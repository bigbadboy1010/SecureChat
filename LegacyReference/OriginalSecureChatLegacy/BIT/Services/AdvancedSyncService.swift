import Foundation

final class AdvancedSyncService: ObservableObject {
    static let shared = AdvancedSyncService()

    @Published private(set) var syncState: SyncState = .idle
    @Published private(set) var conflictResolutions: [ConflictResolution] = []

    private let persistence = MessagePersistenceService.shared
    private let queue = DispatchQueue(label: "com.secureChat.advancedSync", attributes: .concurrent)
    private var vectorClocks: [String: VectorClock] = [:]
    private var conflictLog: [ConflictResolution] = []

    enum SyncState: Equatable {
        case idle
        case syncing
        case resolving
        case complete
        case failed(String)
    }

    private override init() {
        loadVectorClocks()
    }

    // MARK: - Vector Clock Management
    func getOrCreateVectorClock(for nodeID: String) -> VectorClock {
        queue.sync {
            if let existing = vectorClocks[nodeID] {
                return existing
            }
        }

        let newClock = VectorClock(nodeID: nodeID)
        queue.async(flags: .barrier) {
            self.vectorClocks[nodeID] = newClock
            self.saveVectorClocks()
        }

        return newClock
    }

    func incrementVectorClock(for nodeID: String) {
        queue.async(flags: .barrier) {
            if var clock = self.vectorClocks[nodeID] {
                clock.increment(for: nodeID)
                self.vectorClocks[nodeID] = clock
                self.saveVectorClocks()
            }
        }
    }

    func updateVectorClock(for nodeID: String, with remoteClock: VectorClock) {
        queue.async(flags: .barrier) {
            if var clock = self.vectorClocks[nodeID] {
                clock.merge(with: remoteClock)
                self.vectorClocks[nodeID] = clock
                self.saveVectorClocks()
            }
        }
    }

    // MARK: - Causal Ordering
    func determineCausalOrder(
        localMessage: BitchatMessage,
        remoteMessage: BitchatMessage
    ) -> CausalOrdering {
        let localClock = getOrCreateVectorClock(for: localMessage.senderID)
        let remoteClock = getOrCreateVectorClock(for: remoteMessage.senderID)

        let comparison = localClock.compare(with: remoteClock)

        switch comparison {
        case .happensBefore:
            return .remote_happened_before_local
        case .happensAfter:
            return .local_happened_before_remote
        case .concurrent:
            return .concurrent_events
        }
    }

    enum CausalOrdering {
        case local_happened_before_remote
        case remote_happened_before_local
        case concurrent_events
    }

    // MARK: - Advanced Conflict Resolution
    func resolveConflict(
        local: BitchatMessage,
        remote: BitchatMessage,
        strategy: ConflictStrategy = .lastWriteWins
    ) -> ConflictResolution {
        DispatchQueue.main.async {
            self.syncState = .resolving
        }

        let causalOrder = determineCausalOrder(local: local, remote: remote)
        let resolution: BitchatMessage

        switch strategy {
        case .lastWriteWins:
            resolution = local.timestamp > remote.timestamp ? local : remote

        case .vectorClockOrdering:
            switch causalOrder {
            case .local_happened_before_remote:
                resolution = local
            case .remote_happened_before_local:
                resolution = remote
            case .concurrent_events:
                // On concurrent events, use tiebreaker
                resolution = local.id > remote.id ? local : remote
            }

        case .application_specific(let handler):
            resolution = handler(local, remote, causalOrder)

        case .mergeContent:
            resolution = mergeMessages(local: local, remote: remote)
        }

        let conflict = ConflictResolution(
            messageID: local.id,
            localVersion: local,
            remoteVersion: remote,
            resolvedVersion: resolution,
            strategy: String(describing: strategy),
            timestamp: Date(),
            causalOrdering: causalOrder
        )

        queue.async(flags: .barrier) {
            self.conflictLog.append(conflict)
            self.saveConflictLog()
        }

        DispatchQueue.main.async {
            self.syncState = .complete
            self.conflictResolutions.append(conflict)
        }

        return conflict
    }

