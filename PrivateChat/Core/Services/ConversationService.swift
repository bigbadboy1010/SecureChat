import Combine
import CryptoKit
import Foundation

enum TransportPayloadKind: String, Codable, Equatable {
    case message
    case deliveryReceipt
    case attachmentChunk
}

struct TransportMessagePayload: Codable, Equatable {
    let version: Int
    let kind: TransportPayloadKind
    let messageID: UUID
    let conversationID: UUID?
    let senderID: String
    let recipientID: String
    let body: String?
    let createdAt: Date
    let deliveredMessageID: UUID?
    let attachment: ChatAttachment?
    let attachmentSHA256: String?
    let chunkIndex: Int?
    let totalChunks: Int?
    let chunkDataBase64: String?

    init(
        version: Int,
        kind: TransportPayloadKind,
        messageID: UUID,
        conversationID: UUID?,
        senderID: String,
        recipientID: String,
        body: String?,
        createdAt: Date,
        deliveredMessageID: UUID?,
        attachment: ChatAttachment? = nil,
        attachmentSHA256: String? = nil,
        chunkIndex: Int? = nil,
        totalChunks: Int? = nil,
        chunkDataBase64: String? = nil
    ) {
        self.version = version
        self.kind = kind
        self.messageID = messageID
        self.conversationID = conversationID
        self.senderID = senderID
        self.recipientID = recipientID
        self.body = body
        self.createdAt = createdAt
        self.deliveredMessageID = deliveredMessageID
        self.attachment = attachment
        self.attachmentSHA256 = attachmentSHA256
        self.chunkIndex = chunkIndex
        self.totalChunks = totalChunks
        self.chunkDataBase64 = chunkDataBase64
    }
}

