import Foundation
import Network

final class OfflineService: NSObject, ObservableObject {
    static let shared = OfflineService()

    @Published var isOnline: Bool = true
    @Published var syncStatus: SyncStatus = .synced
    @Published var pendingMessageCount: Int = 0

    private var monitor: NWPathMonitor?
    private var queue = DispatchQueue.global(qos: .background)

    private let persistence = MessagePersistenceService.shared
    private let operationQueue = OperationQueue()
    private var offlineQueue: [OfflineQueueItem] = []
    private let dbQueue = DispatchQueue(label: "com.secureChat.offlineQueue", attributes: .concurrent)

    enum SyncStatus {
        case synced
        case syncing
        case pendingSync
        case syncFailed(Error?)
    }

    private override init() {
        super.init()
        setupNetworkMonitoring()
        loadOfflineQueue()
        operationQueue.maxConcurrentOperationCount = 4
    }

    // MARK: - Network Monitoring
    private func setupNetworkMonitoring() {
        monitor = NWPathMonitor()
        monitor?.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let wasOffline = !self?.isOnline ?? true
                self?.isOnline = path.status == .satisfied

                if wasOffline && self?.isOnline ?? false {
                    print("✅ Network restored - syncing offline messages")
                    self?.syncOfflineMessages()
                }
            }
        }

        monitor?.start(queue: queue)
    }

    // MARK: - Offline Queue Management
    func queueMessage(
        _ message: BitchatMessage,
        priority: QueuePriority = .normal
    ) -> OfflineQueueItem {
        let item = OfflineQueueItem(
            message: message,
            priority: priority,
            createdAt: Date(),
            retryCount: 0
        )

        dbQueue.async(flags: .barrier) {
            self.offlineQueue.append(item)
            self.saveOfflineQueue()
        }

        DispatchQueue.main.async {
            self.pendingMessageCount = self.offlineQueue.count
            self.syncStatus = .pendingSync
        }

        print("📤 Message queued offline: \(message.id)")

        // Try to send immediately if online
        if isOnline {
            syncOfflineMessages()
        }

        return item
    }

    func queueMediaUpload(
        _ attachment: MediaAttachment,
        messageID: String,
        priority: QueuePriority = .normal
    ) {
        let item = OfflineQueueItem(
            media: attachment,
            messageID: messageID,
            priority: priority,
            createdAt: Date(),
            retryCount: 0
        )

        dbQueue.async(flags: .barrier) {
            self.offlineQueue.append(item)
            self.saveOfflineQueue()
        }

        DispatchQueue.main.async {
            self.pendingMessageCount = self.offlineQueue.count
        }

        if isOnline {
            syncOfflineMessages()
        }
    }

    // MARK: - Sync Logic
    func syncOfflineMessages(completion: @escaping (Bool) -> Void = { _ in }) {
        guard isOnline else {
            completion(false)
            return
        }

        DispatchQueue.main.async {
            self.syncStatus = .syncing
        }

        dbQueue.sync {
            let itemsToSync = self.offlineQueue.sorted { $0.priority.rawValue < $1.priority.rawValue }

            for item in itemsToSync {
                let op = AsyncOperation { [weak self] finish in
                    self?.processSyncItem(item) { success in
                        if success {
                            self?.dbQueue.async(flags: .barrier) {
                                self?.offlineQueue.removeAll { $0.id == item.id }
                            }
                        } else {
                            // Retry with exponential backoff
                            self?.scheduleRetry(for: item)
                        }
                        finish()
                    }
                }

                self.operationQueue.addOperation(op)
            }

            self.operationQueue.waitUntilAllOperationsAreFinished()

            DispatchQueue.main.async {
                if self.offlineQueue.isEmpty {
                    self.syncStatus = .synced
                    print("✅ All offline messages synced")
                } else {
                    self.syncStatus = .syncFailed(nil)
                }
                self.pendingMessageCount = self.offlineQueue.count
                completion(self.offlineQueue.isEmpty)
            }
        }
    }

    private func processSyncItem(
        _ item: OfflineQueueItem,
        completion: @escaping (Bool) -> Void
    ) {
        if let message = item.message {
            // Send message
            sendMessageToNetwork(message) { success in
                if success {
                    print("✅ Synced message: \(message.id)")
                    self.persistence.saveMessage(message)
                }
                completion(success)
            }
        } else if let media = item.media {
            // Upload media
            uploadMediaToNetwork(media) { success in
                if success {
                    print("✅ Synced media: \(media.fileName)")
                }
                completion(success)
            }
        }
    }

    private func scheduleRetry(for item: OfflineQueueItem) {
        let maxRetries = 5
        let newRetryCount = item.retryCount + 1

        if newRetryCount <= maxRetries {
            // Exponential backoff: 2^retry seconds (2s, 4s, 8s, 16s, 32s)
            let delaySeconds = pow(2.0, Double(newRetryCount))

            dbQueue.asyncAfter(deadline: .now() + delaySeconds) { [weak self] in
                guard var updatedItem = self?.offlineQueue.first(where: { $0.id == item.id }) else { return }
                updatedItem.retryCount = newRetryCount
                updatedItem.lastRetryAt = Date()

                self?.dbQueue.async(flags: .barrier) {
                    if let index = self?.offlineQueue.firstIndex(where: { $0.id == item.id }) {
                        self?.offlineQueue[index] = updatedItem
                        self?.saveOfflineQueue()
                    }
                }

                print("🔄 Retrying sync for \(item.id) (attempt \(newRetryCount)/\(maxRetries))")

                if self?.isOnline ?? false {
                    self?.syncOfflineMessages()
                }
            }
        } else {
            print("❌ Max retries reached for \(item.id)")
            dbQueue.async(flags: .barrier) {
                self.offlineQueue.removeAll { $0.id == item.id }
            }
        }
    }

    // MARK: - Network Operations (Placeholder)
    private func sendMessageToNetwork(
        _ message: BitchatMessage,
        completion: @escaping (Bool) -> Void
    ) {
        // This would integrate with actual network layer
        // For now, simulate network operation
        queue.asyncAfter(deadline: .now() + 0.5) {
            completion(true) // Assume success
        }
    }

    private func uploadMediaToNetwork(
        _ media: MediaAttachment,
        completion: @escaping (Bool) -> Void
    ) {
        // This would upload to actual server/peers
        queue.asyncAfter(deadline: .now() + 1.0) {
            completion(true)
        }
    }

    // MARK: - Conflict Resolution
    func resolveConflict(
        local: BitchatMessage,
        remote: BitchatMessage
    ) -> BitchatMessage {
        // Last-write-wins strategy with vector clocks consideration
        if local.timestamp > remote.timestamp {
            return local
        } else if remote.timestamp > local.timestamp {
            return remote
        } else {
            // Same timestamp: use lexicographic ordering of IDs
            return local.id > remote.id ? local : remote
        }
    }

    // MARK: - Persistence
    private func saveOfflineQueue() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(offlineQueue) else { return }

        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let queuePath = paths[0].appendingPathComponent("offline_queue.json")

        try? data.write(to: queuePath)
    }

    private func loadOfflineQueue() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let queuePath = paths[0].appendingPathComponent("offline_queue.json")

        guard let data = try? Data(contentsOf: queuePath) else { return }

        let decoder = JSONDecoder()
        if let queue = try? decoder.decode([OfflineQueueItem].self, from: data) {
            dbQueue.async(flags: .barrier) {
                self.offlineQueue = queue
            }
        }

        DispatchQueue.main.async {
            self.pendingMessageCount = self.offlineQueue.count
        }
    }

    func clearOfflineQueue() {
        dbQueue.async(flags: .barrier) {
            self.offlineQueue.removeAll()
            self.saveOfflineQueue()
        }

        DispatchQueue.main.async {
            self.pendingMessageCount = 0
            self.syncStatus = .synced
        }
    }

    // MARK: - Statistics
    func getQueueStats() -> QueueStats {
        var stats = QueueStats()

        dbQueue.sync {
            stats.totalItems = offlineQueue.count
            stats.highPriorityItems = offlineQueue.filter { $0.priority == .high }.count
            stats.oldestItemAge = offlineQueue.map { Date().timeIntervalSince($0.createdAt) }.max() ?? 0
            stats.totalRetries = offlineQueue.reduce(0) { $0 + $1.retryCount }
        }

        return stats
    }
}

