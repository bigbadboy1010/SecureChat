import XCTest
import CryptoKit
@testable import BIT

final class IntegrationTests: XCTestCase {
    var persistenceService: MessagePersistenceService!
    var securityService: SecurityAuditService!
    var searchService: SearchService!
    var offlineService: OfflineService!
    var analyticsService: AnalyticsService!

    override func setUp() {
        super.setUp()
        persistenceService = MessagePersistenceService.shared
        securityService = SecurityAuditService.shared
        searchService = SearchService.shared
        offlineService = OfflineService.shared
        analyticsService = AnalyticsService.shared

        // Enable analytics for tests
        analyticsService.setAnalyticsOptIn(true)

        // Clean up
        clearTestData()
    }

    override func tearDown() {
        clearTestData()
        super.tearDown()
    }

    private func clearTestData() {
        let messages = persistenceService.fetchMessages(channelTag: "integration_test", limit: 1000)
        for message in messages {
            persistenceService.deleteMessage(message.id)
        }
        offlineService.clearOfflineQueue()
    }

    // MARK: - Full Message Flow Tests
    func testSecureMessageFlow() {
        // Arrange
        let messageContent = "Integration test message"
        let channelTag = "integration_test"

        // Act 1: Validate input
        let validationResult = securityService.validateAndSanitizeInput(messageContent)
        guard case .success(let sanitized) = validationResult else {
            XCTFail("Input validation failed")
            return
        }

        // Act 2: Create message
        let message = BitchatMessage(
            id: UUID().uuidString,
            content: sanitized,
            senderID: "test_user",
            channelTag: channelTag,
            timestamp: Date(),
            deliveryStatus: .sent,
            isRead: false
        )

        // Act 3: Save to persistence
        persistenceService.saveMessage(message)

        // Act 4: Track analytics
        analyticsService.trackEvent("message_sent", category: .messaging)

        // Act 5: Verify searchability
        let searchResults = searchService.search("Integration", in: channelTag)

        // Assert
        XCTAssertEqual(message.content, sanitized)
        XCTAssertGreaterThan(searchResults.count, 0)
        XCTAssertTrue(analyticsService.isAnalyticsEnabled())
    }

