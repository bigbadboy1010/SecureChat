import Foundation

enum MessageDeliveryStatus: String, Codable, Equatable, CaseIterable {
    case queued
    case sending
    case sentToRelay
    case sent
    case delivered
    case failed

    var localizedTitle: String {
        switch self {
        case .queued:
            return "Wartet"
        case .sending:
            return "Sendet"
        case .sentToRelay:
            return "Am Relay"
        case .sent:
            return "Gesendet"
        case .delivered:
            return "Zugestellt"
        case .failed:
            return "Fehler"
        }
    }

    var systemImageName: String {
        switch self {
        case .queued:
            return "clock"
        case .sending:
            return "arrow.up.circle"
        case .sentToRelay:
            return "tray.and.arrow.up"
        case .sent:
            return "checkmark"
        case .delivered:
            return "checkmark.seal"
        case .failed:
            return "exclamationmark.triangle"
        }
    }
}

enum TrustState: String, Codable, Equatable, CaseIterable {
    case unverified
    case verified
    case blocked
}

enum TransportMode: String, Codable, Equatable, CaseIterable {
    case localOnly
    case relayAllowed
}

struct ChatMessage: Identifiable, Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case id
        case conversationID
        case senderID
        case recipientID
        case body
        case createdAt
        case status
        case isIncoming
        case readAt
        case isStarred
    }

    let id: UUID
    let conversationID: UUID
    let senderID: String
    let recipientID: String?
    var body: String
    let createdAt: Date
    var status: MessageDeliveryStatus
    let isIncoming: Bool
    var readAt: Date?
    var isStarred: Bool

    init(
        id: UUID = UUID(),
        conversationID: UUID,
        senderID: String,
        recipientID: String?,
        body: String,
        createdAt: Date = Date(),
        status: MessageDeliveryStatus,
        isIncoming: Bool,
        readAt: Date? = nil,
        isStarred: Bool = false
    ) {
        self.id = id
        self.conversationID = conversationID
        self.senderID = senderID
        self.recipientID = recipientID
        self.body = body
        self.createdAt = createdAt
        self.status = status
        self.isIncoming = isIncoming
        self.readAt = readAt
        self.isStarred = isStarred
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.conversationID = try container.decode(UUID.self, forKey: .conversationID)
        self.senderID = try container.decode(String.self, forKey: .senderID)
        self.recipientID = try container.decodeIfPresent(String.self, forKey: .recipientID)
        self.body = try container.decode(String.self, forKey: .body)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.status = try container.decode(MessageDeliveryStatus.self, forKey: .status)
        self.isIncoming = try container.decode(Bool.self, forKey: .isIncoming)
        self.readAt = try container.decodeIfPresent(Date.self, forKey: .readAt)
        self.isStarred = try container.decodeIfPresent(Bool.self, forKey: .isStarred) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(conversationID, forKey: .conversationID)
        try container.encode(senderID, forKey: .senderID)
        try container.encodeIfPresent(recipientID, forKey: .recipientID)
        try container.encode(body, forKey: .body)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(status, forKey: .status)
        try container.encode(isIncoming, forKey: .isIncoming)
        try container.encodeIfPresent(readAt, forKey: .readAt)
        try container.encode(isStarred, forKey: .isStarred)
    }
}

struct Conversation: Identifiable, Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case peerID
        case createdAt
        case updatedAt
        case isPinned
        case isArchived
        case isMuted
    }

    let id: UUID
    var title: String
    var peerID: String?
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var isArchived: Bool
    var isMuted: Bool

    init(
        id: UUID = UUID(),
        title: String,
        peerID: String?,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false,
        isArchived: Bool = false,
        isMuted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.peerID = peerID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.isMuted = isMuted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.peerID = try container.decodeIfPresent(String.self, forKey: .peerID)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        self.isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(peerID, forKey: .peerID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encode(isMuted, forKey: .isMuted)
    }
}

struct StoredConversation: Identifiable, Codable, Equatable {
    var id: UUID { conversation.id }
    var conversation: Conversation
    var messages: [ChatMessage]
}

