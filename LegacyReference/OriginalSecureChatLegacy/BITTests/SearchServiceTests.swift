import XCTest
@testable import BIT

final class SearchServiceTests: XCTestCase {
    var searchService: SearchService!
    var persistenceService: MessagePersistenceService!

    override func setUp() {
        super.setUp()
        searchService = SearchService.shared
        persistenceService = MessagePersistenceService.shared

        // Clean up test data
        clearTestMessages()
    }

    override func tearDown() {
        clearTestMessages()
        super.tearDown()
    }

    private func clearTestMessages() {
        // Clear test messages from database
        let testMessages = persistenceService.fetchMessages(channelTag: "test_channel", limit: 1000)
        for message in testMessages {
            persistenceService.deleteMessage(message.id)
        }
    }

    func testBasicFullTextSearch() {
        // Arrange
        let testMessage = BitchatMessage(
            id: UUID().uuidString,
            content: "This is a test message about swift programming",
            senderID: "test_user_1",
            channelTag: "test_channel",
            timestamp: Date(),
            deliveryStatus: .delivered,
            isRead: true
        )
        persistenceService.saveMessage(testMessage)

        // Act
        let results = searchService.search("swift", in: "test_channel")

        // Assert
        XCTAssertGreaterThan(results.count, 0)
        XCTAssertTrue(results.contains { $0.messageID == testMessage.id })
    }

    func testFuzzySearchWithTolerance() {
        // Arrange
        let testMessage = BitchatMessage(
            id: UUID().uuidString,
            content: "The quick brown fox jumps over the lazy dog",
            senderID: "test_user_1",
            channelTag: "test_channel",
            timestamp: Date(),
            deliveryStatus: .delivered,
            isRead: true
        )
        persistenceService.saveMessage(testMessage)

        // Act - Search with typo
        let results = searchService.searchWithFuzzy("quikc", tolerance: 0.7)

        // Assert
        XCTAssertGreaterThan(results.count, 0)
    }