    // MARK: - Content Merging
    private func mergeMessages(
        local: BitchatMessage,
        remote: BitchatMessage
    ) -> BitchatMessage {
        var merged = local

        // Merge reactions
        var allReactions = local.reactions
        for reaction in remote.reactions {
            if !allReactions.contains(reaction) {
                allReactions.append(reaction)
            }
        }
        merged.reactions = allReactions

        // Merge media attachments
        if let remoteMedia = remote.mediaAttachments {
            var allMedia = merged.mediaAttachments ?? []
            for media in remoteMedia {
                let exists = allMedia.contains { $0.id == media.id }
                if !exists {
                    allMedia.append(media)
                }
            }
            merged.mediaAttachments = allMedia
        }

        // Use newer timestamp
        if remote.timestamp > local.timestamp {
            merged.timestamp = remote.timestamp
            merged.deliveryStatus = remote.deliveryStatus
        }

        // Merge edit history
        var editHistory: [MessageEdit] = merged.editHistory ?? []
        if let remoteEdits = remote.editHistory {
            for edit in remoteEdits {
                let exists = editHistory.contains { $0.timestamp == edit.timestamp }
                if !exists {
                    editHistory.append(edit)
                }
            }
        }
        merged.editHistory = editHistory

        return merged
    }

    enum ConflictStrategy {
        case lastWriteWins
        case vectorClockOrdering
        case application_specific((BitchatMessage, BitchatMessage, CausalOrdering) -> BitchatMessage)
        case mergeContent
    }

    // MARK: - Sync Operations
    func performFullSync(
        localMessages: [BitchatMessage],
        remoteMessages: [BitchatMessage]
    ) -> SyncResult {
        DispatchQueue.main.async {
            self.syncState = .syncing
        }

        var conflicts: [ConflictResolution] = []
        var applied: Int = 0
        var errors: [String] = []

        // Create maps for efficient lookup
        let localMap = Dictionary(uniqueKeysWithValues: localMessages.map { ($0.id, $0) })
        let remoteMap = Dictionary(uniqueKeysWithValues: remoteMessages.map { ($0.id, $0) })

        // Find conflicts (same ID, different content)
        for (messageID, localMsg) in localMap {
            if let remoteMsg = remoteMap[messageID] {
                if localMsg != remoteMsg {
                    let resolution = resolveConflict(local: localMsg, remote: remoteMsg)
                    conflicts.append(resolution)

                    do {
                        try applyResolution(resolution)
                        applied += 1
                    } catch {
                        errors.append("Failed to apply resolution for \(messageID): \(error)")
                    }
                }
            } else {
                // Local message not in remote, send to remote
                applied += 1
            }
        }

        // Find new remote messages
        for (messageID, remoteMsg) in remoteMap {
            if localMap[messageID] == nil {
                // New remote message, add locally
                persistence.saveMessage(remoteMsg)
                applied += 1
            }
        }

        let result = SyncResult(
            totalMessages: localMessages.count + remoteMessages.count,
            conflictsDetected: conflicts.count,
            conflictsResolved: applied,
            errors: errors,
            timestamp: Date()
        )

        DispatchQueue.main.async {
            self.syncState = errors.isEmpty ? .complete : .failed(errors.joined(separator: "; "))
        }

        return result
    }

    private func applyResolution(_ resolution: ConflictResolution) throws {
        persistence.saveMessage(resolution.resolvedVersion)
    }

    // MARK: - Causal Consistency Checks
    func verifyEventOrdering(
        messages: [BitchatMessage]
    ) -> EventOrderingReport {
        var report = EventOrderingReport()
        var seenClocks: [String: VectorClock] = [:]

        for message in messages {
            let clock = getOrCreateVectorClock(for: message.senderID)

            // Check if this message could have happened after previous messages
            if let previousClock = seenClocks.values.last {
                let comparison = clock.compare(with: previousClock)
                switch comparison {
                case .happensBefore, .concurrent:
                    report.violations.append("Message \(message.id) violates causal order")
                case .happensAfter:
                    report.validOrders += 1
                }
            }

            seenClocks[message.senderID] = clock
            report.totalEvents += 1
        }

        report.consistencyPercentage = report.totalEvents > 0 ?
            Double(report.validOrders) / Double(report.totalEvents) * 100 : 0

        return report
    }

    // MARK: - Persistence
    private func saveVectorClocks() {
        let encoder = JSONEncoder()
        let data = try? encoder.encode(vectorClocks)

        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let clockPath = paths[0].appendingPathComponent("vector_clocks.json")

        if let data = data {
            try? data.write(to: clockPath)
        }
    }

    private func loadVectorClocks() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let clockPath = paths[0].appendingPathComponent("vector_clocks.json")

        guard let data = try? Data(contentsOf: clockPath) else { return }