struct TrustedPeer: Identifiable, Codable, Equatable {
    let id: String
    var displayName: String
    let keyAgreementPublicKeyBase64: String
    let signingPublicKeyBase64: String
    let safetyNumber: String
    var trustState: TrustState
    let firstSeenAt: Date
    var lastVerifiedAt: Date?

    init(
        id: String,
        displayName: String,
        keyAgreementPublicKeyBase64: String,
        signingPublicKeyBase64: String,
        safetyNumber: String,
        trustState: TrustState = .unverified,
        firstSeenAt: Date = Date(),
        lastVerifiedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.keyAgreementPublicKeyBase64 = keyAgreementPublicKeyBase64
        self.signingPublicKeyBase64 = signingPublicKeyBase64
        self.safetyNumber = safetyNumber
        self.trustState = trustState
        self.firstSeenAt = firstSeenAt
        self.lastVerifiedAt = lastVerifiedAt
    }
}

struct RelayConfiguration: Codable, Equatable {
    var isEnabled: Bool
    var baseURLString: String
    var registrationToken: String?
    var inboxPollingLimit: Int
    var autoPollingIntervalSeconds: Int
    var retryFailedMessagesAutomatically: Bool
    var autoPurgeRelayInboxAfterSuccessfulSync: Bool
    var verboseRelayLogging: Bool

    var normalizedBaseURLString: String {
        SecureChatProductionProfile.normalizeRelayBaseURL(baseURLString)
    }

    var hasUsableClientToken: Bool {
        SecureChatProductionProfile.isUsableClientToken(registrationToken)
    }

    var readinessIssue: String? {
        SecureChatProductionProfile.readinessIssue(for: self)
    }

    var isReadyForNetworkRequests: Bool {
        readinessIssue == nil
    }

    var migratedForSecureChatProduction: RelayConfiguration {
        SecureChatProductionProfile.migratedConfiguration(self)
    }

    static let disabled = RelayConfiguration(
        isEnabled: false,
        baseURLString: "",
        registrationToken: nil,
        inboxPollingLimit: 50,
        autoPollingIntervalSeconds: 15,
        retryFailedMessagesAutomatically: true,
        autoPurgeRelayInboxAfterSuccessfulSync: false,
        verboseRelayLogging: false
    )

    init(
        isEnabled: Bool,
        baseURLString: String,
        registrationToken: String?,
        inboxPollingLimit: Int = 50,
        autoPollingIntervalSeconds: Int = 15,
        retryFailedMessagesAutomatically: Bool = true,
        autoPurgeRelayInboxAfterSuccessfulSync: Bool = false,
        verboseRelayLogging: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.baseURLString = baseURLString
        self.registrationToken = registrationToken
        self.inboxPollingLimit = max(1, min(inboxPollingLimit, 100))
        self.autoPollingIntervalSeconds = max(5, min(autoPollingIntervalSeconds, 300))
        self.retryFailedMessagesAutomatically = retryFailedMessagesAutomatically
        self.autoPurgeRelayInboxAfterSuccessfulSync = autoPurgeRelayInboxAfterSuccessfulSync
        self.verboseRelayLogging = verboseRelayLogging
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        self.baseURLString = try container.decode(String.self, forKey: .baseURLString)
        self.registrationToken = try container.decodeIfPresent(String.self, forKey: .registrationToken)
        let decodedLimit = try container.decodeIfPresent(Int.self, forKey: .inboxPollingLimit) ?? 50
        let decodedPollingInterval = try container.decodeIfPresent(Int.self, forKey: .autoPollingIntervalSeconds) ?? 15
        self.inboxPollingLimit = max(1, min(decodedLimit, 100))
        self.autoPollingIntervalSeconds = max(5, min(decodedPollingInterval, 300))
        self.retryFailedMessagesAutomatically = try container.decodeIfPresent(Bool.self, forKey: .retryFailedMessagesAutomatically) ?? true
        self.autoPurgeRelayInboxAfterSuccessfulSync = try container.decodeIfPresent(Bool.self, forKey: .autoPurgeRelayInboxAfterSuccessfulSync) ?? false
        self.verboseRelayLogging = try container.decodeIfPresent(Bool.self, forKey: .verboseRelayLogging) ?? false
    }
}