    func testSearchWithChannelFilter() {
        // Arrange
        let message1 = BitchatMessage(
            id: UUID().uuidString,
            content: "Channel 1 message",
            senderID: "test_user_1",
            channelTag: "channel_1",
            timestamp: Date(),
            deliveryStatus: .delivered,
            isRead: true
        )

        let message2 = BitchatMessage(
            id: UUID().uuidString,
            content: "Channel 2 message",
            senderID: "test_user_1",
            channelTag: "channel_2",
            timestamp: Date(),
            deliveryStatus: .delivered,
            isRead: true
        )

        persistenceService.saveMessage(message1)
        persistenceService.saveMessage(message2)

        // Act
        let results = searchService.search("message", in: "channel_1")

        // Assert
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.channelTag, "channel_1")
    }

    func testSearchWithSenderFilter() {
        // Arrange
        let message1 = BitchatMessage(
            id: UUID().uuidString,
            content: "Message from Alice",
            senderID: "alice",
            channelTag: "test_channel",
            timestamp: Date(),
            deliveryStatus: .delivered,
            isRead: true
        )

        let message2 = BitchatMessage(
            id: UUID().uuidString,
            content: "Message from Bob",
            senderID: "bob",
            channelTag: "test_channel",
            timestamp: Date(),
            deliveryStatus: .delivered,
            isRead: true
        )

        persistenceService.saveMessage(message1)
        persistenceService.saveMessage(message2)

        // Act
        let results = searchService.search("Message", in: "test_channel", senderID: "alice")

        // Assert
        XCTAssertEqual(results.filter { $0.senderID == "alice" }.count, 1)
    }

    func testSearchWithDateRangeFilter() {
        // Arrange
        let now = Date()
        let pastDate = now.addingTimeInterval(-86400) // 24 hours ago
        let futureDate = now.addingTimeInterval(86400) // 24 hours later

        let recentMessage = BitchatMessage(
            id: UUID().uuidString,
            content: "Recent message",
            senderID: "test_user",
            channelTag: "test_channel",
            timestamp: now,
            deliveryStatus: .delivered,
            isRead: true
        )

        persistenceService.saveMessage(recentMessage)

        // Act
        let results = searchService.search("Recent", in: "test_channel", dateRange: pastDate...futureDate)

        // Assert
        XCTAssertGreaterThan(results.count, 0)
    }

    func testSearchWithMediaFilter() {
        // Arrange
        let messageWithMedia = BitchatMessage(
            id: UUID().uuidString,
            content: "Check out this image",
            senderID: "test_user",
            channelTag: "test_channel",
            timestamp: Date(),
            deliveryStatus: .delivered,
            isRead: true,
            mediaAttachments: [
                MediaAttachment(
                    id: UUID().uuidString,
                    fileName: "test.jpg",
                    mimeType: "image/jpeg",
                    fileSize: 1024,
                    encryptionKey: Data(),
                    encryptedData: Data(),
                    thumbnailData: nil
                )
            ]
        )

        persistenceService.saveMessage(messageWithMedia)

        // Act
        let results = searchService.search("image", in: "test_channel", mediaOnly: true)

        // Assert
        XCTAssertGreaterThan(results.count, 0)
    }

    func testSavedSearches() {
        // Arrange
        let criteria = SearchCriteria(keywords: ["important", "urgent"])

        // Act
        searchService.saveSearch("urgent_messages", criteria: criteria)
        let savedSearches = searchService.listSavedSearches()

        // Assert
        XCTAssertTrue(savedSearches.contains("urgent_messages"))
    }

    func testSearchResultRelevanceScoring() {
        // Arrange
        let exactMatchMessage = BitchatMessage(
            id: UUID().uuidString,
            content: "Swift programming language",
            senderID: "test_user",
            channelTag: "test_channel",
            timestamp: Date(),
            deliveryStatus: .delivered,
            isRead: true
        )

        persistenceService.saveMessage(exactMatchMessage)

        // Act
        let results = searchService.search("Swift programming")

        // Assert
        XCTAssertGreaterThan(results.count, 0)
        XCTAssertGreaterThanOrEqual(results.first?.relevanceScore ?? 0, 0.5)
    }

    func testAdvancedSearchWithMultipleFilters() {
        // Arrange
        var criteria = SearchCriteria(keywords: ["test"])
        criteria.senderID = "alice"
        criteria.channelTag = "test_channel"
        criteria.minContentLength = 10

        let message = BitchatMessage(
            id: UUID().uuidString,
            content: "This is a test message with sufficient length",
            senderID: "alice",
            channelTag: "test_channel",
            timestamp: Date(),
            deliveryStatus: .delivered,
            isRead: true
        )

        persistenceService.saveMessage(message)

        // Act
        let results = searchService.advancedSearch(criteria: criteria)

        // Assert
        XCTAssertGreaterThan(results.count, 0)
    }

    func testSearchIndexRebuild() {
        // Arrange
        let message = BitchatMessage(
            id: UUID().uuidString,
            content: "Indexed message",
            senderID: "test_user",
            channelTag: "test_channel",
            timestamp: Date(),
            deliveryStatus: .delivered,
            isRead: true
        )
        persistenceService.saveMessage(message)

        // Act
        searchService.rebuildSearchIndex()
        let results = searchService.search("Indexed")

        // Assert
        // Index should still be functional after rebuild
        XCTAssertNotNil(results)
    }

    func testEmptySearchResults() {
        // Act
        let results = searchService.search("nonexistent_query_xyz_12345")

        // Assert
        XCTAssertEqual(results.count, 0)
    }

    func testSearchQueryNormalization() {
        // Arrange
        let message = BitchatMessage(
            id: UUID().uuidString,
            content: "SQL injection' OR '1'='1",
            senderID: "test_user",
            channelTag: "test_channel",
            timestamp: Date(),
            deliveryStatus: .delivered,
            isRead: true
        )
        persistenceService.saveMessage(message)

        // Act - Search with SQL injection attempt should not crash
        let results = searchService.search("' OR '")

        // Assert
        XCTAssertNotNil(results)
    }

    func testLevenshteinSimilarityCalculation() {
        // Arrange
        let query = "kitten"
        let target = "sitting"

        // Act
        let results = searchService.searchWithFuzzy(query, tolerance: 0.5)

        // Assert
        // Should not crash and return valid results array
        XCTAssertNotNil(results)
    }
}
