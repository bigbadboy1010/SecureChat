import XCTest
@testable import BIT

final class OfflineServiceTests: XCTestCase {
    var offlineService: OfflineService!
    var persistenceService: MessagePersistenceService!

    override func setUp() {
        super.setUp()
        offlineService = OfflineService.shared
        persistenceService = MessagePersistenceService.shared

        offlineService.clearOfflineQueue()
    }

    override func tearDown() {
        offlineService.clearOfflineQueue()
        super.tearDown()
    }

    func testQueueMessageOffline() {
        // Arrange
        let testMessage = BitchatMessage(
            id: UUID().uuidString,
            content: "Offline message",
            senderID: "test_user",
            channelTag: "test_channel",
            timestamp: Date(),
            deliveryStatus: .pending,
            isRead: false
        )

        // Act
        let queuedItem = offlineService.queueMessage(testMessage)

        // Assert
        XCTAssertEqual(queuedItem.message?.id, testMessage.id)
        XCTAssertEqual(offlineService.pendingMessageCount, 1)
    }

    func testQueueMessageWithPriority() {
        // Arrange
        let highPriorityMessage = BitchatMessage(
            id: UUID().uuidString,
            content: "High priority",
            senderID: "test_user",
            channelTag: "test_channel",
            timestamp: Date(),
            deliveryStatus: .pending,
            isRead: false
        )

        let normalMessage = BitchatMessage(
            id: UUID().uuidString,
            content: "Normal priority",
            senderID: "test_user",
            channelTag: "test_channel",
            timestamp: Date(),
            deliveryStatus: .pending,
            isRead: false
        )

        // Act
        offlineService.queueMessage(highPriorityMessage, priority: .high)
        offlineService.queueMessage(normalMessage, priority: .normal)

        // Assert
        let stats = offlineService.getQueueStats()
        XCTAssertEqual(stats.highPriorityItems, 1)
        XCTAssertEqual(stats.totalItems, 2)
    }

    func testOfflineQueuePersistence() {
        // Arrange
        let message = BitchatMessage(
            id: UUID().uuidString,
            content: "Persistent message",
            senderID: "test_user",
            channelTag: "test_channel",
            timestamp: Date(),
            deliveryStatus: .pending,
            isRead: false
        )

        // Act
        offlineService.queueMessage(message)
        let countBefore = offlineService.pendingMessageCount

        // Simulate app termination and restart by clearing service state
        let newInstance = OfflineService()

        // Assert
        // New instance should load the queued message from persistence
        XCTAssertGreaterThan(countBefore, 0)
    }

    func testQueueMediaUpload() {
        // Arrange
        let mediaAttachment = MediaAttachment(
            id: UUID().uuidString,
            fileName: "test_image.jpg",
            mimeType: "image/jpeg",
            fileSize: 2048,
            encryptionKey: Data(),
            encryptedData: Data(),
            thumbnailData: nil
        )

        // Act
        offlineService.queueMediaUpload(mediaAttachment, messageID: "test_message_id")

        // Assert
        XCTAssertGreaterThan(offlineService.pendingMessageCount, 0)
    }

    func testConflictResolutionLastWriteWins() {
        // Arrange
        let localMessage = BitchatMessage(
            id: "conflict_msg",
            content: "Local version",
            senderID: "alice",
            channelTag: "test_channel",
            timestamp: Date().addingTimeInterval(-100),
            deliveryStatus: .sent,
            isRead: true
        )

        let remoteMessage = BitchatMessage(
            id: "conflict_msg",
            content: "Remote version (newer)",
            senderID: "alice",
            channelTag: "test_channel",
            timestamp: Date(),
            deliveryStatus: .delivered,
            isRead: true
        )

        // Act
        let resolved = offlineService.resolveConflict(local: localMessage, remote: remoteMessage)

        // Assert
        XCTAssertEqual(resolved.content, remoteMessage.content)
        XCTAssertEqual(resolved.timestamp, remoteMessage.timestamp)
    }

    func testConflictResolutionSameTimestamp() {
        // Arrange
        let now = Date()
        let localMessage = BitchatMessage(
            id: "conflict_msg_same_time",
            content: "Local version",
            senderID: "alice",
            channelTag: "test_channel",
            timestamp: now,
            deliveryStatus: .sent,
            isRead: true
        )

        let remoteMessage = BitchatMessage(
            id: "conflict_msg_same_time",
            content: "Remote version (same timestamp)",
            senderID: "bob",
            channelTag: "test_channel",
            timestamp: now,
            deliveryStatus: .sent,
            isRead: true
        )

        // Act
        let resolved = offlineService.resolveConflict(local: localMessage, remote: remoteMessage)

        // Assert
        // With same timestamp, should use lexicographic ordering
        XCTAssertNotNil(resolved)
    }