/// Produces stable relay packet identifiers for attachment chunks.
///
/// Retrying an attachment must reuse the same packet IDs. Otherwise every
/// attempt consumes another set of recipient-queue slots even though the
/// encrypted attachment message itself has not changed.
enum AttachmentPacketIdentifier {
    nonisolated static func make(
        messageID: UUID,
        chunkIndex: Int,
        recipientID: String
    ) -> UUID {
        let input = "securechat/attachment-packet/v1/\(messageID.uuidString.lowercased())/\(chunkIndex)/\(recipientID)"
        var bytes = Array(SHA256.hash(data: Data(input.utf8)).prefix(16))

        // Keep the identifier compatible with relay validators that accept
        // version-4 UUIDs while deriving its payload deterministically.
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

private struct OutboundMessageContext {
    let conversationID: UUID
    let peerID: String?
    let message: ChatMessage
}

private struct DeliveryReceiptContext {
    let originalMessageID: UUID
    let originalConversationID: UUID?
    let originalSenderID: String
}

private struct InboundPacketProcessResult {
    let didProcessMessage: Bool
    let isDuplicate: Bool
    let deliveryReceiptContext: DeliveryReceiptContext?
}

@MainActor
final class ConversationService: ObservableObject {
    // The Double-Ratchet implementation remains in-tree for continued
    // development and unit testing, but it is deliberately disabled in
    // the TestFlight/production message path until its session bootstrap,
    // turn rotation and crash-persistence semantics have completed an
    // external cryptographic review. Protocol v2 (packet version 2) stays
    // active and retains signed-envelope + AES-GCM E2E protection.
    private static let experimentalDoubleRatchetEnabled = false
    static let maximumAttachmentBytes = 8 * 1_048_576
    private static let attachmentChunkBytes = 64 * 1_024
    private static let relayBulkRequestIntervalSeconds: TimeInterval = 0.65
    @Published private(set) var conversations: [StoredConversation]
    @Published private(set) var trustedPeers: [TrustedPeer]
    @Published private(set) var securityState: AppSecurityState
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var isRelaySyncRunning: Bool
    @Published private(set) var lastRelaySyncSummary: RelayInboxSyncSummary?
    @Published private(set) var isRelayHealthCheckRunning: Bool
    @Published private(set) var lastRelayHealthMessage: String?
    @Published private(set) var lastTransportDiagnosticMessage: String?
    @Published private(set) var isOutboxRetryRunning: Bool
    @Published private(set) var lastOutboxRetrySummary: OutboxRetrySummary?
    @Published private(set) var isRelayAutoPollingActive: Bool
    @Published private(set) var isRelayStatsRunning: Bool
    @Published private(set) var lastRelayStatsSnapshot: RelayStatsSnapshot?
    @Published private(set) var isRelayPurgeRunning: Bool
    @Published private(set) var lastRelayPurgeSummary: RelayPurgeSummary?
    @Published private(set) var isLocalRetentionPurgeRunning: Bool
    @Published private(set) var lastLocalRetentionSummary: LocalRetentionSummary?
    @Published private(set) var relayConnectivityStatus: RelayConnectivityStatus
    @Published private(set) var runtimeSecuritySnapshot: RuntimeSecuritySnapshot
    @Published private(set) var securityAISnapshot: SecurityAISnapshot
    @Published private(set) var localIdentity: LocalIdentity
    @Published private(set) var criticalSessionFailure: String?

    // Standalone service fixtures retain their established behavior.
    // The production AppContainer closes this gate immediately at init,
    // and opens it only after device-owner authentication succeeds.
    private var userSessionAuthorized = true
    private var userSessionGeneration = UUID()

    var currentUserSessionID: UUID? {
        userSessionAuthorized && criticalSessionFailure == nil ? userSessionGeneration : nil
    }

    func isCurrentUserSession(_ identifier: UUID?) -> Bool {
        identifier != nil && identifier == currentUserSessionID && !Task.isCancelled
    }

    @discardableResult
    func beginUserSession() -> Bool {
        guard !Task.isCancelled else { return false }
        if currentUserSessionID != nil { return true }
        if criticalSessionFailure != nil {
            do {
                // Repair an interrupted security transaction from the
                // retained, fail-closed in-memory state before reopening.
                try peerTrustStore.savePeers(trustedPeers)
                try messageStore.save(conversations)
                criticalSessionFailure = nil
            } catch {
                lastErrorMessage = "Sicherheitszustand konnte nicht dauerhaft gespeichert werden. " + error.localizedDescription
                return false
            }
        }
        userSessionGeneration = UUID()
        userSessionAuthorized = true
        guard resetInterruptedOutgoingMessages() else {
            failClosedForUndurableSecurityState()
            return false
        }
        return true
    }

    func endUserSession() {
        userSessionAuthorized = false
        userSessionGeneration = UUID()
        stopRelayAutoSyncLoop()
        isRelaySyncRunning = false
        isOutboxRetryRunning = false
        isRelayStatsRunning = false
        isRelayPurgeRunning = false
        isRelayHealthCheckRunning = false
    }

    private enum SessionAccessError: LocalizedError {
        case locked
        var errorDescription: String? { "PrivateRoom ist gesperrt. Bitte erneut entsperren." }
    }

    private func authorizeUserAction() -> Bool {
        guard currentUserSessionID != nil, !Task.isCancelled else {
            lastErrorMessage = criticalSessionFailure ?? SessionAccessError.locked.localizedDescription
            return false
        }
        return true
    }

    private func requireUserSession() throws -> UUID {
        guard let sessionID = currentUserSessionID, !Task.isCancelled else { throw SessionAccessError.locked }
        return sessionID
    }

    private func ensureUserSession(_ sessionID: UUID) throws {
        guard isCurrentUserSession(sessionID) else { throw SessionAccessError.locked }
    }

    private func failClosedForUndurableSecurityState() {
        criticalSessionFailure = "Eine Sicherheitsänderung konnte nicht dauerhaft gespeichert werden. Bitte erneut entsperren, um sie sicher zu speichern."
        lastErrorMessage = criticalSessionFailure
        endUserSession()
    }

    private let messageStore: MessageStoring
    private let draftStore: DraftStoring
    private let peerTrustStore: PeerTrustStoring
    private let settingsStore: SecuritySettingsStoring
    private let relayPacketLedgerStore: RelayPacketLedgerStoring
    private let identityManager: IdentityManaging
    private let crypto: CryptoServicing
    private let transportCoordinator: TransportCoordinating
    private let attachmentStore: AttachmentStoring
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var relayPacketLedger: RelayPacketLedger
    // Sprint 9D: the v2 (Double Ratchet) envelope
    // router. Owned by the service so the v2 path
    // has the same lifetime as the v1 path. The
    // router is library-complete; a future Sprint
    // 10 will swap the in-memory store for the
    // keychain-backed one.
    private let ratchetRouter: RatchetEnvelopeRouter
    private let ratchetStore: DoubleRatchetStoring
    private var ratchetObservations: [RatchetSentinelObservation] = []
    private var relayAutoSyncTask: Task<Void, Never>?
    private var relayAutoSyncGeneration = UUID()
    private var nextRelayBulkRequestAt = Date.distantPast

    init(
        localIdentity: LocalIdentity,
        messageStore: MessageStoring,
        draftStore: DraftStoring,
        peerTrustStore: PeerTrustStoring,
        settingsStore: SecuritySettingsStoring,
        relayPacketLedgerStore: RelayPacketLedgerStoring,
        identityManager: IdentityManaging,
        crypto: CryptoServicing,
        transportCoordinator: TransportCoordinating,
        attachmentStore: AttachmentStoring? = nil
    ) {
        self.localIdentity = localIdentity
        self.messageStore = messageStore
        self.draftStore = draftStore
        self.peerTrustStore = peerTrustStore
        self.settingsStore = settingsStore
        self.relayPacketLedgerStore = relayPacketLedgerStore
        self.identityManager = identityManager
        self.crypto = crypto
        self.transportCoordinator = transportCoordinator
        self.attachmentStore = attachmentStore ?? InMemoryAttachmentStore()
        self.encoder = RelayWireCoding.makeEncoder()
        self.decoder = DateCoding.makeDecoder()
        self.relayPacketLedger = .empty
        self.conversations = []
        self.trustedPeers = []
        // Sprint 10A: own a Keychain-backed
        // Double Ratchet store so the v2 envelope
        // state survives an app relaunch. The
        // first call to register/open a
        // RatchetChannel will hit the keychain
        // (account: "ratchet.<peerID>"); subsequent
        // app launches will pick the same session
        // up and continue the chain instead of
        // falling back to v1.
        let ratchetStore: DoubleRatchetStoring = KeychainDoubleRatchetStore()
        self.ratchetStore = ratchetStore
        self.ratchetRouter = RatchetEnvelopeRouter(
            store: ratchetStore,
            localIdentityID: { localIdentity.id }
        )
        self.securityState = .secureDefault
        self.lastRelaySyncSummary = nil
        self.isRelaySyncRunning = false
        self.isRelayHealthCheckRunning = false
        self.lastRelayHealthMessage = nil
        self.lastTransportDiagnosticMessage = nil
        self.isOutboxRetryRunning = false
        self.lastOutboxRetrySummary = nil
        self.isRelayAutoPollingActive = false
        self.isRelayStatsRunning = false
        self.lastRelayStatsSnapshot = nil
        self.isRelayPurgeRunning = false
        self.lastRelayPurgeSummary = nil
        self.isLocalRetentionPurgeRunning = false
        self.lastLocalRetentionSummary = nil
        self.relayConnectivityStatus = .healthy
        self.runtimeSecuritySnapshot = RuntimeSecurityEvaluator.assess()
        self.securityAISnapshot = .empty
    }

    @discardableResult
    func load() -> Bool {
        do {
            conversations = try messageStore.load().sorted { $0.conversation.updatedAt > $1.conversation.updatedAt }
            guard resetInterruptedOutgoingMessages() else { return false }
            trustedPeers = try peerTrustStore.loadPeers()
            try migratePeerSafetyNumbersIfNeeded()
            securityState = try settingsStore.load()
            relayPacketLedger = try relayPacketLedgerStore.load()
            refreshRuntimeSecurityAssessment()
            refreshSecurityAIAssessment()
            lastRelayHealthMessage = nil
            lastTransportDiagnosticMessage = transportDiagnosticSummary()
            lastErrorMessage = nil
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    /// Sprint 27 (2026-06-24): peer-enrollment hook.
    ///
    /// After device unlock, prove possession of this device's signing key.
    /// Only approved beta devices can enroll on the hosted relay. Existing
    /// identities remain immutable; a failure is visible and can be retried
    /// explicitly without replacing keys or silently changing trust.
    @discardableResult
    func enrollLocalPeerIfNeeded() async -> Bool {
        guard authorizeUserAction(), let sessionID = currentUserSessionID else { return false }
        guard securityState.transportMode == .relayAllowed,
              securityState.relayConfiguration.isEnabled,
              securityState.relayConfiguration.isReadyForNetworkRequests else {
            return false
        }
        do {
            let response = try await transportCoordinator.enrollLocalPeer(
                localIdentity,
                relayConfiguration: securityState.relayConfiguration
            )
            try ensureUserSession(sessionID)
            guard response.peerID == localIdentity.id else { throw PrivateChatError.relayInvalidResponse }
            lastRelayHealthMessage = "PrivateRoom ist verbunden."
            lastErrorMessage = nil
            return true
        } catch {
            guard isCurrentUserSession(sessionID) else { return false }
            if case PrivateChatError.relayHTTPError(let status, let code) = error,
               status == 403, code == "beta_admission_required" {
                lastRelayHealthMessage = "Dieses Gerät ist für die geschlossene Beta noch nicht freigegeben."
                lastErrorMessage = "Der Betreiber muss zuerst deine Geräte-ID für die Beta zulassen. Es ist kein gemeinsamer Zugangscode nötig."
            } else {
                lastRelayHealthMessage = "PrivateRoom konnte die Geräteidentität nicht anmelden."
                lastErrorMessage = error.localizedDescription
            }
            return false
        }
    }

    func clearError() {
        lastErrorMessage = nil
    }

    func reportError(_ error: Error) {
        lastErrorMessage = error.localizedDescription
    }

    func loadDraft(conversationID: UUID, legacyUserDefaultsValue: String?, onDurableLoad: () -> Void = {}) -> String {
        guard authorizeUserAction() else { return "" }
        do {
            if let migratedDraft = try draftStore.migrateLegacyDraftIfNeeded(conversationID: conversationID, legacyValue: legacyUserDefaultsValue) {
                onDurableLoad()
                return migratedDraft
            }
            let draft = try draftStore.loadDraft(conversationID: conversationID) ?? ""
            onDurableLoad()
            return draft
        } catch {
            lastErrorMessage = "Entwurf konnte nicht entschlüsselt geladen werden: \(error.localizedDescription)"
            return legacyUserDefaultsValue ?? ""
        }
    }

    @discardableResult
    func saveDraft(_ draft: String, conversationID: UUID) -> Bool {
        guard authorizeUserAction() else { return false }
        do {
            try draftStore.saveDraft(draft, conversationID: conversationID)
            return true
        } catch {
            lastErrorMessage = "Entwurf konnte nicht verschlüsselt gespeichert werden: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func deleteDraft(conversationID: UUID) -> Bool {
        guard authorizeUserAction() else { return false }
        do {
            try draftStore.deleteDraft(conversationID: conversationID)
            return true
        } catch {
            lastErrorMessage = "Entwurf konnte nicht gelöscht werden: \(error.localizedDescription)"
            return false
        }
    }

    func startRelayAutoSyncLoop() {
        guard authorizeUserAction() else { return }
        guard relayAutoSyncTask == nil else {
            return
        }

        let generation = UUID()
        relayAutoSyncGeneration = generation
        relayAutoSyncTask = Task { [weak self] in
            await self?.runRelayAutoSyncLoop(generation: generation)
        }
    }

    func stopRelayAutoSyncLoop() {
        relayAutoSyncGeneration = UUID()
        relayAutoSyncTask?.cancel()
        relayAutoSyncTask = nil
        isRelayAutoPollingActive = false
    }

    private func runRelayAutoSyncLoop(generation: UUID) async {
        guard authorizeUserAction(), isRelayAutoPollingActive == false, relayAutoSyncGeneration == generation else {
            return
        }

        isRelayAutoPollingActive = true
        defer {
            if relayAutoSyncGeneration == generation {
                isRelayAutoPollingActive = false
                relayAutoSyncTask = nil
            }
        }

        while Task.isCancelled == false && relayAutoSyncGeneration == generation && currentUserSessionID != nil {
            if securityState.transportMode == .relayAllowed, securityState.relayConfiguration.isEnabled {
                if shouldBlockRelayDueToConfiguration(showUserFacingError: false, context: "Auto-Sync") == false, shouldPauseRelayRequests(showUserFacingError: false) == false {
                    await syncRelayInbox(showDisabledError: false)
                    guard !Task.isCancelled, relayAutoSyncGeneration == generation, currentUserSessionID != nil else { return }
                    if securityState.relayConfiguration.retryFailedMessagesAutomatically, shouldPauseRelayRequests(showUserFacingError: false) == false {
                        await retryPendingOutboundMessages(showEmptyResult: false)
                    }
                }
            }

            let baseInterval = max(5, min(securityState.relayConfiguration.autoPollingIntervalSeconds, 300))
            let sleepSeconds = relayConnectivityStatus.isPaused ? min(max(relayConnectivityStatus.remainingPauseSeconds, 5), 60) : baseInterval
            try? await Task.sleep(nanoseconds: UInt64(sleepSeconds) * 1_000_000_000)
        }
    }

    @discardableResult
    func createConversation(title: String, peerID: String?) -> UUID? {
        guard authorizeUserAction() else { return nil }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty == false else {
            return nil
        }

        let conversation = Conversation(title: trimmedTitle, peerID: peerID)
        let previous = conversations
        conversations.insert(StoredConversation(conversation: conversation, messages: []), at: 0)
        guard persistConversations() else { conversations = previous; return nil }
        return conversation.id
    }

    @discardableResult
    func createSoloTestConversation() -> UUID? {
        guard authorizeUserAction() else { return nil }
        if let existing = conversations.first(where: { $0.conversation.title == "Solo-Test" && $0.conversation.peerID == nil }) {
            return existing.id
        }

        let conversation = Conversation(title: "Solo-Test", peerID: nil)
        let welcomeMessage = ChatMessage(
            conversationID: conversation.id,
            senderID: "privatechat.system",
            recipientID: localIdentity.id,
            body: "Dies ist ein lokaler Test-Chat. Nachrichten in diesem Chat bleiben auf diesem Gerät und werden nicht an den Relay gesendet.",
            status: .delivered,
            isIncoming: true,
            readAt: Date()
        )
        let hintMessage = ChatMessage(
            conversationID: conversation.id,
            senderID: localIdentity.id,
            recipientID: nil,
            body: "Solo-Test bereit. Du kannst hier den Composer, die verschlüsselte lokale Speicherung und die Chat-UI ohne zweiten Peer testen.",
            status: .delivered,
            isIncoming: false
        )
        let previous = conversations
        conversations.insert(StoredConversation(conversation: conversation, messages: [welcomeMessage, hintMessage]), at: 0)
        guard commitConversationMutation(previous: previous) else { return nil }
        lastTransportDiagnosticMessage = "Solo-Test-Chat lokal angelegt. Kein Relay-Transport erforderlich."
        return conversation.id
    }

    func deleteConversation(id: UUID) {
        guard authorizeUserAction() else { return }
        let previous = conversations
        let removed = conversations.first(where: { $0.id == id })?.messages.compactMap(\.attachment) ?? []
        conversations.removeAll { $0.id == id }
        guard commitConversationMutation(previous: previous) else { return }
        reclaimUnreferencedAttachments(removed)
    }

    func toggleConversationPinned(id: UUID) {
        guard authorizeUserAction() else { return }
        guard let index = conversations.firstIndex(where: { $0.id == id }) else {
            return
        }
        conversations[index].conversation.isPinned.toggle()
        conversations[index].conversation.updatedAt = Date()
        sortConversations()
        persistConversations()
    }

    func toggleConversationArchived(id: UUID) {
        guard authorizeUserAction() else { return }
        guard let index = conversations.firstIndex(where: { $0.id == id }) else {
            return
        }
        conversations[index].conversation.isArchived.toggle()
        conversations[index].conversation.updatedAt = Date()
        sortConversations()
        persistConversations()
    }

    func toggleConversationMuted(id: UUID) {
        guard authorizeUserAction() else { return }
        guard let index = conversations.firstIndex(where: { $0.id == id }) else {
            return
        }
        conversations[index].conversation.isMuted.toggle()
        conversations[index].conversation.updatedAt = Date()
        sortConversations()
        persistConversations()
    }

    func clearConversationMessages(id: UUID) {
        guard authorizeUserAction(), let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let previous = conversations
        let removed = conversations[index].messages.compactMap(\.attachment)
        conversations[index].messages.removeAll()
        conversations[index].conversation.updatedAt = Date()
        sortConversations()
        guard commitConversationMutation(previous: previous) else { return }
        reclaimUnreferencedAttachments(removed)
    }

    func markConversationRead(id: UUID) {
        guard authorizeUserAction() else { return }
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == id }) else {
            return
        }
        var didChange = false
        let now = Date()
        for messageIndex in conversations[conversationIndex].messages.indices {
            let message = conversations[conversationIndex].messages[messageIndex]
            if message.isIncoming, message.readAt == nil {
                conversations[conversationIndex].messages[messageIndex].readAt = now
                didChange = true
            }
        }
        if didChange {
            persistConversations()
        }
    }

    func markAllConversationsRead() {
        guard authorizeUserAction() else { return }
        var didChange = false
        let now = Date()
        for conversationIndex in conversations.indices {
            for messageIndex in conversations[conversationIndex].messages.indices {
                let message = conversations[conversationIndex].messages[messageIndex]
                if message.isIncoming, message.readAt == nil {
                    conversations[conversationIndex].messages[messageIndex].readAt = now
                    didChange = true
                }
            }
        }
        if didChange {
            persistConversations()
        }
    }

    func unreadCount(for conversationID: UUID) -> Int {
        conversations.first(where: { $0.id == conversationID })?.messages.filter { message in
            message.isIncoming && message.readAt == nil
        }.count ?? 0
    }

    func totalUnreadCount() -> Int {
        conversations.reduce(0) { partialResult, storedConversation in
            partialResult + unreadCount(for: storedConversation.id)
        }
    }

    func retryMessage(messageID: UUID, conversationID: UUID) async {
        guard authorizeUserAction(), let sessionID = currentUserSessionID else { return }
        do {
            try await deliverOutboundMessage(messageID: messageID, conversationID: conversationID, sessionID: sessionID)
            try ensureUserSession(sessionID)
            lastErrorMessage = nil
        } catch {
            guard isCurrentUserSession(sessionID) else { return }
            lastErrorMessage = error.localizedDescription
        }
    }

    func deleteMessage(messageID: UUID, conversationID: UUID) {
        guard authorizeUserAction(), let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        let previous = conversations
        let removed = conversations[index].messages.filter { $0.id == messageID }.compactMap(\.attachment)
        conversations[index].messages.removeAll { $0.id == messageID }
        conversations[index].conversation.updatedAt = conversations[index].messages.last?.createdAt ?? Date()
        sortConversations()
        guard commitConversationMutation(previous: previous) else { return }
        reclaimUnreferencedAttachments(removed)
    }

    func toggleMessageStarred(messageID: UUID, conversationID: UUID) {
        guard authorizeUserAction() else { return }
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }
        conversations[conversationIndex].messages[messageIndex].isStarred.toggle()
        persistConversations()
    }

    @discardableResult
    func sendMessage(conversationID: UUID, body: String) async -> Bool {
        guard authorizeUserAction(), let sessionID = currentUserSessionID else { return false }
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedBody.isEmpty == false else {
            return false
        }

        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return false
        }

        guard normalizedBody.utf8.count <= 16_384 else {
            lastErrorMessage = "Die Nachricht ist zu lang. Bitte auf mehrere Nachrichten aufteilen."
            return false
        }
        guard !RelayWireCoding.hasUnsupportedTextControls(normalizedBody) else {
            lastErrorMessage = "Die Nachricht enthält nicht unterstützte Steuerzeichen."
            return false
        }
        let conversation = conversations[index].conversation
        if let peerID = conversation.peerID {
            do { _ = try verifiedPeer(id: peerID) }
            catch { lastErrorMessage = error.localizedDescription; return false }
        }
        let previous = conversations
        let message = ChatMessage(
            conversationID: conversationID,
            senderID: localIdentity.id,
            recipientID: conversation.peerID,
            body: normalizedBody,
            status: .queued,
            isIncoming: false
        )

        conversations[index].messages.append(message)
        conversations[index].conversation.updatedAt = message.createdAt
        sortConversations()
        guard persistConversations() else { conversations = previous; return false }
        deleteDraft(conversationID: conversationID)
        lastTransportDiagnosticMessage = transportDiagnosticSummary()

        do {
            try await deliverOutboundMessage(messageID: message.id, conversationID: conversationID, sessionID: sessionID)
            try ensureUserSession(sessionID)
            lastErrorMessage = nil
        } catch {
            guard isCurrentUserSession(sessionID) else { return false }
            lastErrorMessage = error.localizedDescription
        }
        return true // Accepted into the encrypted outbox, even if the relay is offline.
    }

    @discardableResult
    func sendAttachment(
        conversationID: UUID,
        body: String,
        data: Data,
        kind: ChatAttachmentKind,
        fileName: String,
        mimeType: String
    ) async -> Bool {
        guard authorizeUserAction(), let sessionID = currentUserSessionID else { return false }
        let normalizedFileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMIMEType = mimeType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard data.isEmpty == false else {
            lastErrorMessage = PrivateChatError.attachmentUnavailable.localizedDescription
            return false
        }
        guard data.count <= Self.maximumAttachmentBytes else {
            lastErrorMessage = PrivateChatError.attachmentTooLarge(
                maximumBytes: Self.maximumAttachmentBytes
            ).localizedDescription
            return false
        }
        guard normalizedFileName.isEmpty == false,
              normalizedFileName.utf8.count <= 255,
              normalizedMIMEType.isEmpty == false,
              normalizedMIMEType.utf8.count <= 128 else {
            lastErrorMessage = PrivateChatError.unsupportedAttachment.localizedDescription
            return false
        }
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return false
        }

        guard body.utf8.count <= 16_384 else {
            lastErrorMessage = "Die Nachricht ist zu lang."
            return false
        }
        guard !RelayWireCoding.hasUnsupportedTextControls(body) else {
            lastErrorMessage = "Die Nachricht enthält nicht unterstützte Steuerzeichen."
            return false
        }
        if let peerID = conversations[index].conversation.peerID {
            do { _ = try verifiedPeer(id: peerID) }
            catch { lastErrorMessage = error.localizedDescription; return false }
        }
        let previous = conversations
        let attachment = ChatAttachment(
            id: UUID(),
            kind: kind,
            fileName: normalizedFileName,
            mimeType: normalizedMIMEType,
            byteCount: data.count
        )

        do {
            try attachmentStore.saveAttachment(id: attachment.id, data: data)
        } catch {
            guard isCurrentUserSession(sessionID) else { return false }
            lastErrorMessage = error.localizedDescription
            return false
        }

        let conversation = conversations[index].conversation
        let message = ChatMessage(
            conversationID: conversationID,
            senderID: localIdentity.id,
            recipientID: conversation.peerID,
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            status: .queued,
            isIncoming: false,
            attachment: attachment
        )
        conversations[index].messages.append(message)
        conversations[index].conversation.updatedAt = message.createdAt
        sortConversations()
        guard persistConversations() else {
            conversations = previous
            try? attachmentStore.deleteAttachment(id: attachment.id)
            return false
        }
        deleteDraft(conversationID: conversationID)

        do {
            try await deliverOutboundMessage(messageID: message.id, conversationID: conversationID, sessionID: sessionID)
            try ensureUserSession(sessionID)
            lastErrorMessage = nil
        } catch {
            guard isCurrentUserSession(sessionID) else { return false }
            lastErrorMessage = error.localizedDescription
        }
        return true
    }