struct AppSecurityState: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case transportMode
        case relayConfiguration
        case requireBiometricUnlock
        case localMessageRetentionDays
        case hideMessagePreviews
        case reduceKeyboardSuggestions
        case warnOnRuntimeRisk
        case restrictRelayOnRuntimeRisk
    }

    var transportMode: TransportMode
    var relayConfiguration: RelayConfiguration
    var requireBiometricUnlock: Bool
    var localMessageRetentionDays: Int
    var hideMessagePreviews: Bool
    var reduceKeyboardSuggestions: Bool
    var warnOnRuntimeRisk: Bool
    var restrictRelayOnRuntimeRisk: Bool

    static let secureDefault = AppSecurityState(
        transportMode: .localOnly,
        relayConfiguration: .disabled,
        requireBiometricUnlock: true,
        localMessageRetentionDays: 30,
        hideMessagePreviews: false,
        reduceKeyboardSuggestions: true,
        warnOnRuntimeRisk: true,
        restrictRelayOnRuntimeRisk: false
    )

    init(
        transportMode: TransportMode,
        relayConfiguration: RelayConfiguration,
        requireBiometricUnlock: Bool,
        localMessageRetentionDays: Int = 30,
        hideMessagePreviews: Bool = false,
        reduceKeyboardSuggestions: Bool = true,
        warnOnRuntimeRisk: Bool = true,
        restrictRelayOnRuntimeRisk: Bool = false
    ) {
        self.transportMode = transportMode
        self.relayConfiguration = relayConfiguration
        self.requireBiometricUnlock = requireBiometricUnlock
        self.localMessageRetentionDays = max(1, min(localMessageRetentionDays, 365))
        self.hideMessagePreviews = hideMessagePreviews
        self.reduceKeyboardSuggestions = reduceKeyboardSuggestions
        self.warnOnRuntimeRisk = warnOnRuntimeRisk
        self.restrictRelayOnRuntimeRisk = restrictRelayOnRuntimeRisk
    }

    func migratedForSecureChatProduction() -> AppSecurityState {
        var migrated = self
        migrated.relayConfiguration = relayConfiguration.migratedForSecureChatProduction
        if migrated.transportMode == .relayAllowed, migrated.relayConfiguration.isEnabled == false {
            // Keep the user's selected mode visible, but prevent background network calls until a valid token is saved.
            migrated.relayConfiguration.isEnabled = false
        }
        return migrated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.transportMode = try container.decodeIfPresent(TransportMode.self, forKey: .transportMode) ?? .localOnly
        self.relayConfiguration = try container.decodeIfPresent(RelayConfiguration.self, forKey: .relayConfiguration) ?? .disabled
        self.requireBiometricUnlock = try container.decodeIfPresent(Bool.self, forKey: .requireBiometricUnlock) ?? true
        let decodedRetention = try container.decodeIfPresent(Int.self, forKey: .localMessageRetentionDays) ?? 30
        self.localMessageRetentionDays = max(1, min(decodedRetention, 365))
        self.hideMessagePreviews = try container.decodeIfPresent(Bool.self, forKey: .hideMessagePreviews) ?? false
        self.reduceKeyboardSuggestions = try container.decodeIfPresent(Bool.self, forKey: .reduceKeyboardSuggestions) ?? true
        self.warnOnRuntimeRisk = try container.decodeIfPresent(Bool.self, forKey: .warnOnRuntimeRisk) ?? true
        self.restrictRelayOnRuntimeRisk = try container.decodeIfPresent(Bool.self, forKey: .restrictRelayOnRuntimeRisk) ?? false

        let migrated = migratedForSecureChatProduction()
        self.transportMode = migrated.transportMode
        self.relayConfiguration = migrated.relayConfiguration
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(transportMode, forKey: .transportMode)
        try container.encode(relayConfiguration, forKey: .relayConfiguration)
        try container.encode(requireBiometricUnlock, forKey: .requireBiometricUnlock)
        try container.encode(localMessageRetentionDays, forKey: .localMessageRetentionDays)
        try container.encode(hideMessagePreviews, forKey: .hideMessagePreviews)
        try container.encode(reduceKeyboardSuggestions, forKey: .reduceKeyboardSuggestions)
        try container.encode(warnOnRuntimeRisk, forKey: .warnOnRuntimeRisk)
        try container.encode(restrictRelayOnRuntimeRisk, forKey: .restrictRelayOnRuntimeRisk)
    }
}