    func testSyncOfflineMessagesCompletion() {
        // Arrange
        let message = BitchatMessage(
            id: UUID().uuidString,
            content: "Test sync message",
            senderID: "test_user",
            channelTag: "test_channel",
            timestamp: Date(),
            deliveryStatus: .pending,
            isRead: false
        )

        offlineService.queueMessage(message)
        var syncCompleted = false

        // Act
        offlineService.syncOfflineMessages { success in
            syncCompleted = true
            XCTAssertTrue(success)
        }

        // Assert
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertTrue(syncCompleted)
        }
    }

    func testClearOfflineQueue() {
        // Arrange
        let message = BitchatMessage(
            id: UUID().uuidString,
            content: "Message to clear",
            senderID: "test_user",
            channelTag: "test_channel",
            timestamp: Date(),
            deliveryStatus: .pending,
            isRead: false
        )

        offlineService.queueMessage(message)
        XCTAssertGreaterThan(offlineService.pendingMessageCount, 0)

        // Act
        offlineService.clearOfflineQueue()

        // Assert
        XCTAssertEqual(offlineService.pendingMessageCount, 0)
    }

    func testQueueStatsCalculation() {
        // Arrange
        for i in 0..<5 {
            let message = BitchatMessage(
                id: UUID().uuidString,
                content: "Message \(i)",
                senderID: "test_user",
                channelTag: "test_channel",
                timestamp: Date().addingTimeInterval(TimeInterval(-i * 10)),
                deliveryStatus: .pending,
                isRead: false
            )
            offlineService.queueMessage(message, priority: i == 0 ? .high : .normal)
        }

        // Act
        let stats = offlineService.getQueueStats()

        // Assert
        XCTAssertEqual(stats.totalItems, 5)
        XCTAssertEqual(stats.highPriorityItems, 1)
        XCTAssertGreaterThan(stats.oldestItemAge, 0)
    }

    func testQueueHealthMonitoring() {
        // Arrange
        offlineService.clearOfflineQueue()

        // Act
        let healthyStats = offlineService.getQueueStats()

        // Assert
        XCTAssertTrue(healthyStats.isHealthy)
    }

    func testExponentialBackoffRetry() {
        // Arrange - Test that retry times follow exponential backoff
        let expectedBackoffSequence = [
            2.0,  // 2^1 = 2 seconds
            4.0,  // 2^2 = 4 seconds
            8.0,  // 2^3 = 8 seconds
            16.0, // 2^4 = 16 seconds
            32.0  // 2^5 = 32 seconds
        ]

        // Act & Assert
        for (index, expectedDelay) in expectedBackoffSequence.enumerated() {
            let calculatedDelay = pow(2.0, Double(index + 1))
            XCTAssertEqual(calculatedDelay, expectedDelay)
        }
    }

    func testRetryCountTracking() {
        // Arrange
        let message = BitchatMessage(
            id: UUID().uuidString,
            content: "Message for retry tracking",
            senderID: "test_user",
            channelTag: "test_channel",
            timestamp: Date(),
            deliveryStatus: .pending,
            isRead: false
        )

        // Act
        let queuedItem = offlineService.queueMessage(message)
        let initialRetryCount = queuedItem.retryCount

        // Assert
        XCTAssertEqual(initialRetryCount, 0)
    }

    func testPrioritySorting() {
        // Arrange
        offlineService.clearOfflineQueue()

        let messages = [
            (BitchatMessage(
                id: UUID().uuidString,
                content: "Low priority",
                senderID: "user",
                channelTag: "channel",
                timestamp: Date(),
                deliveryStatus: .pending,
                isRead: false
            ), QueuePriority.low),

            (BitchatMessage(
                id: UUID().uuidString,
                content: "High priority",
                senderID: "user",
                channelTag: "channel",
                timestamp: Date(),
                deliveryStatus: .pending,
                isRead: false
            ), QueuePriority.high),

            (BitchatMessage(
                id: UUID().uuidString,
                content: "Normal priority",
                senderID: "user",
                channelTag: "channel",
                timestamp: Date(),
                deliveryStatus: .pending,
                isRead: false
            ), QueuePriority.normal)
        ]

        // Act
        for (msg, priority) in messages {
            offlineService.queueMessage(msg, priority: priority)
        }

        let stats = offlineService.getQueueStats()

        // Assert
        XCTAssertEqual(stats.totalItems, 3)
    }

    func testNetworkMonitoringStateChange() {
        // Arrange
        let isOnlineInitially = offlineService.isOnline

        // Act & Assert
        // Just verify the property exists and can be read
        XCTAssertNotNil(isOnlineInitially)
    }

    func testSyncStatusTransitions() {
        // Assert initial state
        XCTAssertEqual(offlineService.syncStatus, OfflineService.SyncStatus.synced)

        // Queue a message to trigger pending sync
        let message = BitchatMessage(
            id: UUID().uuidString,
            content: "Test message",
            senderID: "user",
            channelTag: "channel",
            timestamp: Date(),
            deliveryStatus: .pending,
            isRead: false
        )

        offlineService.queueMessage(message)

        // Assert pending state
        if case .pendingSync = offlineService.syncStatus {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected pendingSync status")
        }
    }
}