// MARK: - Models
struct OfflineQueueItem: Codable, Identifiable {
    let id: String = UUID().uuidString
    var message: BitchatMessage?
    var media: MediaAttachment?
    var messageID: String?
    var priority: QueuePriority
    var createdAt: Date
    var lastRetryAt: Date?
    var retryCount: Int
    var status: QueueItemStatus = .pending

    enum QueueItemStatus: String, Codable {
        case pending
        case syncing
        case failed
    }
}

enum QueuePriority: Int, Codable {
    case low = 3
    case normal = 2
    case high = 1
}

struct QueueStats {
    var totalItems: Int = 0
    var highPriorityItems: Int = 0
    var oldestItemAge: TimeInterval = 0 // seconds
    var totalRetries: Int = 0

    var isHealthy: Bool {
        totalItems == 0 && totalRetries < 10
    }
}

// MARK: - Helper
private class AsyncOperation: Operation {
    var finish: (() -> Void)?

    override var isAsynchronous: Bool { true }
    private var _executing = false
    private var _finished = false

    override var isExecuting: Bool {
        return _executing
    }

    override var isFinished: Bool {
        return _finished
    }

    private let block: (@escaping () -> Void) -> Void

    init(block: @escaping (@escaping () -> Void) -> Void) {
        self.block = block
        super.init()
    }

    override func start() {
        willChangeValue(forKey: "isExecuting")
        _executing = true
        didChangeValue(forKey: "isExecuting")

        block { [weak self] in
            self?.finish()
        }
    }

    private func finish() {
        willChangeValue(forKey: "isFinished")
        willChangeValue(forKey: "isExecuting")
        _finished = true
        _executing = false
        didChangeValue(forKey: "isExecuting")
        didChangeValue(forKey: "isFinished")
    }
}