        let decoder = JSONDecoder()
        if let clocks = try? decoder.decode([String: VectorClock].self, from: data) {
            queue.async(flags: .barrier) {
                self.vectorClocks = clocks
            }
        }
    }

    private func saveConflictLog() {
        let encoder = JSONEncoder()
        let data = try? encoder.encode(conflictLog)

        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let logPath = paths[0].appendingPathComponent("conflict_log.json")

        if let data = data {
            try? data.write(to: logPath)
        }
    }

    private func loadConflictLog() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let logPath = paths[0].appendingPathComponent("conflict_log.json")

        guard let data = try? Data(contentsOf: logPath) else { return }

        let decoder = JSONDecoder()
        if let log = try? decoder.decode([ConflictResolution].self, from: data) {
            queue.async(flags: .barrier) {
                self.conflictLog = log
            }
        }
    }

    func exportSyncReport() -> String {
        var report = "# Sync Report\n"
        report += "Generated: \(ISO8601DateFormatter().string(from: Date()))\n\n"

        report += "## Conflicts Resolved\n"
        report += "Total: \(conflictLog.count)\n\n"

        for conflict in conflictLog.suffix(10) {
            report += "### Conflict \(conflict.messageID)\n"
            report += "- Strategy: \(conflict.strategy)\n"
            report += "- Resolved: \(conflict.resolvedVersion.content)\n"
            report += "- Time: \(conflict.timestamp)\n\n"
        }

        report += "## Vector Clocks\n"
        queue.sync {
            for (nodeID, clock) in vectorClocks {
                report += "- \(nodeID): \(clock.timestamp)\n"
            }
        }

        return report
    }
}

// MARK: - Models
struct VectorClock: Codable {
    let nodeID: String
    var timestamp: [String: Int] = [:]

    mutating func increment(for nodeID: String) {
        timestamp[nodeID] = (timestamp[nodeID] ?? 0) + 1
    }

    mutating func merge(with other: VectorClock) {
        for (node, time) in other.timestamp {
            timestamp[node] = max(timestamp[node] ?? 0, time)
        }
    }

    func compare(with other: VectorClock) -> ClockComparison {
        var isGreater = false
        var isLess = false

        let allNodes = Set(timestamp.keys).union(other.timestamp.keys)

        for node in allNodes {
            let ourTime = timestamp[node] ?? 0
            let theirTime = other.timestamp[node] ?? 0

            if ourTime > theirTime {
                isGreater = true
            } else if ourTime < theirTime {
                isLess = true
            }
        }

        if isGreater && !isLess {
            return .happensAfter
        } else if isLess && !isGreater {
            return .happensBefore
        } else {
            return .concurrent
        }
    }

    enum ClockComparison {
        case happensBefore
        case happensAfter
        case concurrent
    }
}

struct ConflictResolution: Codable, Identifiable {
    let id = UUID()
    let messageID: String
    let localVersion: BitchatMessage
    let remoteVersion: BitchatMessage
    let resolvedVersion: BitchatMessage
    let strategy: String
    let timestamp: Date
    let causalOrdering: String

    enum CodingKeys: String, CodingKey {
        case messageID, localVersion, remoteVersion, resolvedVersion, strategy, timestamp, causalOrdering
    }

    init(
        messageID: String,
        localVersion: BitchatMessage,
        remoteVersion: BitchatMessage,
        resolvedVersion: BitchatMessage,
        strategy: String,
        timestamp: Date,
        causalOrdering: AdvancedSyncService.CausalOrdering
    ) {
        self.messageID = messageID
        self.localVersion = localVersion
        self.remoteVersion = remoteVersion
        self.resolvedVersion = resolvedVersion
        self.strategy = strategy
        self.timestamp = timestamp
        self.causalOrdering = String(describing: causalOrdering)
    }
}

struct SyncResult: Codable {
    let totalMessages: Int
    let conflictsDetected: Int
    let conflictsResolved: Int
    let errors: [String]
    let timestamp: Date

    var successRate: Double {
        guard conflictsDetected > 0 else { return 100 }
        return Double(conflictsResolved) / Double(conflictsDetected) * 100
    }
}

struct EventOrderingReport {
    var totalEvents: Int = 0
    var validOrders: Int = 0
    var violations: [String] = []

    var consistencyPercentage: Double = 0
}

extension BitchatMessage: Equatable {
    public static func == (lhs: BitchatMessage, rhs: BitchatMessage) -> Bool {
        lhs.id == rhs.id &&
            lhs.content == rhs.content &&
            lhs.senderID == rhs.senderID &&
            lhs.timestamp == rhs.timestamp &&
            lhs.deliveryStatus == rhs.deliveryStatus
    }
}