struct RelayInboxSyncSummary: Equatable {
    let processedCount: Int
    let duplicateCount: Int
    let rejectedCount: Int
    let deletedCount: Int
    let acknowledgementFailureCount: Int
    let deliveryReceiptSentCount: Int
    let deliveryReceiptFailureCount: Int
    let receivedAt: Date

    static let empty = RelayInboxSyncSummary(
        processedCount: 0,
        duplicateCount: 0,
        rejectedCount: 0,
        deletedCount: 0,
        acknowledgementFailureCount: 0,
        deliveryReceiptSentCount: 0,
        deliveryReceiptFailureCount: 0,
        receivedAt: Date(timeIntervalSince1970: 0)
    )
}

struct OutboxRetrySummary: Equatable {
    let attemptedCount: Int
    let sentCount: Int
    let failedCount: Int
    let completedAt: Date

    static let empty = OutboxRetrySummary(
        attemptedCount: 0,
        sentCount: 0,
        failedCount: 0,
        completedAt: Date(timeIntervalSince1970: 0)
    )
}

struct RelayStatsSnapshot: Equatable {
    let storedPackets: Int
    let activeRecipients: Int
    let acknowledgedPacketTombstones: Int
    let fetchedAt: Date
}

struct RelayPurgeSummary: Equatable {
    let deletedCount: Int
    let recipientID: String
    let completedAt: Date
}


struct RelayConnectivityStatus: Equatable {
    enum State: String, Equatable {
        case healthy
        case degraded
        case paused
    }

    let state: State
    let consecutiveFailureCount: Int
    let pausedUntil: Date?
    let lastFailureAt: Date?
    let lastSuccessAt: Date?
    let lastErrorMessage: String?

    static let healthy = RelayConnectivityStatus(
        state: .healthy,
        consecutiveFailureCount: 0,
        pausedUntil: nil,
        lastFailureAt: nil,
        lastSuccessAt: nil,
        lastErrorMessage: nil
    )

    var isPaused: Bool {
        guard let pausedUntil else {
            return false
        }
        return pausedUntil > Date()
    }

    var remainingPauseSeconds: Int {
        guard let pausedUntil else {
            return 0
        }
        return max(0, Int(ceil(pausedUntil.timeIntervalSinceNow)))
    }

    var localizedStateTitle: String {
        switch state {
        case .healthy:
            return "Relay stabil"
        case .degraded:
            return "Relay instabil"
        case .paused:
            return isPaused ? "Relay pausiert" : "Relay bereit"
        }
    }
}

struct LocalRetentionSummary: Equatable {
    let deletedMessages: Int
    let deletedConversations: Int
    let completedAt: Date
}


struct ConversationAnalyticsSnapshot: Equatable {
    let messageCount: Int
    let incomingCount: Int
    let outgoingCount: Int
    let starredCount: Int
    let failedCount: Int
    let pendingCount: Int
    let unreadCount: Int
}

struct RelayPacketLedgerEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var firstSeenAt: Date
    var lastSeenAt: Date
    var processCount: Int
    var acknowledgementCount: Int
    var lastAcknowledgedAt: Date?

    init(
        id: UUID,
        firstSeenAt: Date = Date(),
        lastSeenAt: Date = Date(),
        processCount: Int = 0,
        acknowledgementCount: Int = 0,
        lastAcknowledgedAt: Date? = nil
    ) {
        self.id = id
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.processCount = processCount
        self.acknowledgementCount = acknowledgementCount
        self.lastAcknowledgedAt = lastAcknowledgedAt
    }
}

struct DeliveryReceiptLedgerEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var firstSentAt: Date
    var lastSentAt: Date
    var sendCount: Int

    init(
        id: UUID,
        firstSentAt: Date = Date(),
        lastSentAt: Date = Date(),
        sendCount: Int = 1
    ) {
        self.id = id
        self.firstSentAt = firstSentAt
        self.lastSentAt = lastSentAt
        self.sendCount = sendCount
    }
}

struct RelayPacketLedger: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case entries
        case deliveryReceipts
    }

    var entries: [RelayPacketLedgerEntry]
    var deliveryReceipts: [DeliveryReceiptLedgerEntry]

    static let empty = RelayPacketLedger(entries: [], deliveryReceipts: [])

    init(entries: [RelayPacketLedgerEntry], deliveryReceipts: [DeliveryReceiptLedgerEntry] = []) {
        self.entries = entries
        self.deliveryReceipts = deliveryReceipts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.entries = try container.decodeIfPresent([RelayPacketLedgerEntry].self, forKey: .entries) ?? []
        self.deliveryReceipts = try container.decodeIfPresent([DeliveryReceiptLedgerEntry].self, forKey: .deliveryReceipts) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .entries)
        try container.encode(deliveryReceipts, forKey: .deliveryReceipts)
    }

    mutating func registerSeen(packetID: UUID, now: Date = Date()) -> Bool {
        if let index = entries.firstIndex(where: { $0.id == packetID }) {
            entries[index].lastSeenAt = now
            entries[index].processCount += 1
            return true
        }

        entries.append(RelayPacketLedgerEntry(id: packetID, firstSeenAt: now, lastSeenAt: now, processCount: 1))
        compact(maxEntries: 2_000, maxDeliveryReceipts: 2_000)
        return false
    }

    mutating func registerAcknowledged(packetID: UUID, now: Date = Date()) {
        if let index = entries.firstIndex(where: { $0.id == packetID }) {
            entries[index].lastSeenAt = now
            entries[index].lastAcknowledgedAt = now
            entries[index].acknowledgementCount += 1
            return
        }

        entries.append(
            RelayPacketLedgerEntry(
                id: packetID,
                firstSeenAt: now,
                lastSeenAt: now,
                processCount: 0,
                acknowledgementCount: 1,
                lastAcknowledgedAt: now
            )
        )
        compact(maxEntries: 2_000, maxDeliveryReceipts: 2_000)
    }

    func wasAcknowledged(packetID: UUID) -> Bool {
        entries.first { $0.id == packetID }?.lastAcknowledgedAt != nil
    }

    func shouldAttemptAcknowledgement(packetID: UUID, now: Date = Date(), minimumRetryInterval: TimeInterval = 86_400) -> Bool {
        guard let entry = entries.first(where: { $0.id == packetID }), let lastAcknowledgedAt = entry.lastAcknowledgedAt else {
            return true
        }
        return now.timeIntervalSince(lastAcknowledgedAt) >= minimumRetryInterval
    }

    func wasDeliveryReceiptSent(for messageID: UUID) -> Bool {
        deliveryReceipts.contains { $0.id == messageID }
    }

    mutating func registerDeliveryReceiptSent(for messageID: UUID, now: Date = Date()) {
        if let index = deliveryReceipts.firstIndex(where: { $0.id == messageID }) {
            deliveryReceipts[index].lastSentAt = now
            deliveryReceipts[index].sendCount += 1
            return
        }

        deliveryReceipts.append(DeliveryReceiptLedgerEntry(id: messageID, firstSentAt: now, lastSentAt: now, sendCount: 1))
        compact(maxEntries: 2_000, maxDeliveryReceipts: 2_000)
    }

    mutating func compact(maxEntries: Int, maxDeliveryReceipts: Int) {
        if entries.count > maxEntries {
            entries.sort { $0.lastSeenAt > $1.lastSeenAt }
            entries = Array(entries.prefix(maxEntries))
        }

        if deliveryReceipts.count > maxDeliveryReceipts {
            deliveryReceipts.sort { $0.lastSentAt > $1.lastSentAt }
            deliveryReceipts = Array(deliveryReceipts.prefix(maxDeliveryReceipts))
        }
    }
}