    func attachmentData(for attachment: ChatAttachment) throws -> Data {
        _ = try requireUserSession()
        return try attachmentStore.loadAttachment(id: attachment.id)
    }

    func syncRelayInbox() async {
        await syncRelayInbox(showDisabledError: true)
    }

    func retryPendingOutboundMessages() async {
        await retryPendingOutboundMessages(showEmptyResult: true)
    }

    func retryPendingOutboundMessages(conversationID: UUID) async {
        await retryPendingOutboundMessages(showEmptyResult: true, conversationID: conversationID)
    }

    func fetchRelayStats() async {
        guard authorizeUserAction(), let sessionID = currentUserSessionID else { return }
        guard isRelayStatsRunning == false else {
            return
        }
        guard securityState.transportMode == .relayAllowed, securityState.relayConfiguration.isEnabled else {
            let message = PrivateChatError.relayDisabled.localizedDescription
            lastTransportDiagnosticMessage = message
            lastErrorMessage = message
            return
        }

        guard shouldBlockRelayForRuntimeRisk(showUserFacingError: true, context: "Relay-Stats") == false else {
            return
        }
        guard shouldBlockRelayDueToConfiguration(showUserFacingError: true, context: "Relay-Stats") == false else {
            return
        }

        isRelayStatsRunning = true
        defer { if userSessionGeneration == sessionID { isRelayStatsRunning = false } }

        do {
            let response = try await transportCoordinator.fetchRelayStats(relayConfiguration: securityState.relayConfiguration)
            try ensureUserSession(sessionID)
            lastRelayStatsSnapshot = RelayStatsSnapshot(
                storedPackets: response.storedPackets,
                activeRecipients: response.activeRecipients,
                acknowledgedPacketTombstones: response.acknowledgedPacketTombstones,
                fetchedAt: Date()
            )
            registerRelaySuccess(message: "Relay-Stats aktualisiert: \(response.storedPackets) Pakete, \(response.activeRecipients) Empfänger, \(response.acknowledgedPacketTombstones) ACK-Tombstones.")
            lastErrorMessage = nil
        } catch {
            guard isCurrentUserSession(sessionID) else { return }
            registerRelayFailure(error, showUserFacingError: true, context: "Relay-Stats")
        }
    }

    func purgeRelayInbox() async {
        guard authorizeUserAction(), let sessionID = currentUserSessionID else { return }
        guard isRelayPurgeRunning == false else {
            return
        }
        guard securityState.transportMode == .relayAllowed, securityState.relayConfiguration.isEnabled else {
            let message = PrivateChatError.relayDisabled.localizedDescription
            lastTransportDiagnosticMessage = message
            lastErrorMessage = message
            return
        }

        guard shouldBlockRelayForRuntimeRisk(showUserFacingError: true, context: "Relay-Inbox bereinigen") == false else {
            return
        }
        guard shouldBlockRelayDueToConfiguration(showUserFacingError: true, context: "Relay-Inbox bereinigen") == false else {
            return
        }

        isRelayPurgeRunning = true
        defer { if userSessionGeneration == sessionID { isRelayPurgeRunning = false } }

        do {
            let response = try await transportCoordinator.purgeRelayInbox(recipientID: localIdentity.id, relayConfiguration: securityState.relayConfiguration)
            try ensureUserSession(sessionID)
            lastRelayPurgeSummary = RelayPurgeSummary(deletedCount: response.deletedCount, recipientID: response.recipientID, completedAt: Date())
            registerRelaySuccess(message: "Relay-Inbox bereinigt: \(response.deletedCount) Paket(e) für diese Identität entfernt.")
            await fetchRelayStats()
            try ensureUserSession(sessionID)
            lastErrorMessage = nil
        } catch {
            guard isCurrentUserSession(sessionID) else { return }
            registerRelayFailure(error, showUserFacingError: true, context: "Relay-Inbox bereinigen")
        }
    }

    func purgeExpiredLocalMessages() {
        guard authorizeUserAction(), isLocalRetentionPurgeRunning == false else { return }
        isLocalRetentionPurgeRunning = true
        defer { isLocalRetentionPurgeRunning = false }
        let previous = conversations
        let cutoff = Date().addingTimeInterval(-TimeInterval(securityState.localMessageRetentionDays) * 86_400)
        var removed: [ChatAttachment] = []
        var deletedMessages = 0
        for index in conversations.indices {
            removed += conversations[index].messages.filter { $0.createdAt < cutoff }.compactMap(\.attachment)
            let originalCount = conversations[index].messages.count
            conversations[index].messages.removeAll { $0.createdAt < cutoff }
            deletedMessages += originalCount - conversations[index].messages.count
            conversations[index].conversation.updatedAt = conversations[index].messages.last?.createdAt ?? conversations[index].conversation.updatedAt
        }
        conversations.removeAll { $0.messages.isEmpty && $0.conversation.createdAt < cutoff }
        sortConversations()
        guard commitConversationMutation(previous: previous) else { return }
        reclaimUnreferencedAttachments(removed)
        let deletedConversations = previous.count - conversations.count
        lastLocalRetentionSummary = LocalRetentionSummary(deletedMessages: deletedMessages, deletedConversations: deletedConversations, completedAt: Date())
        lastTransportDiagnosticMessage = "Lokale Retention bereinigt: \(deletedMessages) Nachricht(en), \(deletedConversations) leere Chat(s) gelöscht."
    }

    func checkRelayHealth() async {
        guard authorizeUserAction(), let sessionID = currentUserSessionID else { return }
        guard isRelayHealthCheckRunning == false else {
            return
        }

        isRelayHealthCheckRunning = true
        defer { if userSessionGeneration == sessionID { isRelayHealthCheckRunning = false } }
        lastTransportDiagnosticMessage = "Relay-Prüfung gestartet. \(transportDiagnosticSummary())"
        guard shouldBlockRelayForRuntimeRisk(showUserFacingError: true, context: "Relay-Prüfung") == false else {
            return
        }
        guard shouldBlockRelayDueToConfiguration(showUserFacingError: true, context: "Relay-Prüfung") == false else {
            return
        }

        do {
            let status = try await transportCoordinator.checkRelayHealth(relayConfiguration: securityState.relayConfiguration)
            try ensureUserSession(sessionID)
            registerRelaySuccess(message: "Relay-Prüfung erfolgreich. \(transportDiagnosticSummary())")
            lastRelayHealthMessage = status.isHealthy
                ? "Relay erreichbar. Policy: \(status.hardeningSummary)"
                : "Relay antwortet unerwartet: \(status.status)"
            lastErrorMessage = nil
        } catch {
            guard isCurrentUserSession(sessionID) else { return }
            lastRelayHealthMessage = nil
            registerRelayFailure(error, showUserFacingError: true, context: "Relay-Prüfung")
        }
    }