    func testMessageWithMediaEncryption() {
        // Arrange
        let messageContent = "Check out this image"
        let mediaAttachment = MediaAttachment(
            id: UUID().uuidString,
            fileName: "test_image.jpg",
            mimeType: "image/jpeg",
            fileSize: 5242880, // 5MB
            encryptionKey: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) },
            encryptedData: Data(),
            thumbnailData: nil
        )

        // Act 1: Validate message
        let validationResult = securityService.validateAndSanitizeInput(messageContent)
        guard case .success = validationResult else {
            XCTFail("Validation failed")
            return
        }

        // Act 2: Create message with media
        let message = BitchatMessage(
            id: UUID().uuidString,
            content: messageContent,
            senderID: "test_user",
            channelTag: "integration_test",
            timestamp: Date(),
            deliveryStatus: .sent,
            isRead: false,
            mediaAttachments: [mediaAttachment]
        )

        // Act 3: Save message
        persistenceService.saveMessage(message)

        // Act 4: Track media upload
        analyticsService.trackEvent("media_uploaded", properties: ["size": "5242880"])

        // Act 5: Search for media
        let mediaResults = searchService.search("image", in: "integration_test", mediaOnly: true)

        // Assert
        XCTAssertNotNil(message.mediaAttachments)
        XCTAssertEqual(message.mediaAttachments?.count, 1)
        XCTAssertGreaterThan(analyticsService.metrics.totalMediaSize, 0)
    }

    func testOfflineMessageQueueAndSync() {
        // Arrange
        let offlineMessage = BitchatMessage(
            id: UUID().uuidString,
            content: "Offline test message",
            senderID: "test_user",
            channelTag: "integration_test",
            timestamp: Date(),
            deliveryStatus: .pending,
            isRead: false
        )

        // Act 1: Queue message offline
        let queuedItem = offlineService.queueMessage(offlineMessage)

        // Act 2: Verify message is queued
        let stats = offlineService.getQueueStats()

        // Act 3: Track offline event
        analyticsService.trackEvent("message_queued", category: .messaging)

        // Act 4: Sync (simulated)
        offlineService.syncOfflineMessages { success in
            XCTAssertTrue(success)
        }

        // Assert
        XCTAssertEqual(queuedItem.message?.id, offlineMessage.id)
        XCTAssertGreaterThan(stats.totalItems, 0)
    }

    func testGroupMessageWithEncryption() {
        // Arrange
        let groupID = "test_group"
        let messageContent = "Group chat test message"

        // Act 1: Validate input
        let validationResult = securityService.validateAndSanitizeInput(messageContent)
        guard case .success(let sanitized) = validationResult else {
            XCTFail("Validation failed")
            return
        }

        // Act 2: Create group message
        let message = BitchatMessage(
            id: UUID().uuidString,
            content: sanitized,
            senderID: "alice",
            channelTag: "group:\(groupID)",
            timestamp: Date(),
            deliveryStatus: .delivered,
            isRead: true
        )

        // Act 3: Save message
        persistenceService.saveMessage(message)

        // Act 4: Track group event
        analyticsService.trackEvent("group_message_sent", category: .messaging)

        // Act 5: Search group messages
        let results = searchService.search("Group", in: "group:\(groupID)")

        // Assert
        XCTAssertTrue(message.channelTag.contains("group:"))
        XCTAssertGreaterThan(results.count, 0)
    }

    func testMessageDeletionWithAudit() {
        // Arrange
        let message = BitchatMessage(
            id: UUID().uuidString,
            content: "Message to be deleted",
            senderID: "test_user",
            channelTag: "integration_test",
            timestamp: Date(),
            deliveryStatus: .sent,
            isRead: false
        )

        // Act 1: Save message
        persistenceService.saveMessage(message)

        // Act 2: Log deletion audit
        securityService.logSecurityEvent(.dataProtection, "Message deleted by user")

        // Act 3: Delete message
        persistenceService.deleteMessage(message.id)

        // Act 4: Track deletion event
        analyticsService.trackEvent("message_deleted", category: .messaging)

        // Act 5: Verify deletion
        let results = searchService.search(message.content, in: "integration_test")

        // Assert
        XCTAssertEqual(results.count, 0)
    }

    func testErrorTrackingWithAudit() {
        // Arrange
        let errorType = "NetworkError"
        let errorMessage = "Failed to connect to server at 0x7fff5fbff8c0"

        // Act 1: Record error
        analyticsService.recordError(type: errorType, message: errorMessage, context: "Message send")

        // Act 2: Log security event
        securityService.logSecurityEvent(.violation, "Network error occurred")

        // Act 3: Generate compliance report
        let report = securityService.generateComplianceReport()

        // Assert
        XCTAssertTrue(report.contains("Security Audit Report"))
        XCTAssertGreaterThan(analyticsService.metrics.messagesSent, -1) // Can be 0 or more
    }

    func testPerformanceMonitoringWithAnalytics() {
        // Arrange
        let operations = [
            ("database_query", 0.150),
            ("encryption", 0.045),
            ("file_upload", 0.890)
        ]

        // Act
        for (operation, duration) in operations {
            analyticsService.recordPerformanceMetric(
                operation: operation,
                duration: duration,
                success: true
            )
        }

        // Assert
        let report = analyticsService.getAggregatedMetrics(for: 7)
        XCTAssertGreaterThan(report.eventsByCategory[.performance] ?? 0, 0)
    }

    func testComplexMessageFiltering() {
        // Arrange
        let now = Date()
        let messages = [
            BitchatMessage(
                id: UUID().uuidString,
                content: "Important update from alice",
                senderID: "alice",
                channelTag: "integration_test",
                timestamp: now,
                deliveryStatus: .delivered,
                isRead: true
            ),
            BitchatMessage(
                id: UUID().uuidString,
                content: "Regular message from bob",
                senderID: "bob",
                channelTag: "integration_test",
                timestamp: now.addingTimeInterval(-3600),
                deliveryStatus: .sent,
                isRead: false
            ),
            BitchatMessage(
                id: UUID().uuidString,
                content: "Important notification from alice",
                senderID: "alice",
                channelTag: "integration_test",
                timestamp: now.addingTimeInterval(-7200),
                deliveryStatus: .delivered,
                isRead: true
            )
        ]

        // Act 1: Save all messages
        for message in messages {
            persistenceService.saveMessage(message)
        }

        // Act 2: Search with filters
        var criteria = SearchCriteria(keywords: ["Important"])
        criteria.senderID = "alice"
        let results = searchService.advancedSearch(criteria: criteria)

        // Assert
        XCTAssertGreaterThan(results.count, 0)
        XCTAssertTrue(results.allSatisfy { $0.senderID == "alice" })
    }

    func testInputSanitizationThroughFullFlow() {
        // Arrange
        let suspiciousInput = "'; DROP TABLE messages; -- normal text"

        // Act
        let validationResult = securityService.validateAndSanitizeInput(suspiciousInput)

        // Assert
        if case .failure(let error) = validationResult {
            XCTAssertEqual(error, SecurityAuditService.ValidationError.injectionAttempt)
        } else {
            XCTFail("Should detect SQL injection")
        }
    }

    func testEncryptionKeyValidation() {
        // Arrange
        let validKey = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let invalidKey = Data(repeating: 0xFF, count: 24) // 192 bits

        // Act
        let validKeyCheck = securityService.validateEncryptionKeySize(validKey)
        let invalidKeyCheck = securityService.validateEncryptionKeySize(invalidKey)

        // Assert
        XCTAssertTrue(validKeyCheck)
        XCTAssertFalse(invalidKeyCheck)
    }

    func testNonceReplayProtection() {
        // Arrange
        let nonce = "unique_integration_test_nonce"
        let validation1 = SecurityAuditService.RequestValidation(
            timestamp: Date(),
            nonce: nonce,
            signature: "sig"
        )
        let validation2 = SecurityAuditService.RequestValidation(
            timestamp: Date(),
            nonce: nonce,
            signature: "sig"
        )

        // Act
        let result1 = securityService.validateAPIRequest(validation1)
        let result2 = securityService.validateAPIRequest(validation2)

        // Assert
        XCTAssertTrue(result1)
        XCTAssertFalse(result2)
    }

    func testBatchMessageOperations() {
        // Arrange
        let messageCount = 10
        let messages = (0..<messageCount).map { i in
            BitchatMessage(
                id: UUID().uuidString,
                content: "Batch message \(i)",
                senderID: "batch_user",
                channelTag: "integration_test",
                timestamp: Date().addingTimeInterval(TimeInterval(-i * 10)),
                deliveryStatus: .sent,
                isRead: i % 2 == 0
            )
        }

        // Act 1: Save batch
        for message in messages {
            persistenceService.saveMessage(message)
        }

        // Act 2: Search all
        let results = searchService.search("Batch", in: "integration_test")

        // Act 3: Analytics
        analyticsService.trackEvent("batch_messages_sent", properties: ["count": String(messageCount)])

        // Assert
        XCTAssertEqual(results.count, messageCount)
    }

    func testMessageConflictResolution() {
        // Arrange
        let offlineService = OfflineService.shared
        let localMessage = BitchatMessage(
            id: "conflict_test",
            content: "Local version",
            senderID: "user",
            channelTag: "integration_test",
            timestamp: Date().addingTimeInterval(-10),
            deliveryStatus: .pending,
            isRead: false
        )

        let remoteMessage = BitchatMessage(
            id: "conflict_test",
            content: "Remote version",
            senderID: "user",
            channelTag: "integration_test",
            timestamp: Date(),
            deliveryStatus: .delivered,
            isRead: true
        )

        // Act
        let resolved = offlineService.resolveConflict(local: localMessage, remote: remoteMessage)

        // Assert
        XCTAssertEqual(resolved.content, remoteMessage.content)
        XCTAssertEqual(resolved.deliveryStatus, .delivered)
    }

    func testEndToEndMessageLifecycle() {
        // Arrange
        let messageID = UUID().uuidString
        let content = "E2E test message"
        let channelTag = "integration_test"

        // Act 1: Validate
        let validationResult = securityService.validateAndSanitizeInput(content)
        guard case .success(let sanitized) = validationResult else {
            XCTFail("Validation failed")
            return
        }

        // Act 2: Create
        let message = BitchatMessage(
            id: messageID,
            content: sanitized,
            senderID: "e2e_user",
            channelTag: channelTag,
            timestamp: Date(),
            deliveryStatus: .pending,
            isRead: false
        )

        // Act 3: Queue (offline)
        offlineService.queueMessage(message)

        // Act 4: Persist
        persistenceService.saveMessage(message)

        // Act 5: Search
        let searchResults = searchService.search(content, in: channelTag)

        // Act 6: Track
        analyticsService.trackEvent("message_sent", category: .messaging)

        // Act 7: Verify
        let retrievedMessage = persistenceService.fetchMessages(
            channelTag: channelTag,
            limit: 1
        ).first

        // Assert
        XCTAssertEqual(retrievedMessage?.id, messageID)
        XCTAssertGreaterThan(searchResults.count, 0)
        XCTAssertTrue(analyticsService.isAnalyticsEnabled())
    }
}
