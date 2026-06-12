import Combine
import CryptoKit
import Foundation

enum TransportPayloadKind: String, Codable, Equatable {
    case message
    case deliveryReceipt
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

    private let messageStore: MessageStoring
    private let draftStore: DraftStoring
    private let peerTrustStore: PeerTrustStoring
    private let settingsStore: SecuritySettingsStoring
    private let relayPacketLedgerStore: RelayPacketLedgerStoring
    private let identityManager: IdentityManaging
    private let crypto: CryptoServicing
    private let transportCoordinator: TransportCoordinating
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var relayPacketLedger: RelayPacketLedger
    private var relayAutoSyncTask: Task<Void, Never>?

    init(
        localIdentity: LocalIdentity,
        messageStore: MessageStoring,
        draftStore: DraftStoring,
        peerTrustStore: PeerTrustStoring,
        settingsStore: SecuritySettingsStoring,
        relayPacketLedgerStore: RelayPacketLedgerStoring,
        identityManager: IdentityManaging,
        crypto: CryptoServicing,
        transportCoordinator: TransportCoordinating
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
        self.encoder = DateCoding.makeEncoder()
        self.decoder = DateCoding.makeDecoder()
        self.relayPacketLedger = .empty
        self.conversations = []
        self.trustedPeers = []
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

    func load() {
        do {
            conversations = try messageStore.load().sorted { $0.conversation.updatedAt > $1.conversation.updatedAt }
            resetInterruptedOutgoingMessages()
            trustedPeers = try peerTrustStore.loadPeers()
            securityState = try settingsStore.load()
            relayPacketLedger = try relayPacketLedgerStore.load()
            refreshRuntimeSecurityAssessment()
            refreshSecurityAIAssessment()
            lastRelayHealthMessage = nil
            lastTransportDiagnosticMessage = transportDiagnosticSummary()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func clearError() {
        lastErrorMessage = nil
    }

    func reportError(_ error: Error) {
        lastErrorMessage = error.localizedDescription
    }

    func loadDraft(conversationID: UUID, legacyUserDefaultsValue: String?) -> String {
        do {
            if let migratedDraft = try draftStore.migrateLegacyDraftIfNeeded(conversationID: conversationID, legacyValue: legacyUserDefaultsValue) {
                return migratedDraft
            }
            return try draftStore.loadDraft(conversationID: conversationID) ?? ""
        } catch {
            lastErrorMessage = "Entwurf konnte nicht entschlüsselt geladen werden: \(error.localizedDescription)"
            return legacyUserDefaultsValue ?? ""
        }
    }

    func saveDraft(_ draft: String, conversationID: UUID) {
        do {
            try draftStore.saveDraft(draft, conversationID: conversationID)
        } catch {
            lastErrorMessage = "Entwurf konnte nicht verschlüsselt gespeichert werden: \(error.localizedDescription)"
        }
    }

    func deleteDraft(conversationID: UUID) {
        do {
            try draftStore.deleteDraft(conversationID: conversationID)
        } catch {
            lastErrorMessage = "Entwurf konnte nicht gelöscht werden: \(error.localizedDescription)"
        }
    }

    func startRelayAutoSyncLoop() {
        guard relayAutoSyncTask == nil else {
            return
        }

        relayAutoSyncTask = Task { [weak self] in
            await self?.runRelayAutoSyncLoop()
        }
    }

    func stopRelayAutoSyncLoop() {
        relayAutoSyncTask?.cancel()
        relayAutoSyncTask = nil
        isRelayAutoPollingActive = false
    }

    private func runRelayAutoSyncLoop() async {
        guard isRelayAutoPollingActive == false else {
            return
        }

        isRelayAutoPollingActive = true
        defer {
            isRelayAutoPollingActive = false
            relayAutoSyncTask = nil
        }

        while Task.isCancelled == false {
            if securityState.transportMode == .relayAllowed, securityState.relayConfiguration.isEnabled {
                if shouldBlockRelayDueToConfiguration(showUserFacingError: false, context: "Auto-Sync") == false, shouldPauseRelayRequests(showUserFacingError: false) == false {
                    await syncRelayInbox(showDisabledError: false)
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

    func createConversation(title: String, peerID: String?) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty == false else {
            return
        }

        let conversation = Conversation(title: trimmedTitle, peerID: peerID)
        conversations.insert(StoredConversation(conversation: conversation, messages: []), at: 0)
        persistConversations()
    }

    @discardableResult
    func createSoloTestConversation() -> UUID {
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
        conversations.insert(StoredConversation(conversation: conversation, messages: [welcomeMessage, hintMessage]), at: 0)
        persistConversations()
        lastTransportDiagnosticMessage = "Solo-Test-Chat lokal angelegt. Kein Relay-Transport erforderlich."
        return conversation.id
    }

    func deleteConversation(id: UUID) {
        conversations.removeAll { $0.id == id }
        persistConversations()
    }

    func toggleConversationPinned(id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else {
            return
        }
        conversations[index].conversation.isPinned.toggle()
        conversations[index].conversation.updatedAt = Date()
        sortConversations()
        persistConversations()
    }

    func toggleConversationArchived(id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else {
            return
        }
        conversations[index].conversation.isArchived.toggle()
        conversations[index].conversation.updatedAt = Date()
        sortConversations()
        persistConversations()
    }

    func toggleConversationMuted(id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else {
            return
        }
        conversations[index].conversation.isMuted.toggle()
        conversations[index].conversation.updatedAt = Date()
        sortConversations()
        persistConversations()
    }

    func clearConversationMessages(id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else {
            return
        }
        conversations[index].messages.removeAll()
        conversations[index].conversation.updatedAt = Date()
        sortConversations()
        persistConversations()
    }

    func markConversationRead(id: UUID) {
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
        do {
            try await deliverOutboundMessage(messageID: messageID, conversationID: conversationID)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func deleteMessage(messageID: UUID, conversationID: UUID) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return
        }
        conversations[conversationIndex].messages.removeAll { $0.id == messageID }
        conversations[conversationIndex].conversation.updatedAt = conversations[conversationIndex].messages.last?.createdAt ?? Date()
        sortConversations()
        persistConversations()
    }

    func toggleMessageStarred(messageID: UUID, conversationID: UUID) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }
        conversations[conversationIndex].messages[messageIndex].isStarred.toggle()
        persistConversations()
    }

    func sendMessage(conversationID: UUID, body: String) async {
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedBody.isEmpty == false else {
            return
        }

        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return
        }

        let conversation = conversations[index].conversation
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
        persistConversations()
        lastTransportDiagnosticMessage = transportDiagnosticSummary()

        do {
            try await deliverOutboundMessage(messageID: message.id, conversationID: conversationID)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func syncRelayInbox() async {
        await syncRelayInbox(showDisabledError: true)
    }

    func retryPendingOutboundMessages() async {
        await retryPendingOutboundMessages(showEmptyResult: true)
    }

    func fetchRelayStats() async {
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
        defer { isRelayStatsRunning = false }

        do {
            let response = try await transportCoordinator.fetchRelayStats(relayConfiguration: securityState.relayConfiguration)
            lastRelayStatsSnapshot = RelayStatsSnapshot(
                storedPackets: response.storedPackets,
                activeRecipients: response.activeRecipients,
                acknowledgedPacketTombstones: response.acknowledgedPacketTombstones,
                fetchedAt: Date()
            )
            registerRelaySuccess(message: "Relay-Stats aktualisiert: \(response.storedPackets) Pakete, \(response.activeRecipients) Empfänger, \(response.acknowledgedPacketTombstones) ACK-Tombstones.")
            lastErrorMessage = nil
        } catch {
            registerRelayFailure(error, showUserFacingError: true, context: "Relay-Stats")
        }
    }

    func purgeRelayInbox() async {
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
        defer { isRelayPurgeRunning = false }

        do {
            let response = try await transportCoordinator.purgeRelayInbox(recipientID: localIdentity.id, relayConfiguration: securityState.relayConfiguration)
            lastRelayPurgeSummary = RelayPurgeSummary(deletedCount: response.deletedCount, recipientID: response.recipientID, completedAt: Date())
            registerRelaySuccess(message: "Relay-Inbox bereinigt: \(response.deletedCount) Paket(e) für diese Identität entfernt.")
            await fetchRelayStats()
            lastErrorMessage = nil
        } catch {
            registerRelayFailure(error, showUserFacingError: true, context: "Relay-Inbox bereinigen")
        }
    }

    func purgeExpiredLocalMessages() {
        guard isLocalRetentionPurgeRunning == false else {
            return
        }

        isLocalRetentionPurgeRunning = true
        defer { isLocalRetentionPurgeRunning = false }

        let cutoff = Date().addingTimeInterval(-TimeInterval(securityState.localMessageRetentionDays) * 86_400)
        var deletedMessages = 0
        let originalConversationCount = conversations.count

        for index in conversations.indices {
            let originalMessageCount = conversations[index].messages.count
            conversations[index].messages.removeAll { $0.createdAt < cutoff }
            let newMessageCount = conversations[index].messages.count
            deletedMessages += originalMessageCount - newMessageCount
            conversations[index].conversation.updatedAt = conversations[index].messages.last?.createdAt ?? conversations[index].conversation.updatedAt
        }

        conversations.removeAll { storedConversation in
            storedConversation.messages.isEmpty && storedConversation.conversation.createdAt < cutoff
        }

        let deletedConversations = originalConversationCount - conversations.count
        sortConversations()
        persistConversations()
        lastLocalRetentionSummary = LocalRetentionSummary(deletedMessages: deletedMessages, deletedConversations: deletedConversations, completedAt: Date())
        lastTransportDiagnosticMessage = "Lokale Retention bereinigt: \(deletedMessages) Nachricht(en), \(deletedConversations) leere Chat(s) gelöscht."
    }

    func checkRelayHealth() async {
        guard isRelayHealthCheckRunning == false else {
            return
        }

        isRelayHealthCheckRunning = true
        defer { isRelayHealthCheckRunning = false }
        lastTransportDiagnosticMessage = "Relay-Prüfung gestartet. \(transportDiagnosticSummary())"
        guard shouldBlockRelayForRuntimeRisk(showUserFacingError: true, context: "Relay-Prüfung") == false else {
            return
        }
        guard shouldBlockRelayDueToConfiguration(showUserFacingError: true, context: "Relay-Prüfung") == false else {
            return
        }

        do {
            let status = try await transportCoordinator.checkRelayHealth(relayConfiguration: securityState.relayConfiguration)
            registerRelaySuccess(message: "Relay-Prüfung erfolgreich. \(transportDiagnosticSummary())")
            lastRelayHealthMessage = status.isHealthy
                ? "Relay erreichbar. Policy: \(status.hardeningSummary)"
                : "Relay antwortet unerwartet: \(status.status)"
            lastErrorMessage = nil
        } catch {
            lastRelayHealthMessage = nil
            registerRelayFailure(error, showUserFacingError: true, context: "Relay-Prüfung")
        }
    }

    func importPeer(from encodedPayload: String) {
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
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func verifyPeer(id: String) {
        guard let index = trustedPeers.firstIndex(where: { $0.id == id }) else {
            return
        }
        trustedPeers[index].trustState = .verified
        trustedPeers[index].lastVerifiedAt = Date()
        persistPeers()
    }

    func blockPeer(id: String) {
        guard let index = trustedPeers.firstIndex(where: { $0.id == id }) else {
            return
        }
        trustedPeers[index].trustState = .blocked
        persistPeers()
    }

    func unblockPeerAsUnverified(id: String) {
        guard let index = trustedPeers.firstIndex(where: { $0.id == id }) else {
            return
        }
        trustedPeers[index].trustState = .unverified
        trustedPeers[index].lastVerifiedAt = nil
        persistPeers()
    }

    func deletePeer(id: String) {
        trustedPeers.removeAll { $0.id == id }
        conversations.removeAll { $0.conversation.peerID == id }
        persistPeers()
        persistConversations()
    }

    func makeLocalPairingCode() throws -> String {
        try identityManager.exportPairingPayload(identity: localIdentity)
    }

    func exportLocalPairingCode() -> String {
        (try? makeLocalPairingCode()) ?? ""
    }

    func updateLocalDisplayName(_ displayName: String) {
        do {
            localIdentity = try identityManager.updateDisplayName(displayName, identity: localIdentity)
            lastTransportDiagnosticMessage = "Anzeigename aktualisiert. Der neue Name wird im nächsten Pairing-Code verwendet."
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Anzeigename konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func updateSecurityState(_ state: AppSecurityState) {
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
        } catch {
            lastErrorMessage = error.localizedDescription
        }
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
        guard let storedConversation = conversations.first(where: { $0.id == conversationID }) else {
            return "PrivateChat Export\nChat nicht gefunden."
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var lines: [String] = []
        lines.append("PrivateChat Export")
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
        relayPacketLedger.compact(maxEntries: 500, maxDeliveryReceipts: 500)
        persistRelayPacketLedger()
        lastTransportDiagnosticMessage = "Relay-Ledger kompaktiert: \(relayPacketLedger.entries.count) Pakete, \(relayPacketLedger.deliveryReceipts.count) Receipts bleiben gespeichert."
        lastErrorMessage = nil
    }

    func clearRelayLedger() {
        relayPacketLedger = .empty
        persistRelayPacketLedger()
        lastTransportDiagnosticMessage = "Lokales Relay-Ledger gelöscht. Neue Relay-Pakete werden wieder frisch bewertet."
        lastErrorMessage = nil
    }

    func resetRelayConnectivityBackoff() {
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
        securityAISnapshot = SecurityAISentinel.assess(
            securityState: securityState,
            runtimeSnapshot: runtimeSecuritySnapshot,
            relayConnectivityStatus: relayConnectivityStatus,
            conversations: conversations,
            trustedPeers: trustedPeers,
            relayStats: lastRelayStatsSnapshot,
            localIdentityID: localIdentity.id
        )
    }


    private func syncRelayInbox(showDisabledError: Bool) async {
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
        defer { isRelaySyncRunning = false }
        lastTransportDiagnosticMessage = "Relay-Inbox-Abruf gestartet. \(transportDiagnosticSummary())"

        do {
            let packets = try await transportCoordinator.fetchRelayInbox(
                recipientID: localIdentity.id,
                relayConfiguration: securityState.relayConfiguration
            )
            var processedCount = 0
            var duplicateCount = 0
            var rejectedCount = 0
            var acknowledgedCount = 0
            var acknowledgementFailureCount = 0
            var deliveryReceiptSentCount = 0
            var deliveryReceiptFailureCount = 0

            for packet in packets {
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
                            let didSendReceipt = try await sendDeliveryReceiptIfNeeded(for: receiptContext)
                            if didSendReceipt {
                                deliveryReceiptSentCount += 1
                            }
                        } catch {
                            deliveryReceiptFailureCount += 1
                            lastTransportDiagnosticMessage = "Delivery-Receipt fehlgeschlagen für Nachricht \(receiptContext.originalMessageID.uuidString): \(error.localizedDescription)"
                        }
                    }
                } catch {
                    rejectedCount += 1
                }

                guard relayPacketLedger.shouldAttemptAcknowledgement(packetID: packet.id) else {
                    duplicateCount += 1
                    continue
                }

                do {
                    _ = try await transportCoordinator.deleteRelayPacket(packetID: packet.id, relayConfiguration: securityState.relayConfiguration)
                    acknowledgedCount += 1
                    relayPacketLedger.registerAcknowledged(packetID: packet.id)
                    persistRelayPacketLedger()
                } catch {
                    acknowledgementFailureCount += 1
                    lastTransportDiagnosticMessage = "Relay-ACK fehlgeschlagen für Paket \(packet.id.uuidString): \(error.localizedDescription)"
                }
            }

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
            registerRelayFailure(error, showUserFacingError: showDisabledError, context: "Relay-Inbox-Abruf")
        }
    }

    private func retryPendingOutboundMessages(showEmptyResult: Bool) async {
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

        let pendingMessages = pendingOutboundMessageReferences()
        guard pendingMessages.isEmpty == false else {
            if showEmptyResult {
                lastOutboxRetrySummary = OutboxRetrySummary(attemptedCount: 0, sentCount: 0, failedCount: 0, completedAt: Date())
                lastTransportDiagnosticMessage = "Outbox ist leer. Keine ausstehenden Relay-Nachrichten."
                lastErrorMessage = nil
            }
            return
        }

        isOutboxRetryRunning = true
        defer { isOutboxRetryRunning = false }

        var attemptedCount = 0
        var sentCount = 0
        var failedCount = 0

        for reference in pendingMessages {
            attemptedCount += 1
            do {
                try await deliverOutboundMessage(messageID: reference.messageID, conversationID: reference.conversationID)
                sentCount += 1
            } catch {
                failedCount += 1
            }
        }

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

    private func deliverOutboundMessage(messageID: UUID, conversationID: UUID) async throws {
        guard let context = outboundMessageContext(messageID: messageID, conversationID: conversationID) else {
            return
        }

        guard let peerID = context.peerID else {
            markMessage(messageID, in: conversationID, status: .delivered)
            lastTransportDiagnosticMessage = "Lokale Nachricht gespeichert. Kein Netzwerktransport erforderlich."
            return
        }

        if securityState.transportMode == .relayAllowed {
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
            let packet = try makeTransportPacket(payload: payload, recipientID: peerID)
            try await transportCoordinator.send(
                packet,
                mode: securityState.transportMode,
                relayConfiguration: securityState.relayConfiguration
            )
            let finalStatus: MessageDeliveryStatus = securityState.transportMode == .relayAllowed ? .sentToRelay : .sent
            markMessage(messageID, in: conversationID, status: finalStatus)
            if securityState.transportMode == .relayAllowed {
                registerRelaySuccess(message: "Nachricht wurde verschlüsselt an den Relay übergeben.")
            } else {
                lastTransportDiagnosticMessage = "Nachricht wurde an den lokalen Transport übergeben."
            }
        } catch {
            markMessage(messageID, in: conversationID, status: .failed)
            registerRelayFailure(error, showUserFacingError: true, context: "Nachricht senden")
            throw error
        }
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

    private func makeTransportPacket(payload: TransportMessagePayload, recipientID: String) throws -> OutboundTransportPacket {
        let peer = try verifiedPeer(id: recipientID)
        guard let peerPublicKeyData = Data(base64Encoded: peer.keyAgreementPublicKeyBase64) else {
            throw PrivateChatError.invalidKeyMaterial
        }

        let peerPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKeyData)
        let key = try makePairwiseKey(peerID: recipientID, peerPublicKey: peerPublicKey)
        let payloadData = try encoder.encode(payload)
        let packetID = UUID()
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
        guard packet.protocolVersion == 2,
              packet.recipientID == localIdentity.id,
              packet.senderID != localIdentity.id else {
            throw PrivateChatError.invalidInboundPacket
        }

        let wasSeenBefore = relayPacketLedger.registerSeen(packetID: packet.id)
        persistRelayPacketLedger()

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

            appendInboundMessage(payload: payload, peer: peer)
            let newReceiptContext = relayPacketLedger.wasDeliveryReceiptSent(for: payload.messageID) ? nil : receiptContext
            return InboundPacketProcessResult(didProcessMessage: true, isDuplicate: wasSeenBefore, deliveryReceiptContext: newReceiptContext)

        case .deliveryReceipt:
            guard let deliveredMessageID = payload.deliveredMessageID else {
                throw PrivateChatError.invalidInboundPacket
            }
            let didMarkDelivered = markDeliveredMessage(deliveredMessageID, from: payload.senderID)
            return InboundPacketProcessResult(didProcessMessage: didMarkDelivered, isDuplicate: wasSeenBefore || didMarkDelivered == false, deliveryReceiptContext: nil)
        }
    }

    private func sendDeliveryReceiptIfNeeded(for context: DeliveryReceiptContext) async throws -> Bool {
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
        try await transportCoordinator.send(packet, mode: .relayAllowed, relayConfiguration: securityState.relayConfiguration)
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

    private func appendInboundMessage(payload: TransportMessagePayload, peer: TrustedPeer) {
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
            readAt: nil
        )
        conversations[conversationIndex].messages.append(message)
        conversations[conversationIndex].conversation.updatedAt = max(Date(), payload.createdAt)
        sortConversations()
        persistConversations()
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

    private func markDeliveredMessage(_ messageID: UUID, from peerID: String) -> Bool {
        for conversationIndex in conversations.indices {
            guard let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { message in
                message.id == messageID &&
                message.isIncoming == false &&
                message.recipientID == peerID
            }) else {
                continue
            }

            conversations[conversationIndex].messages[messageIndex].status = .delivered
            conversations[conversationIndex].conversation.updatedAt = Date()
            sortConversations()
            persistConversations()
            return true
        }
        return false
    }

    private func resetInterruptedOutgoingMessages() {
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
            persistConversations()
        }
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

    private func persistConversations() {
        do {
            try messageStore.save(conversations)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func persistPeers() {
        do {
            try peerTrustStore.savePeers(trustedPeers)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
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