    @discardableResult
    func importPeer(from encodedPayload: String) -> Bool {
        guard authorizeUserAction() else { return false }
        let previousPeers = trustedPeers
        do {
            let peer = try identityManager.importPairingPayload(encodedPayload)
            guard peer.id != localIdentity.id else {
                throw PrivateChatError.invalidPairingPayload
            }

            if let existingIndex = trustedPeers.firstIndex(where: { $0.id == peer.id }) {
                let existingPeer = trustedPeers[existingIndex]
                let keyChanged = existingPeer.signingPublicKeyBase64 != peer.signingPublicKeyBase64 || existingPeer.keyAgreementPublicKeyBase64 != peer.keyAgreementPublicKeyBase64
                if keyChanged {
                    var blockedPeer = peer
                    blockedPeer.trustState = .blocked
                    trustedPeers[existingIndex] = blockedPeer
                    lastErrorMessage = "Kontakt-Schlüssel haben sich geändert. Kontakt wurde blockiert."
                } else {
                    var updatedPeer = existingPeer
                    updatedPeer.displayName = peer.displayName
                    trustedPeers[existingIndex] = updatedPeer
                    lastErrorMessage = nil
                }
            } else {
                trustedPeers.append(peer)
                lastErrorMessage = nil
            }
            try peerTrustStore.savePeers(trustedPeers)

            // Sprint 10C: opt the new peer into the
            // v2 (Double Ratchet) envelope by
            // registering a fresh RatchetChannel.
            // The X3DH bundle material is built
            // from the local + remote key-agreement
            // keys and the PairingPayload.createdAt
            // timestamps; it is persisted to the
            // Keychain via the
            // KeychainDoubleRatchetStore, so the
            // next app relaunch picks the same
            // session up.
            //
            // A pairing whose signing key matches a
            // key-changed / blocked event is
            // intentionally NOT registered, so the
            // blocked peer does not accidentally
            // end up with a v2 envelope.
            registerRatchetChannelForPeer(peer, encodedPayload: encodedPayload)
            return lastErrorMessage == nil
        } catch {
            let undurableBlock = trustedPeers.contains { peer in
                peer.trustState == .blocked && previousPeers.contains { $0.id == peer.id && $0.trustState != .blocked }
            }
            if undurableBlock { failClosedForUndurableSecurityState() }
            else { trustedPeers = previousPeers }
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    /// Sprint 10C: build and persist a
    /// RatchetChannel for a newly-imported peer.
    /// The X3DH bundle material needs both the
    /// raw PairingPayload (for `createdAt`) and
    /// the local key-agreement private key, so
    /// we decode the payload ourselves before
    /// handing off to `RatchetChannel.register`.
    private func registerRatchetChannelForPeer(
        _ peer: TrustedPeer,
        encodedPayload: String
    ) {
        guard Self.experimentalDoubleRatchetEnabled else {
            return
        }
        // Skip v2 registration for blocked peers
        // (key-changed during re-pairing).
        guard peer.trustState != .blocked else {
            return
        }
        // Skip if a channel already exists for
        // this peer (re-import of an existing
        // peer must not overwrite the ratchet
        // state and lose the message chain).
        if (try? ratchetStore.load(peerID: peer.id)) != nil {
            return
        }
        do {
            let normalized = encodedPayload
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "privatechat://pairing/", with: "")
                .replacingOccurrences(of: "securechat://pairing/", with: "")
            guard let payloadData = Base64URL.decode(normalized) else {
                return
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let payload = try? decoder.decode(
                PairingPayload.self, from: payloadData
            ) else {
                return
            }
            guard let remoteKAPubData = Data(
                base64Encoded: peer.keyAgreementPublicKeyBase64
            ),
                  let remoteSigningPubData = Data(
                base64Encoded: peer.signingPublicKeyBase64
            ) else {
                return
            }
            let remoteKAPub = try Curve25519.KeyAgreement.PublicKey(
                rawRepresentation: remoteKAPubData
            )
            // The remote signing public key is
            // not used for ECDH in the current
            // X3DH single-DH variant; we still
            // pass it so the call signature is
            // future-proof when Sprint 11 adds
            // the 2-DH variant.
            let remoteSigningPub = try Curve25519.Signing.PublicKey(
                rawRepresentation: remoteSigningPubData
            )
            let localKAPriv = localIdentity.keyAgreementPrivateKey
            _ = try RatchetChannel.register(
                peerID: peer.id,
                localKeyAgreementPrivateKey: localKAPriv,
                remoteKeyAgreementPublicKey: remoteKAPub,
                remoteSigningPublicKey: remoteSigningPub,
                localPayloadCreatedAt: payload.createdAt,
                remotePayloadCreatedAt: payload.createdAt,
                store: ratchetStore
            )
        } catch {
            // Soft failure: the v1 path still
            // works for this peer; the user will
            // see a "session still on v1" finding
            // in the Sentinel until the next
            // successful re-pairing.
        }
    }

    @discardableResult
    func verifyPeer(id: String) -> Bool {
        guard authorizeUserAction() else { return false }
        guard let index = trustedPeers.firstIndex(where: { $0.id == id }),
              trustedPeers[index].trustState != .blocked,
              let signing = Data(base64Encoded: trustedPeers[index].signingPublicKeyBase64), signing.count == 32,
              let agreement = Data(base64Encoded: trustedPeers[index].keyAgreementPublicKeyBase64), agreement.count == 32 else {
            lastErrorMessage = PrivateChatError.peerNotTrusted.localizedDescription
            return false
        }
        let expected = SafetyNumberV3.make(
            localSigningPublicKeyData: localIdentity.signingPublicKeyData,
            localKeyAgreementPublicKeyData: localIdentity.keyAgreementPublicKeyData,
            remoteSigningPublicKeyData: signing,
            remoteKeyAgreementPublicKeyData: agreement
        )
        guard trustedPeers[index].safetyNumber == expected, expected.hasPrefix("SC3 ") else {
            trustedPeers[index].trustState = .unverified
            trustedPeers[index].lastVerifiedAt = nil
            _ = persistPeers()
            lastErrorMessage = "Bitte den neuen Kontakt-Code importieren und die SC3 Sicherheitsnummer auf beiden Geräten vergleichen."
            return false
        }
        let previous = trustedPeers[index]
        trustedPeers[index].trustState = .verified
        trustedPeers[index].lastVerifiedAt = Date()
        guard persistPeers() else { trustedPeers[index] = previous; return false }
        return true
    }

    func blockPeer(id: String) {
        guard authorizeUserAction(), let index = trustedPeers.firstIndex(where: { $0.id == id }) else { return }
        trustedPeers[index].trustState = .blocked
        trustedPeers[index].lastVerifiedAt = nil
        guard persistPeers() else {
            // Retain the block in memory and stop all sensitive operations
            // until this exact blocked state can be durably persisted.
            failClosedForUndurableSecurityState()
            return
        }
        revokeExperimentalRatchetState(peerID: id)
    }

    func unblockPeerAsUnverified(id: String) {
        guard authorizeUserAction(), let index = trustedPeers.firstIndex(where: { $0.id == id }) else { return }
        let previous = trustedPeers[index]
        trustedPeers[index].trustState = .unverified
        trustedPeers[index].lastVerifiedAt = nil
        guard persistPeers() else { trustedPeers[index] = previous; return }
        revokeExperimentalRatchetState(peerID: id)
    }

    func deletePeer(id: String) {
        guard authorizeUserAction() else { return }
        let previousPeers = trustedPeers
        let previousConversations = conversations
        let removed = conversations.filter { $0.conversation.peerID == id }.flatMap { $0.messages.compactMap(\.attachment) }
        trustedPeers.removeAll { $0.id == id }
        guard persistPeers() else {
            trustedPeers = previousPeers
            failClosedForUndurableSecurityState()
            return
        }
        conversations.removeAll { $0.conversation.peerID == id }
        guard persistConversations() else {
            let error = lastErrorMessage
            conversations = previousConversations
            trustedPeers = previousPeers
            if !persistPeers() { failClosedForUndurableSecurityState() }
            else { lastErrorMessage = error }
            return
        }
        reclaimUnreferencedAttachments(removed)
        revokeExperimentalRatchetState(peerID: id)
    }

    func makeLocalPairingCode() throws -> String {
        _ = try requireUserSession()
        return try identityManager.exportPairingPayload(identity: localIdentity)
    }

    func exportLocalPairingCode() -> String {
        (try? makeLocalPairingCode()) ?? ""
    }

    @discardableResult
    func updateLocalDisplayName(_ displayName: String) -> Bool {
        guard authorizeUserAction() else { return false }
        do {
            localIdentity = try identityManager.updateDisplayName(displayName, identity: localIdentity)
            lastTransportDiagnosticMessage = "Anzeigename aktualisiert. Der neue Name wird im nächsten Pairing-Code verwendet."
            lastErrorMessage = nil
            return true
        } catch {
            lastErrorMessage = "Anzeigename konnte nicht gespeichert werden: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func updateSecurityState(_ state: AppSecurityState) -> Bool {
        guard authorizeUserAction() else { return false }
        do {
            let migratedState = state.migratedForSecureChatProduction()
            try settingsStore.save(migratedState)
            let previousRelayURL = securityState.relayConfiguration.baseURLString
            securityState = migratedState
            refreshRuntimeSecurityAssessment()
            refreshSecurityAIAssessment()
            lastRelayHealthMessage = nil
            if previousRelayURL != migratedState.relayConfiguration.baseURLString {
                relayConnectivityStatus = .healthy
            }
            lastTransportDiagnosticMessage = transportDiagnosticSummary(for: migratedState)
            lastErrorMessage = nil
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func enablePrivateRoomRelay() async -> Bool {
        guard authorizeUserAction(), let sessionID = currentUserSessionID else { return false }
        var state = securityState
        state.transportMode = .relayAllowed
        state.relayConfiguration.isEnabled = true
        state.relayConfiguration.baseURLString = SecureChatProductionProfile.relayBaseURLString
        state.relayConfiguration.registrationToken = nil
        state.relayConfiguration.verboseRelayLogging = false
        guard updateSecurityState(state) else { return false }
        let enrolled = await enrollLocalPeerIfNeeded()
        guard isCurrentUserSession(sessionID) else { return false }
        return enrolled
    }

    func verifiedPeers() -> [TrustedPeer] {
        trustedPeers
            .filter { $0.trustState == .verified }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func peerDisplayName(for peerID: String?) -> String? {
        guard let peerID else {
            return nil
        }
        return trustedPeers.first { $0.id == peerID }?.displayName
    }

    func renameConversation(id: UUID, title: String) {
        guard authorizeUserAction() else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty == false,
              let index = conversations.firstIndex(where: { $0.id == id }) else {
            return
        }
        conversations[index].conversation.title = trimmedTitle
        conversations[index].conversation.updatedAt = Date()
        sortConversations()
        persistConversations()
    }

    func appDiagnosticsReport() -> String {
        guard authorizeUserAction() else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium

        let relayActiveText = securityState.relayConfiguration.isEnabled ? "ja" : "nein"
        let relayURLText = securityState.relayConfiguration.baseURLString.isEmpty ? "nicht gesetzt" : securityState.relayConfiguration.baseURLString
        let relayTokenText = securityState.relayConfiguration.hasUsableClientToken ? "gesetzt" : "fehlt/ungültig"
        let relayProductionText = SecureChatProductionProfile.isConfiguredProductionRelay(securityState.relayConfiguration.baseURLString) ? "ja" : "nein"
        let verboseLoggingText = securityState.relayConfiguration.verboseRelayLogging ? "aktiv" : "leise"
        let previewProtectionText = securityState.hideMessagePreviews ? "aktiv" : "aus"
        let keyboardProtectionText = securityState.reduceKeyboardSuggestions ? "ja" : "nein"
        let runtimeWarningText = securityState.warnOnRuntimeRisk ? "aktiv" : "aus"
        let runtimeBlockText = securityState.restrictRelayOnRuntimeRisk ? "aktiv" : "aus"

        var lines: [String] = []
        lines.append("PrivateChat Diagnose")
        lines.append("Erstellt: \(formatter.string(from: Date()))")
        lines.append("Lokale Identity: \(String(localIdentity.id.prefix(16)))…")
        lines.append("Transportmodus: \(securityState.transportMode.rawValue)")
        lines.append("Relay aktiv: \(relayActiveText)")
        lines.append("Relay URL: \(relayURLText)")
        lines.append("Relay Token: \(relayTokenText)")
        lines.append("Production Relay: \(relayProductionText)")
        lines.append("Auto-Polling: \(securityState.relayConfiguration.autoPollingIntervalSeconds)s")
        lines.append("Inbox Limit: \(securityState.relayConfiguration.inboxPollingLimit)")
        lines.append("Relay Erfolgslogs: \(verboseLoggingText)")
        lines.append("Relay Verbindung: \(relayConnectivityStatus.localizedStateTitle), Fehlerfolge: \(relayConnectivityStatus.consecutiveFailureCount)")
        lines.append("Vorschau-Schutz: \(previewProtectionText)")
        lines.append("Keyboard-Suggestions reduziert: \(keyboardProtectionText)")
        lines.append("Runtime-Warnungen: \(runtimeWarningText)")
        lines.append("Runtime-Relay-Block: \(runtimeBlockText)")
        lines.append("Runtime-Risiko: \(runtimeSecuritySnapshot.localizedSummary)")
        lines.append("Runtime-Findings: \(runtimeSecuritySnapshot.findings.count)")
        lines.append("Security Sentinel: \(securityAISnapshot.summary)")
        lines.append("Security Sentinel Findings: \(securityAISnapshot.findings.count)")
        lines.append("Retention: \(securityState.localMessageRetentionDays) Tage")
        lines.append("Chats aktiv: \(activeConversationCount())")
        lines.append("Chats archiviert: \(archivedConversationCount())")
        lines.append("Kontakte verifiziert: \(verifiedPeerCount())")
        lines.append("Kontakte blockiert: \(blockedPeerCount())")
        lines.append("Ungelesen: \(totalUnreadCount())")
        lines.append("Outbox ausstehend: \(pendingOutboxCount())")
        lines.append("Fehlerhafte Nachrichten: \(failedMessageCount())")
        lines.append("Markierte Nachrichten: \(starredMessageCount())")
        lines.append("Paket-Ledger: \(relayLedgerEntryCount())")
        lines.append("Receipt-Ledger: \(deliveryReceiptLedgerCount())")
        if let stats = lastRelayStatsSnapshot {
            lines.append("Relay Stats: \(stats.storedPackets) Pakete, \(stats.activeRecipients) Empfänger, \(stats.acknowledgedPacketTombstones) ACK-Tombstones")
        }
        if let summary = lastRelaySyncSummary {
            lines.append("Letzter Sync: \(summary.processedCount) verarbeitet, \(summary.duplicateCount) Duplikate, \(summary.deletedCount) ACKs, \(summary.deliveryReceiptSentCount) Receipts")
        }
        if let message = lastTransportDiagnosticMessage {
            lines.append("Letzte Transportdiagnose: \(message)")
        }
        return lines.joined(separator: "\n")
    }

    func pendingOutboxCount() -> Int {
        conversations.reduce(0) { partialResult, storedConversation in
            partialResult + storedConversation.messages.filter { message in
                message.isIncoming == false &&
                message.recipientID != nil &&
                (message.status == .queued || message.status == .failed)
            }.count
        }
    }

    func verifiedPeerCount() -> Int {
        trustedPeers.filter { $0.trustState == .verified }.count
    }

    func blockedPeerCount() -> Int {
        trustedPeers.filter { $0.trustState == .blocked }.count
    }

    func archivedConversationCount() -> Int {
        conversations.filter { $0.conversation.isArchived }.count
    }

    func activeConversationCount() -> Int {
        conversations.filter { $0.conversation.isArchived == false }.count
    }


    func mutedConversationCount() -> Int {
        conversations.filter { $0.conversation.isMuted }.count
    }

    func starredMessageCount() -> Int {
        conversations.reduce(0) { partialResult, storedConversation in
            partialResult + storedConversation.messages.filter { $0.isStarred }.count
        }
    }

    func failedMessageCount() -> Int {
        conversations.reduce(0) { partialResult, storedConversation in
            partialResult + storedConversation.messages.filter { $0.status == .failed }.count
        }
    }

    func analytics(for conversationID: UUID) -> ConversationAnalyticsSnapshot {
        guard let storedConversation = conversations.first(where: { $0.id == conversationID }) else {
            return ConversationAnalyticsSnapshot(messageCount: 0, incomingCount: 0, outgoingCount: 0, starredCount: 0, failedCount: 0, pendingCount: 0, unreadCount: 0)
        }
        let messages = storedConversation.messages
        return ConversationAnalyticsSnapshot(
            messageCount: messages.count,
            incomingCount: messages.filter { $0.isIncoming }.count,
            outgoingCount: messages.filter { $0.isIncoming == false }.count,
            starredCount: messages.filter { $0.isStarred }.count,
            failedCount: messages.filter { $0.status == .failed }.count,
            pendingCount: messages.filter { $0.status == .queued || $0.status == .sending }.count,
            unreadCount: messages.filter { $0.isIncoming && $0.readAt == nil }.count
        )
    }
    func exportTranscript(for conversationID: UUID) -> String {
        guard authorizeUserAction() else { return "" }
        guard let storedConversation = conversations.first(where: { $0.id == conversationID }) else {
            return "PrivateRoom Export\nChat nicht gefunden."
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var lines: [String] = []
        lines.append("PrivateRoom Export")
        lines.append("Chat: \(storedConversation.conversation.title)")
        lines.append("Chat-ID: \(storedConversation.id.uuidString)")
        if let peerID = storedConversation.conversation.peerID {
            lines.append("Peer: \(peerDisplayName(for: peerID) ?? peerID)")
        } else {
            lines.append("Typ: Lokaler Notiz-Chat")
        }
        lines.append("Erstellt: \(formatter.string(from: storedConversation.conversation.createdAt))")
        lines.append("Exportiert: \(formatter.string(from: Date()))")
        lines.append(String(repeating: "-", count: 48))

        for message in storedConversation.messages.sorted(by: { $0.createdAt < $1.createdAt }) {
            let direction = message.isIncoming ? "Eingehend" : "Ausgehend"
            let marker = message.isStarred ? " ★" : ""
            lines.append("[\(formatter.string(from: message.createdAt))] \(direction) • \(message.status.localizedTitle)\(marker)")
            lines.append(message.body)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    func relayLedgerEntryCount() -> Int {
        relayPacketLedger.entries.count
    }

    func deliveryReceiptLedgerCount() -> Int {
        relayPacketLedger.deliveryReceipts.count
    }

    func compactRelayLedger() {
        guard authorizeUserAction() else { return }
        relayPacketLedger.compact(maxEntries: 500, maxDeliveryReceipts: 500)
        persistRelayPacketLedger()
        lastTransportDiagnosticMessage = "Relay-Ledger kompaktiert: \(relayPacketLedger.entries.count) Pakete, \(relayPacketLedger.deliveryReceipts.count) Receipts bleiben gespeichert."
        lastErrorMessage = nil
    }

    func clearRelayLedger() {
        guard authorizeUserAction() else { return }
        relayPacketLedger = .empty
        persistRelayPacketLedger()
        lastTransportDiagnosticMessage = "Lokales Relay-Ledger gelöscht. Neue Relay-Pakete werden wieder frisch bewertet."
        lastErrorMessage = nil
    }

    func resetRelayConnectivityBackoff() {
        guard authorizeUserAction() else { return }
        relayConnectivityStatus = .healthy
        refreshSecurityAIAssessment()
        lastTransportDiagnosticMessage = "Relay-Backoff zurückgesetzt. Nächster Sync versucht wieder sofort eine Verbindung."
        lastErrorMessage = nil
    }

    func refreshRuntimeSecurityAssessment() {
        runtimeSecuritySnapshot = RuntimeSecurityEvaluator.assess()
        if securityState.warnOnRuntimeRisk && runtimeSecuritySnapshot.riskLevel != .normal {
            lastTransportDiagnosticMessage = "Runtime-Security: \(runtimeSecuritySnapshot.localizedSummary). \(runtimeSecuritySnapshot.findings.count) Finding(s)."
        }
    }

    func refreshSecurityAIAssessment() {
        var snapshot = SecurityAISentinel.assess(
            securityState: securityState,
            runtimeSnapshot: runtimeSecuritySnapshot,
            relayConnectivityStatus: relayConnectivityStatus,
            conversations: conversations,
            trustedPeers: trustedPeers,
            relayStats: lastRelayStatsSnapshot,
            localIdentityID: localIdentity.id
        )
        // Sprint 10D: merge the v1 / v2 envelope
        // findings from the ratchet router into the
        // Sentinel snapshot. The router has been
        // collecting observations every time
        // sendMessage or processInboundPacket
        // produced an envelope; the
        // RatchetSentinelFindings builder collapses
        // them into a single "session still on v1"
        // warning or a "session on v2" info finding.
        // The list is drained so each refresh
        // re-evaluates from the latest state.
        let ratchetFindings = RatchetSentinelFindings.build(
            observations: ratchetObservations
        )
        ratchetObservations.removeAll(keepingCapacity: true)
        if !ratchetFindings.isEmpty {
            // Rebuild the summary string so it
            // reflects the merged findings. The
            // score and riskLevel stay at the
            // v1-assessment values because the
            // ratchet findings are informational
            // / warning, not critical security
            // regressions.
            let mergedFindings = snapshot.findings + ratchetFindings
            let hardCount = mergedFindings.filter {
                $0.severity == .critical || $0.severity == .high
            }.count
            snapshot = SecurityAISnapshot(
                score: snapshot.score,
                riskLevel: snapshot.riskLevel,
                summary: "\(snapshot.summary) + \(ratchetFindings.count) Ratchet-Finding(s) (\(hardCount) hart).",
                findings: mergedFindings,
                generatedAt: snapshot.generatedAt
            )
        }
        securityAISnapshot = snapshot
    }


    private func syncRelayInbox(showDisabledError: Bool) async {
        guard authorizeUserAction(), let sessionID = currentUserSessionID else { return }
        guard securityState.transportMode == .relayAllowed, securityState.relayConfiguration.isEnabled else {
            guard showDisabledError else {
                return
            }
            let message = PrivateChatError.relayDisabled.localizedDescription
            lastTransportDiagnosticMessage = message
            lastErrorMessage = message
            return
        }
        guard shouldBlockRelayForRuntimeRisk(showUserFacingError: showDisabledError, context: "Relay-Inbox-Abruf") == false else {
            return
        }
        guard shouldBlockRelayDueToConfiguration(showUserFacingError: showDisabledError, context: "Relay-Inbox-Abruf") == false else {
            return
        }
        guard shouldPauseRelayRequests(showUserFacingError: showDisabledError) == false else {
            return
        }
        guard isRelaySyncRunning == false else {
            return
        }

        isRelaySyncRunning = true
        defer { if userSessionGeneration == sessionID { isRelaySyncRunning = false } }
        lastTransportDiagnosticMessage = "Relay-Inbox-Abruf gestartet. \(transportDiagnosticSummary())"

        do {
            let packets = try await transportCoordinator.fetchRelayInbox(
                recipientID: localIdentity.id,
                relayConfiguration: securityState.relayConfiguration
            )
            try ensureUserSession(sessionID)
            var processedCount = 0
            var duplicateCount = 0
            var rejectedCount = 0
            var acknowledgedCount = 0
            var acknowledgementFailureCount = 0
            var deliveryReceiptSentCount = 0
            var deliveryReceiptFailureCount = 0

            for packet in packets {
                try ensureUserSession(sessionID)
                guard !Task.isCancelled else { return }
                if relayPacketLedger.wasAcknowledged(packetID: packet.id) {
                    duplicateCount += 1
                    continue
                }

                do {
                    let result = try processInboundPacket(packet)
                    if result.didProcessMessage {
                        processedCount += 1
                    }
                    if result.isDuplicate {
                        duplicateCount += 1
                    }

                    if let receiptContext = result.deliveryReceiptContext {
                        do {
                            let didSendReceipt = try await sendDeliveryReceiptIfNeeded(for: receiptContext, sessionID: sessionID)
                            try ensureUserSession(sessionID)
                            if didSendReceipt {
                                deliveryReceiptSentCount += 1
                            }
                        } catch {
                            guard isCurrentUserSession(sessionID) else { return }
                            deliveryReceiptFailureCount += 1
                            lastTransportDiagnosticMessage = "Delivery-Receipt fehlgeschlagen für Nachricht \(receiptContext.originalMessageID.uuidString): \(error.localizedDescription)"
                        }
                    }
                } catch {
                    guard isCurrentUserSession(sessionID) else { return }
                    rejectedCount += 1
                    // Unverified, malformed or not durably saved messages stay
                    // available until the relay's bounded expiry policy applies.
                    continue
                }

                try ensureUserSession(sessionID)
                _ = relayPacketLedger.registerSeen(packetID: packet.id)
                try relayPacketLedgerStore.save(relayPacketLedger)
                guard relayPacketLedger.shouldAttemptAcknowledgement(packetID: packet.id) else {
                    duplicateCount += 1
                    continue
                }

                do {
                    try await waitForRelayBulkRequestRateSlot(sessionID)
                    try ensureUserSession(sessionID)
                    _ = try await transportCoordinator.deleteRelayPacket(packetID: packet.id, relayConfiguration: securityState.relayConfiguration)
                    try ensureUserSession(sessionID)
                    acknowledgedCount += 1
                    relayPacketLedger.registerAcknowledged(packetID: packet.id)
                    persistRelayPacketLedger()
                } catch {
                    guard isCurrentUserSession(sessionID) else { return }
                    acknowledgementFailureCount += 1
                    lastTransportDiagnosticMessage = "Relay-ACK fehlgeschlagen für Paket \(packet.id.uuidString): \(error.localizedDescription)"
                }
            }

            try ensureUserSession(sessionID)
            registerRelaySuccess(message: nil)

            lastRelaySyncSummary = RelayInboxSyncSummary(
                processedCount: processedCount,
                duplicateCount: duplicateCount,
                rejectedCount: rejectedCount,
                deletedCount: acknowledgedCount,
                acknowledgementFailureCount: acknowledgementFailureCount,
                deliveryReceiptSentCount: deliveryReceiptSentCount,
                deliveryReceiptFailureCount: deliveryReceiptFailureCount,
                receivedAt: Date()
            )
            lastTransportDiagnosticMessage = "Relay-Inbox-Abruf abgeschlossen: \(processedCount) verarbeitet, \(duplicateCount) Duplikate, \(rejectedCount) verworfen, \(acknowledgedCount) bestätigt, \(deliveryReceiptSentCount) Receipts, \(acknowledgementFailureCount) ACK-Fehler."
            if acknowledgementFailureCount == 0 && deliveryReceiptFailureCount == 0 {
                lastErrorMessage = nil
            }
        } catch {
            guard isCurrentUserSession(sessionID) else { return }
            registerRelayFailure(error, showUserFacingError: showDisabledError, context: "Relay-Inbox-Abruf")
        }
    }

    private func retryPendingOutboundMessages(showEmptyResult: Bool, conversationID: UUID? = nil) async {
        guard authorizeUserAction(), let sessionID = currentUserSessionID else { return }
        guard isOutboxRetryRunning == false else {
            return
        }

        guard securityState.transportMode == .relayAllowed, securityState.relayConfiguration.isEnabled else {
            if showEmptyResult {
                let message = PrivateChatError.relayDisabled.localizedDescription
                lastTransportDiagnosticMessage = message
                lastErrorMessage = message
            }
            return
        }

        guard shouldBlockRelayForRuntimeRisk(showUserFacingError: showEmptyResult, context: "Outbox-Retry") == false else {
            return
        }
        guard shouldBlockRelayDueToConfiguration(showUserFacingError: showEmptyResult, context: "Outbox-Retry") == false else {
            return
        }

        guard shouldPauseRelayRequests(showUserFacingError: showEmptyResult) == false else {
            return
        }

        let pendingMessages = pendingOutboundMessageReferences().filter { conversationID == nil || $0.conversationID == conversationID }
        guard pendingMessages.isEmpty == false else {
            if showEmptyResult {
                lastOutboxRetrySummary = OutboxRetrySummary(attemptedCount: 0, sentCount: 0, failedCount: 0, completedAt: Date())
                lastTransportDiagnosticMessage = "Outbox ist leer. Keine ausstehenden Relay-Nachrichten."
                lastErrorMessage = nil
            }
            return
        }

        isOutboxRetryRunning = true
        defer { if userSessionGeneration == sessionID { isOutboxRetryRunning = false } }

        var attemptedCount = 0
        var sentCount = 0
        var failedCount = 0

        for reference in pendingMessages {
            guard isCurrentUserSession(sessionID) else { return }
            attemptedCount += 1
            do {
                try await deliverOutboundMessage(messageID: reference.messageID, conversationID: reference.conversationID, sessionID: sessionID)
                try ensureUserSession(sessionID)
                sentCount += 1
            } catch {
                guard isCurrentUserSession(sessionID) else { return }
                failedCount += 1
            }
        }

        guard isCurrentUserSession(sessionID) else { return }
        lastOutboxRetrySummary = OutboxRetrySummary(
            attemptedCount: attemptedCount,
            sentCount: sentCount,
            failedCount: failedCount,
            completedAt: Date()
        )
        lastTransportDiagnosticMessage = "Outbox-Retry abgeschlossen: \(sentCount)/\(attemptedCount) erneut gesendet, \(failedCount) fehlgeschlagen."
        if failedCount == 0 {
            lastErrorMessage = nil
        }
    }

    private func pendingOutboundMessageReferences() -> [(conversationID: UUID, messageID: UUID)] {
        conversations.flatMap { storedConversation in
            storedConversation.messages.compactMap { message in
                guard message.isIncoming == false,
                      message.recipientID != nil,
                      message.status == .queued || message.status == .failed else {
                    return nil
                }
                return (conversationID: storedConversation.id, messageID: message.id)
            }
        }
    }

    private func deliverOutboundMessage(messageID: UUID, conversationID: UUID, sessionID: UUID) async throws {
        try ensureUserSession(sessionID)
        guard let context = outboundMessageContext(messageID: messageID, conversationID: conversationID) else {
            return
        }

        guard let peerID = context.peerID else {
            markMessage(messageID, in: conversationID, status: .delivered)
            lastTransportDiagnosticMessage = "Lokale Nachricht gespeichert. Kein Netzwerktransport erforderlich."
            return
        }

        if securityState.transportMode == .relayAllowed {
            if shouldPauseRelayRequests(showUserFacingError: false) {
                markMessage(messageID, in: conversationID, status: .queued)
                return // Durable outbox acceptance; retry only after the backoff.
            }
            if shouldBlockRelayForRuntimeRisk(showUserFacingError: true, context: "Nachricht senden") {
                markMessage(messageID, in: conversationID, status: .failed)
                throw PrivateChatError.runtimeIntegrityBlocked(runtimeSecuritySnapshot.localizedSummary)
            }
            if shouldBlockRelayDueToConfiguration(showUserFacingError: true, context: "Nachricht senden") {
                markMessage(messageID, in: conversationID, status: .failed)
                throw PrivateChatError.relayMissingClientToken
            }
        }

        markMessage(messageID, in: conversationID, status: .sending)

        do {
            if let attachment = context.message.attachment {
                let data = try attachmentStore.loadAttachment(id: attachment.id)
                guard data.count == attachment.byteCount,
                      data.count <= Self.maximumAttachmentBytes else {
                    throw PrivateChatError.attachmentUnavailable
                }
                let digest = RequestSigner.sha256Hex(data)
                let totalChunks = max(
                    1,
                    Int(ceil(Double(data.count) / Double(Self.attachmentChunkBytes)))
                )
                for chunkIndex in 0..<totalChunks {
                    try ensureUserSession(sessionID)
                    guard outboundMessageContext(messageID: messageID, conversationID: conversationID) != nil else {
                        throw PrivateChatError.duplicateMessage
                    }
                    let lowerBound = chunkIndex * Self.attachmentChunkBytes
                    let upperBound = min(lowerBound + Self.attachmentChunkBytes, data.count)
                    let chunk = data.subdata(in: lowerBound..<upperBound)
                    let payload = TransportMessagePayload(
                        version: 3,
                        kind: .attachmentChunk,
                        messageID: context.message.id,
                        conversationID: context.conversationID,
                        senderID: localIdentity.id,
                        recipientID: peerID,
                        body: context.message.body,
                        createdAt: context.message.createdAt,
                        deliveredMessageID: nil,
                        attachment: attachment,
                        attachmentSHA256: digest,
                        chunkIndex: chunkIndex,
                        totalChunks: totalChunks,
                        chunkDataBase64: chunk.base64EncodedString()
                    )
                    if securityState.transportMode == .relayAllowed {
                        try await waitForRelayBulkRequestRateSlot(sessionID)
                    }
                    try await sendTransportPayload(payload, peerID: peerID, sessionID: sessionID)
                }
            } else {
                let payload = TransportMessagePayload(
                    version: 3,
                    kind: .message,
                    messageID: context.message.id,
                    conversationID: context.conversationID,
                    senderID: localIdentity.id,
                    recipientID: peerID,
                    body: context.message.body,
                    createdAt: context.message.createdAt,
                    deliveredMessageID: nil
                )
                try await sendTransportPayload(payload, peerID: peerID, sessionID: sessionID)
            }
            try ensureUserSession(sessionID)
            guard outboundMessageContext(messageID: messageID, conversationID: conversationID) != nil else {
                throw PrivateChatError.duplicateMessage
            }
            let finalStatus: MessageDeliveryStatus = securityState.transportMode == .relayAllowed ? .sentToRelay : .sent
            markMessage(messageID, in: conversationID, status: finalStatus)
            if securityState.transportMode == .relayAllowed {
                registerRelaySuccess(message: "Nachricht wurde Ende-zu-Ende verschlüsselt an den Relay übergeben.")
            } else {
                lastTransportDiagnosticMessage = "Nachricht wurde an den lokalen Transport übergeben."
            }
        } catch {
            guard isCurrentUserSession(sessionID) else { throw SessionAccessError.locked }
            markMessage(messageID, in: conversationID, status: .failed)
            registerRelayFailure(error, showUserFacingError: true, context: "Nachricht senden")
            throw error
        }
    }

    private func sendTransportPayload(_ payload: TransportMessagePayload, peerID: String, sessionID: UUID) async throws {
        try ensureUserSession(sessionID)
        let stablePacketID: UUID?
        if payload.kind == .attachmentChunk, let chunkIndex = payload.chunkIndex {
            stablePacketID = AttachmentPacketIdentifier.make(
                messageID: payload.messageID,
                chunkIndex: chunkIndex,
                recipientID: peerID
            )
        } else {
            stablePacketID = nil
        }
        let v1Packet = try makeTransportPacket(
            payload: payload,
            recipientID: peerID,
            packetID: stablePacketID
        )
        let packet: OutboundTransportPacket
        if Self.experimentalDoubleRatchetEnabled {
            let payloadData = try encoder.encode(payload)
            if let ratchetResult = try ratchetRouter.makeRatchetPacket(
                peerID: peerID,
                plaintext: payloadData,
                existingPacket: v1Packet
            ) {
                packet = ratchetResult.0
                ratchetObservations.append(ratchetResult.1)
            } else {
                packet = v1Packet
                ratchetObservations.append(ratchetRouter.v1FallbackObservation(peerID: peerID))
            }
        } else {
            packet = v1Packet
            ratchetObservations.append(ratchetRouter.v1FallbackObservation(peerID: peerID))
        }
        try ensureUserSession(sessionID)
        try await transportCoordinator.send(
            packet,
            mode: securityState.transportMode,
            relayConfiguration: securityState.relayConfiguration
        )
        try ensureUserSession(sessionID)
    }

    private func waitForRelayBulkRequestRateSlot(_ sessionID: UUID) async throws {
        try ensureUserSession(sessionID)
        let now = Date()
        let scheduledAt = max(now, nextRelayBulkRequestAt)
        nextRelayBulkRequestAt = scheduledAt.addingTimeInterval(
            Self.relayBulkRequestIntervalSeconds
        )
        let waitSeconds = scheduledAt.timeIntervalSince(now)
        guard waitSeconds > 0 else { return }
        try await Task.sleep(
            nanoseconds: UInt64(waitSeconds * 1_000_000_000)
        )
        try ensureUserSession(sessionID)
    }

    private func outboundMessageContext(messageID: UUID, conversationID: UUID) -> OutboundMessageContext? {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let message = conversations[conversationIndex].messages.first(where: { $0.id == messageID }) else {
            return nil
        }
        return OutboundMessageContext(
            conversationID: conversationID,
            peerID: conversations[conversationIndex].conversation.peerID,
            message: message
        )
    }


    private func shouldBlockRelayDueToConfiguration(showUserFacingError: Bool, context: String) -> Bool {
        guard securityState.transportMode == .relayAllowed, securityState.relayConfiguration.isEnabled else {
            return false
        }

        if SecureChatProductionProfile.isObsoleteLocalRelay(securityState.relayConfiguration.baseURLString) {
            let message = "\(context): alte lokale Relay-URL blockiert. Bitte Production Relay aktivieren: \(SecureChatProductionProfile.relayBaseURLString)."
            lastTransportDiagnosticMessage = message
            if showUserFacingError {
                lastErrorMessage = PrivateChatError.relayObsoleteLocalConfiguration(securityState.relayConfiguration.baseURLString).localizedDescription
            }
            return true
        }

        if let readinessIssue = securityState.relayConfiguration.readinessIssue {
            let message = "\(context): Relay-Konfiguration nicht bereit. \(readinessIssue)"
            lastTransportDiagnosticMessage = message
            if showUserFacingError {
                lastErrorMessage = message
            }
            return true
        }

        return false
    }

    private func shouldBlockRelayForRuntimeRisk(showUserFacingError: Bool, context: String) -> Bool {
        refreshRuntimeSecurityAssessment()
        guard securityState.restrictRelayOnRuntimeRisk, runtimeSecuritySnapshot.shouldBlockSensitiveTransport else {
            return false
        }

        let message = "\(context): Relay blockiert wegen Runtime-Risiko: \(runtimeSecuritySnapshot.localizedSummary)."
        lastTransportDiagnosticMessage = message
        if showUserFacingError {
            lastErrorMessage = message
        }
        return true
    }

    private func shouldPauseRelayRequests(showUserFacingError: Bool) -> Bool {
        guard relayConnectivityStatus.isPaused else {
            return false
        }
        let seconds = relayConnectivityStatus.remainingPauseSeconds
        let message = "Relay temporär pausiert (noch ca. \(seconds)s). Grund: \(relayConnectivityStatus.lastErrorMessage ?? "letzter Verbindungsfehler")."
        lastTransportDiagnosticMessage = message
        if showUserFacingError {
            lastErrorMessage = message
        }
        return true
    }

    private func registerRelaySuccess(message: String?) {
        relayConnectivityStatus = RelayConnectivityStatus(
            state: .healthy,
            consecutiveFailureCount: 0,
            pausedUntil: nil,
            lastFailureAt: relayConnectivityStatus.lastFailureAt,
            lastSuccessAt: Date(),
            lastErrorMessage: nil
        )
        if let message {
            lastTransportDiagnosticMessage = message
        }
    }

    private func registerRelayFailure(_ error: Error, showUserFacingError: Bool, context: String) {
        let message = error.localizedDescription
        if isTransientRelayConnectivityError(error) {
            let failures = relayConnectivityStatus.consecutiveFailureCount + 1
            let pauseSeconds = min(300, max(10, Int(pow(2.0, Double(min(failures, 6)))) * 5))
            let pauseUntil = Date().addingTimeInterval(TimeInterval(pauseSeconds))
            relayConnectivityStatus = RelayConnectivityStatus(
                state: .paused,
                consecutiveFailureCount: failures,
                pausedUntil: pauseUntil,
                lastFailureAt: Date(),
                lastSuccessAt: relayConnectivityStatus.lastSuccessAt,
                lastErrorMessage: message
            )
            lastTransportDiagnosticMessage = "\(context): Relay nicht erreichbar. Auto-Sync pausiert ca. \(pauseSeconds)s. \(message)"
            if showUserFacingError {
                lastErrorMessage = lastTransportDiagnosticMessage
            }
            return
        }

        relayConnectivityStatus = RelayConnectivityStatus(
            state: .degraded,
            consecutiveFailureCount: relayConnectivityStatus.consecutiveFailureCount + 1,
            pausedUntil: nil,
            lastFailureAt: Date(),
            lastSuccessAt: relayConnectivityStatus.lastSuccessAt,
            lastErrorMessage: message
        )
        lastTransportDiagnosticMessage = "\(context): \(message)"
        if showUserFacingError {
            lastErrorMessage = message
        }
    }

    private func isTransientRelayConnectivityError(_ error: Error) -> Bool {
        guard let privateChatError = error as? PrivateChatError else {
            return false
        }
        switch privateChatError {
        case .relayTimedOut, .relayNoNetwork, .relayCannotConnectToHost, .relayConnectionLost, .relayRequestFailed:
            return true
        case .relayHTTPError(let status, _):
            return status == 429 || (500...599).contains(status)
        default:
            return false
        }
    }

    private func transportDiagnosticSummary() -> String {        transportDiagnosticSummary(for: securityState)
    }

    private func transportDiagnosticSummary(for state: AppSecurityState) -> String {
        let relayURL = state.relayConfiguration.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        switch state.transportMode {
        case .localOnly:
            return "Transportmodus: Nur lokal. Direkttransport ist noch nicht aktiv."
        case .relayAllowed:
            if relayURL.isEmpty {
                return "Transportmodus: Relay erlaubt, aber keine Relay-URL gespeichert. Production: \(SecureChatProductionProfile.relayBaseURLString)."
            }
            if let readinessIssue = state.relayConfiguration.readinessIssue {
                return "Transportmodus: Relay erlaubt, aber nicht bereit. \(readinessIssue)"
            }
            return "Transportmodus: Relay erlaubt. Relay-URL: \(relayURL). Token: gesetzt. Auto-Polling: \(state.relayConfiguration.autoPollingIntervalSeconds)s. Retention: \(state.localMessageRetentionDays)d."
        }
    }

    private func makeTransportPacket(
        payload: TransportMessagePayload,
        recipientID: String,
        packetID requestedPacketID: UUID? = nil
    ) throws -> OutboundTransportPacket {
        _ = try requireUserSession()
        let peer = try verifiedPeer(id: recipientID)
        guard let peerPublicKeyData = Data(base64Encoded: peer.keyAgreementPublicKeyBase64) else {
            throw PrivateChatError.invalidKeyMaterial
        }

        let peerPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKeyData)
        let key = try makePairwiseKey(peerID: recipientID, peerPublicKey: peerPublicKey)
        let payloadData = try encoder.encode(payload)
        guard payloadData.count <= RelayWireCoding.maximumSealedPayloadBytes - 28 else {
            throw PrivateChatError.attachmentTooLarge(maximumBytes: Self.maximumAttachmentBytes)
        }
        let packetID = requestedPacketID ?? UUID()
        let createdAt = Date()
        let expiresAt = createdAt.addingTimeInterval(86_400)
        let unsignedPacket = OutboundTransportPacket(
            id: packetID,
            senderID: localIdentity.id,
            recipientID: recipientID,
            sealedPayloadBase64: try crypto.encrypt(
                payloadData,
                key: key,
                aad: OutboundTransportPacket(
                    id: packetID,
                    senderID: localIdentity.id,
                    recipientID: recipientID,
                    sealedPayloadBase64: "pending",
                    signatureBase64: "pending",
                    createdAt: createdAt,
                    expiresAt: expiresAt
                ).payloadAAD
            ).base64EncodedString(),
            signatureBase64: "pending",
            createdAt: createdAt,
            expiresAt: expiresAt
        )
        let signature = try crypto.sign(unsignedPacket.authenticatedData, privateKey: localIdentity.signingPrivateKey)
        return OutboundTransportPacket(
            protocolVersion: unsignedPacket.protocolVersion,
            id: unsignedPacket.id,
            senderID: unsignedPacket.senderID,
            recipientID: unsignedPacket.recipientID,
            sealedPayloadBase64: unsignedPacket.sealedPayloadBase64,
            signatureBase64: signature.base64EncodedString(),
            createdAt: unsignedPacket.createdAt,
            expiresAt: unsignedPacket.expiresAt
        )
    }

    private func processInboundPacket(_ packet: OutboundTransportPacket) throws -> InboundPacketProcessResult {
        _ = try requireUserSession()
        // Sprint 9D: accept both v1 (protocolVersion 2)
        // and v2 (protocolVersion 3) envelopes. v2
        // packets carry a RatchetChannelEnvelope in
        // their sealedPayloadBase64; the v1 path
        // continues to verify the Ed25519 envelope
        // signature against the trusted-peer key.
        guard (packet.protocolVersion == 2 ||
               (Self.experimentalDoubleRatchetEnabled && packet.protocolVersion == 3)),
              packet.recipientID == localIdentity.id,
              packet.senderID != localIdentity.id,
              packet.createdAt.timeIntervalSinceNow <= 300,
              packet.expiresAt > Date(),
              packet.expiresAt > packet.createdAt,
              packet.expiresAt.timeIntervalSince(packet.createdAt) <= 86_400 else {
            throw PrivateChatError.invalidInboundPacket
        }

        let wasSeenBefore = relayPacketLedger.entries.contains { $0.id == packet.id }

        if packet.protocolVersion == 3 {
            // v2 (Double Ratchet) path. Skip the
            // Ed25519 envelope-signature verification
            // and the trusted-peer pairwise key -- the
            // Ratchet AEAD authenticates the sender.
            return try processInboundV2Packet(packet, wasSeenBefore: wasSeenBefore)
        }

        let peer = try verifiedPeer(id: packet.senderID)
        try verifyEnvelopeSignature(packet, peer: peer)

        guard let peerPublicKeyData = Data(base64Encoded: peer.keyAgreementPublicKeyBase64),
              let sealedPayloadData = Data(base64Encoded: packet.sealedPayloadBase64) else {
            throw PrivateChatError.invalidInboundPacket
        }

        let peerPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKeyData)
        let key = try makePairwiseKey(peerID: packet.senderID, peerPublicKey: peerPublicKey)
        let payloadData = try crypto.decrypt(sealedPayloadData, key: key, aad: packet.payloadAAD)
        let payload = try decoder.decode(TransportMessagePayload.self, from: payloadData)

        guard payload.version == 3,
              payload.senderID == packet.senderID,
              payload.recipientID == localIdentity.id else {
            throw PrivateChatError.invalidInboundPacket
        }

        switch payload.kind {
        case .message:
            guard let body = payload.body,
                  body.isEmpty == false,
                  let conversationID = payload.conversationID else {
                throw PrivateChatError.invalidInboundPacket
            }

            let receiptContext = DeliveryReceiptContext(
                originalMessageID: payload.messageID,
                originalConversationID: conversationID,
                originalSenderID: payload.senderID
            )

            guard hasMessage(id: payload.messageID) == false else {
                let duplicateReceiptContext = relayPacketLedger.wasDeliveryReceiptSent(for: payload.messageID) ? nil : receiptContext
                return InboundPacketProcessResult(didProcessMessage: false, isDuplicate: true, deliveryReceiptContext: duplicateReceiptContext)
            }

            try appendInboundMessage(payload: payload, peer: peer)
            let newReceiptContext = relayPacketLedger.wasDeliveryReceiptSent(for: payload.messageID) ? nil : receiptContext
            return InboundPacketProcessResult(didProcessMessage: true, isDuplicate: wasSeenBefore, deliveryReceiptContext: newReceiptContext)

        case .attachmentChunk:
            guard let conversationID = payload.conversationID,
                  let attachment = payload.attachment,
                  let digest = payload.attachmentSHA256,
                  let chunkIndex = payload.chunkIndex,
                  let totalChunks = payload.totalChunks,
                  let encodedChunk = payload.chunkDataBase64,
                  let chunk = Data(base64Encoded: encodedChunk),
                  attachment.byteCount > 0,
                  attachment.byteCount <= Self.maximumAttachmentBytes,
                  attachment.fileName.isEmpty == false,
                  attachment.fileName.utf8.count <= 255,
                  attachment.mimeType.isEmpty == false,
                  attachment.mimeType.utf8.count <= 128 else {
                throw PrivateChatError.invalidInboundPacket
            }

            let receiptContext = DeliveryReceiptContext(
                originalMessageID: payload.messageID,
                originalConversationID: conversationID,
                originalSenderID: payload.senderID
            )
            if hasMessage(id: payload.messageID) {
                let duplicateReceipt = relayPacketLedger.wasDeliveryReceiptSent(for: payload.messageID)
                    ? nil
                    : receiptContext
                return InboundPacketProcessResult(
                    didProcessMessage: false,
                    isDuplicate: true,
                    deliveryReceiptContext: duplicateReceipt
                )
            }

            let completed = try attachmentStore.storeIncomingChunk(
                attachmentID: attachment.id,
                index: chunkIndex,
                totalChunks: totalChunks,
                data: chunk,
                expectedByteCount: attachment.byteCount,
                expectedSHA256: digest,
                transferContext: packet.senderID + "|" + conversationID.uuidString + "|" + payload.messageID.uuidString
            )
            guard completed else {
                return InboundPacketProcessResult(
                    didProcessMessage: true,
                    isDuplicate: wasSeenBefore,
                    deliveryReceiptContext: nil
                )
            }

            try appendInboundMessage(payload: payload, peer: peer)
            let completedReceipt = relayPacketLedger.wasDeliveryReceiptSent(for: payload.messageID)
                ? nil
                : receiptContext
            return InboundPacketProcessResult(
                didProcessMessage: true,
                isDuplicate: wasSeenBefore,
                deliveryReceiptContext: completedReceipt
            )

        case .deliveryReceipt:
            guard let deliveredMessageID = payload.deliveredMessageID else {
                throw PrivateChatError.invalidInboundPacket
            }
            let didMarkDelivered = try markDeliveredMessage(deliveredMessageID, from: payload.senderID)
            return InboundPacketProcessResult(didProcessMessage: didMarkDelivered, isDuplicate: wasSeenBefore || didMarkDelivered == false, deliveryReceiptContext: nil)
        }
    }

    private func sendDeliveryReceiptIfNeeded(for context: DeliveryReceiptContext, sessionID: UUID) async throws -> Bool {
        try ensureUserSession(sessionID)
        guard securityState.transportMode == .relayAllowed, securityState.relayConfiguration.isEnabled else {
            return false
        }
        guard relayPacketLedger.wasDeliveryReceiptSent(for: context.originalMessageID) == false else {
            return false
        }

        let payload = TransportMessagePayload(
            version: 3,
            kind: .deliveryReceipt,
            messageID: UUID(),
            conversationID: context.originalConversationID,
            senderID: localIdentity.id,
            recipientID: context.originalSenderID,
            body: nil,
            createdAt: Date(),
            deliveredMessageID: context.originalMessageID
        )
        let packet = try makeTransportPacket(payload: payload, recipientID: context.originalSenderID)
        try await waitForRelayBulkRequestRateSlot(sessionID)
        try ensureUserSession(sessionID)
        try await transportCoordinator.send(packet, mode: .relayAllowed, relayConfiguration: securityState.relayConfiguration)
        try ensureUserSession(sessionID)
        relayPacketLedger.registerDeliveryReceiptSent(for: context.originalMessageID)
        persistRelayPacketLedger()
        return true
    }

    private func verifyEnvelopeSignature(_ packet: OutboundTransportPacket, peer: TrustedPeer) throws {
        guard let signatureData = Data(base64Encoded: packet.signatureBase64),
              let signingPublicKeyData = Data(base64Encoded: peer.signingPublicKeyBase64) else {
            throw PrivateChatError.invalidSignature
        }

        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: signingPublicKeyData)
        guard crypto.verify(signature: signatureData, data: packet.authenticatedData, publicKey: publicKey) else {
            throw PrivateChatError.invalidSignature
        }
    }

    // Sprint 9D: handle a v2 (protocolVersion 3)
    // inbound packet. The RatchetChannelEnvelope is
    // in the sealedPayloadBase64; the ratchet AEAD
    // authenticates the sender, so we do not run
    // the v1 Ed25519 envelope-signature verify or
    // the trusted-peer pairwise key. The decoded
    // plaintext is the v1 TransportMessagePayload
    // JSON, so the v1 post-decrypt pipeline
    // (version check, senderID/recipientID check,
    // appendInboundMessage) is reused as-is.
    private func processInboundV2Packet(
        _ packet: OutboundTransportPacket,
        wasSeenBefore: Bool
    ) throws -> InboundPacketProcessResult {
        let (plaintext, obs) = try ratchetRouter.tryDecodeV2(packet: packet)
            ?? (Data(), ratchetRouter.v1FallbackObservation(peerID: packet.senderID))
        ratchetObservations.append(obs)
        let payload = try decoder.decode(TransportMessagePayload.self, from: plaintext)
        guard payload.version == 3,
              payload.senderID == packet.senderID,
              payload.recipientID == localIdentity.id else {
            throw PrivateChatError.invalidInboundPacket
        }
        // The trusted-peer record is the v1
        // invariant. For the v2 path we look it
        // up by senderID; if it is missing, we
        // synthesise a minimal TrustedPeer so the
        // downstream appendInboundMessage and
        // delivery-receipt flow continue to work.
        let peer: TrustedPeer
        if let existing = trustedPeers.first(where: { $0.id == packet.senderID }) {
            peer = existing
        } else {
            // The Ratchet AEAD has already
            // authenticated the sender; we use a
            // deterministic placeholder for the
            // fields the post-decrypt pipeline
            // does not need (displayName,
            // signingPublicKeyBase64, safetyNumber).
            peer = TrustedPeer(
                id: packet.senderID,
                displayName: packet.senderID,
                keyAgreementPublicKeyBase64: "",
                signingPublicKeyBase64: "",
                safetyNumber: ""
            )
        }
        try appendInboundMessage(payload: payload, peer: peer)
        return InboundPacketProcessResult(
            didProcessMessage: true,
            isDuplicate: wasSeenBefore,
            deliveryReceiptContext: nil
        )
    }

    private func appendInboundMessage(payload: TransportMessagePayload, peer: TrustedPeer) throws {
        let previous = conversations
        let conversationIndex: Int
        if let existingIndex = conversations.firstIndex(where: { $0.conversation.peerID == peer.id }) {
            conversationIndex = existingIndex
        } else {
            let conversation = Conversation(title: peer.displayName, peerID: peer.id)
            conversations.insert(StoredConversation(conversation: conversation, messages: []), at: 0)
            conversationIndex = 0
        }

        let conversationID = conversations[conversationIndex].conversation.id
        let message = ChatMessage(
            id: payload.messageID,
            conversationID: conversationID,
            senderID: payload.senderID,
            recipientID: payload.recipientID,
            body: payload.body ?? "",
            createdAt: payload.createdAt,
            status: .delivered,
            isIncoming: true,
            readAt: nil,
            attachment: payload.attachment
        )
        conversations[conversationIndex].messages.append(message)
        conversations[conversationIndex].conversation.updatedAt = max(Date(), payload.createdAt)
        sortConversations()
        guard persistConversations() else {
            conversations = previous
            throw PrivateChatError.persistenceFailed("Eingehende Nachricht konnte nicht sicher gespeichert werden.")
        }
    }

    private func migratePeerSafetyNumbersIfNeeded() throws {
        var didChange = false
        let localSigningPublicKeyData = localIdentity.signingPublicKeyData

        for index in trustedPeers.indices {
            guard let remoteSigningPublicKeyData = Data(
                base64Encoded: trustedPeers[index].signingPublicKeyBase64
            ), remoteSigningPublicKeyData.count == 32,
                  let agreement = Data(base64Encoded: trustedPeers[index].keyAgreementPublicKeyBase64), agreement.count == 32 else {
                trustedPeers[index].trustState = .blocked
                trustedPeers[index].lastVerifiedAt = nil
                didChange = true
                continue
            }

            let current = SafetyNumberV3.make(
                localSigningPublicKeyData: localSigningPublicKeyData,
                localKeyAgreementPublicKeyData: localIdentity.keyAgreementPublicKeyData,
                remoteSigningPublicKeyData: remoteSigningPublicKeyData,
                remoteKeyAgreementPublicKeyData: agreement
            )
            if trustedPeers[index].safetyNumber != current {
                trustedPeers[index].safetyNumber = current
                // A fingerprint algorithm change invalidates the old
                // out-of-band verification. The user must compare the
                // new SC3 value before messages can be sent again.
                if trustedPeers[index].trustState == .verified {
                    trustedPeers[index].trustState = .unverified
                    trustedPeers[index].lastVerifiedAt = nil
                }
                didChange = true
            }
        }

        if didChange {
            try peerTrustStore.savePeers(trustedPeers)
        }
    }

    private func revokeExperimentalRatchetState(peerID: String) {
        do {
            try ratchetStore.delete(peerID: peerID)
        } catch {
            lastErrorMessage = "Ratchet-Session für den Kontakt konnte nicht sicher gelöscht werden: \(error.localizedDescription)"
        }
    }

    private func verifiedPeer(id: String) throws -> TrustedPeer {
        guard let peer = trustedPeers.first(where: { $0.id == id }) else {
            throw PrivateChatError.peerNotTrusted
        }
        guard peer.trustState != .blocked else {
            throw PrivateChatError.peerBlocked
        }
        guard peer.trustState == .verified else {
            throw PrivateChatError.peerNotTrusted
        }
        return peer
    }

    private func makePairwiseKey(peerID: String, peerPublicKey: Curve25519.KeyAgreement.PublicKey) throws -> SymmetricKey {
        let orderedIDs = [localIdentity.id, peerID].sorted().joined(separator: ":")
        let context = Data("PrivateChat/pairwise-message/v3/\(orderedIDs)".utf8)
        return try crypto.derivePairwiseKey(
            privateKey: localIdentity.keyAgreementPrivateKey,
            peerPublicKey: peerPublicKey,
            context: context
        )
    }

    private func hasMessage(id messageID: UUID) -> Bool {
        conversations.contains { storedConversation in
            storedConversation.messages.contains { $0.id == messageID }
        }
    }

    private func markMessage(_ messageID: UUID, in conversationID: UUID, status: MessageDeliveryStatus) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }
        conversations[conversationIndex].messages[messageIndex].status = status
        conversations[conversationIndex].conversation.updatedAt = Date()
        sortConversations()
        persistConversations()
    }

    private func markDeliveredMessage(_ messageID: UUID, from peerID: String) throws -> Bool {
        for conversationIndex in conversations.indices {
            guard let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { message in
                message.id == messageID &&
                message.isIncoming == false &&
                message.recipientID == peerID
            }) else {
                continue
            }

            let previous = conversations
            conversations[conversationIndex].messages[messageIndex].status = .delivered
            conversations[conversationIndex].conversation.updatedAt = Date()
            sortConversations()
            guard commitConversationMutation(previous: previous) else {
                throw PrivateChatError.persistenceFailed("Zustellbestätigung konnte nicht sicher gespeichert werden.")
            }
            return true
        }
        return false
    }

    @discardableResult
    private func resetInterruptedOutgoingMessages() -> Bool {
        let previous = conversations
        var didChange = false
        for conversationIndex in conversations.indices {
            for messageIndex in conversations[conversationIndex].messages.indices {
                let message = conversations[conversationIndex].messages[messageIndex]
                if message.isIncoming == false, message.status == .sending {
                    conversations[conversationIndex].messages[messageIndex].status = .queued
                    didChange = true
                }
            }
        }
        if didChange {
            return commitConversationMutation(previous: previous)
        }
        return true
    }

    private func sortConversations() {
        conversations.sort { left, right in
            if left.conversation.isArchived != right.conversation.isArchived {
                return right.conversation.isArchived
            }
            if left.conversation.isPinned != right.conversation.isPinned {
                return left.conversation.isPinned
            }
            return left.conversation.updatedAt > right.conversation.updatedAt
        }
    }

    private func commitConversationMutation(previous: [StoredConversation]) -> Bool {
        guard persistConversations() else {
            conversations = previous
            return false
        }
        return true
    }

    private func reclaimUnreferencedAttachments(_ removed: [ChatAttachment]) {
        let retained = Set(conversations.flatMap { $0.messages.compactMap { $0.attachment?.id } })
        for id in Set(removed.map(\.id)) where !retained.contains(id) {
            do { try attachmentStore.deleteAttachment(id: id) }
            catch { lastErrorMessage = "Die lokale Anhangsdatei konnte noch nicht gelöscht werden. " + error.localizedDescription }
        }
    }

    @discardableResult
    private func persistConversations() -> Bool {
        do {
            try messageStore.save(conversations)
            lastErrorMessage = nil
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    private func persistPeers() -> Bool {
        do {
            try peerTrustStore.savePeers(trustedPeers)
            lastErrorMessage = nil
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    private func persistRelayPacketLedger() {
        do {
            try relayPacketLedgerStore.save(relayPacketLedger)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
