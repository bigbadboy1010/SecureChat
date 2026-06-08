import XCTest
@testable import BIT

final class PerformanceTests: XCTestCase {
    var persistenceService: MessagePersistenceService!
    var searchService: SearchService!
    var offlineService: OfflineService!

    override func setUp() {
        super.setUp()
        persistenceService = MessagePersistenceService.shared
        searchService = SearchService.shared
        offlineService = OfflineService.shared

        clearTestData()
    }

    override func tearDown() {
        clearTestData()
        super.tearDown()
    }

    private func clearTestData() {
        let messages = persistenceService.fetchMessages(channelTag: "perf_test", limit: 10000)
        for message in messages {
            persistenceService.deleteMessage(message.id)
        }
        offlineService.clearOfflineQueue()
    }

    // MARK: - Database Performance Tests
    func testInsert1000Messages() {
        self.measure {
            for i in 0..<1000 {
                let message = BitchatMessage(
                    id: UUID().uuidString,
                    content: "Performance test message \(i)",
                    senderID: "perf_user",
                    channelTag: "perf_test",
                    timestamp: Date().addingTimeInterval(TimeInterval(-i)),
                    deliveryStatus: .sent,
                    isRead: false
                )
                persistenceService.saveMessage(message)
            }
        }
    }

    func testInsert10000Messages() {
        for i in 0..<10000 {
            let message = BitchatMessage(
                id: UUID().uuidString,
                content: "Large scale test \(i)",
                senderID: "perf_user",
                channelTag: "perf_test",
                timestamp: Date().addingTimeInterval(TimeInterval(-i)),
                deliveryStatus: .sent,
                isRead: false
            )
            persistenceService.saveMessage(message)
        }

        self.measure {
            let messages = persistenceService.fetchMessages(channelTag: "perf_test", limit: 10000)
            _ = messages.count
        }
    }

    func testFetchPerformance() {
        // Setup: Insert test data
        for i in 0..<5000 {
            let message = BitchatMessage(
                id: UUID().uuidString,
                content: "Fetch test \(i)",
                senderID: "perf_user",
                channelTag: "perf_test",
                timestamp: Date().addingTimeInterval(TimeInterval(-i)),
                deliveryStatus: .sent,
                isRead: false
            )
            persistenceService.saveMessage(message)
        }

        self.measure {
            _ = persistenceService.fetchMessages(channelTag: "perf_test", limit: 5000)
        }
    }

    func testPaginationPerformance() {
        // Setup: Insert test data
        for i in 0..<2000 {
            let message = BitchatMessage(
                id: UUID().uuidString,
                content: "Pagination test \(i)",
                senderID: "perf_user",
                channelTag: "perf_test",
                timestamp: Date().addingTimeInterval(TimeInterval(-i)),
                deliveryStatus: .sent,
                isRead: false
            )
            persistenceService.saveMessage(message)
        }

        self.measure {
            let page1 = persistenceService.fetchMessages(channelTag: "perf_test", limit: 100, offset: 0)
            let page2 = persistenceService.fetchMessages(channelTag: "perf_test", limit: 100, offset: 100)
            let page3 = persistenceService.fetchMessages(channelTag: "perf_test", limit: 100, offset: 200)
            _ = (page1.count + page2.count + page3.count)
        }
    }

    // MARK: - Search Performance Tests
    func testSearchPerformanceSmallDataset() {
        // Setup
        for i in 0..<1000 {
            let message = BitchatMessage(
                id: UUID().uuidString,
                content: "Swift programming test message \(i)",
                senderID: "perf_user",
                channelTag: "perf_test",
                timestamp: Date().addingTimeInterval(TimeInterval(-i)),
                deliveryStatus: .sent,
                isRead: false
            )
            persistenceService.saveMessage(message)
        }

        self.measure {
            let results = searchService.search("Swift", in: "perf_test")
            _ = results.count
        }
    }

    func testSearchPerformanceLargeDataset() {
        // Setup: 5000 messages
        for i in 0..<5000 {
            let message = BitchatMessage(
                id: UUID().uuidString,
                content: "Test message content \(i % 100) with search keywords",
                senderID: "perf_user_\(i % 10)",
                channelTag: "perf_test",
                timestamp: Date().addingTimeInterval(TimeInterval(-i)),
                deliveryStatus: .sent,
                isRead: false
            )
            persistenceService.saveMessage(message)
        }

        self.measure {
            let results = searchService.search("keywords", in: "perf_test", limit: 50)
            _ = results.count
        }
    }

    func testFuzzySearchPerformance() {
        // Setup
        for i in 0..<1000 {
            let message = BitchatMessage(
                id: UUID().uuidString,
                content: "Fuzzy search test message \(i)",
                senderID: "perf_user",
                channelTag: "perf_test",
                timestamp: Date().addingTimeInterval(TimeInterval(-i)),
                deliveryStatus: .sent,
                isRead: false
            )
            persistenceService.saveMessage(message)
        }

        self.measure {
            let results = searchService.searchWithFuzzy("Fuzzzy", tolerance: 0.7, in: "perf_test")
            _ = results.count
        }
    }

    // MARK: - Offline Queue Performance Tests
    func testQueueing100Messages() {
        self.measure {
            for i in 0..<100 {
                let message = BitchatMessage(
                    id: UUID().uuidString,
                    content: "Queue test \(i)",
                    senderID: "perf_user",
                    channelTag: "perf_test",
                    timestamp: Date(),
                    deliveryStatus: .pending,
                    isRead: false
                )
                offlineService.queueMessage(message)
            }
        }
    }

    func testQueueing500Messages() {
        self.measure {
            for i in 0..<500 {
                let message = BitchatMessage(
                    id: UUID().uuidString,
                    content: "Heavy queue test \(i)",
                    senderID: "perf_user",
                    channelTag: "perf_test",
                    timestamp: Date(),
                    deliveryStatus: .pending,
                    isRead: false
                )
                offlineService.queueMessage(message, priority: i % 3 == 0 ? .high : .normal)
            }
        }
    }

    func testQueueStatisticsPerformance() {
        // Setup
        for i in 0..<200 {
            let message = BitchatMessage(
                id: UUID().uuidString,
                content: "Stats test \(i)",
                senderID: "perf_user",
                channelTag: "perf_test",
                timestamp: Date(),
                deliveryStatus: .pending,
                isRead: false
            )
            offlineService.queueMessage(message)
        }

        self.measure {
            let stats = offlineService.getQueueStats()
            _ = (stats.totalItems, stats.highPriorityItems)
        }
    }

    // MARK: - Stress Tests
    func testConcurrentMessageInserts() {
        let queue = DispatchQueue(label: "concurrent_insert_test", attributes: .concurrent)

        self.measure {
            let group = DispatchGroup()

            for i in 0..<100 {
                group.enter()
                queue.async {
                    let message = BitchatMessage(
                        id: UUID().uuidString,
                        content: "Concurrent test \(i)",
                        senderID: "perf_user_\(i % 5)",
                        channelTag: "perf_test",
                        timestamp: Date(),
                        deliveryStatus: .sent,
                        isRead: false
                    )
                    self.persistenceService.saveMessage(message)
                    group.leave()
                }
            }

            group.wait()
        }
    }

    func testConcurrentSearchOperations() {
        // Setup
        for i in 0..<2000 {
            let message = BitchatMessage(
                id: UUID().uuidString,
                content: "Concurrent search test \(i)",
                senderID: "perf_user",
                channelTag: "perf_test",
                timestamp: Date(),
                deliveryStatus: .sent,
                isRead: false
            )
            persistenceService.saveMessage(message)
        }

        let queue = DispatchQueue(label: "concurrent_search_test", attributes: .concurrent)

        self.measure {
            let group = DispatchGroup()

            for i in 0..<50 {
                group.enter()
                queue.async {
                    let results = self.searchService.search("test", in: "perf_test", limit: 20)
                    _ = results.count
                    group.leave()
                }
            }

            group.wait()
        }
    }

    func testMemoryUsageWithLargeDataset() {
        // Setup large dataset
        for i in 0..<3000 {
            let message = BitchatMessage(
                id: UUID().uuidString,
                content: String(repeating: "Large message content ", count: 10) + String(i),
                senderID: "perf_user",
                channelTag: "perf_test",
                timestamp: Date().addingTimeInterval(TimeInterval(-i)),
                deliveryStatus: .sent,
                isRead: false
            )
            persistenceService.saveMessage(message)
        }

        self.measure {
            // Fetch all and process
            let messages = persistenceService.fetchMessages(channelTag: "perf_test", limit: 3000)
            let totalSize = messages.reduce(0) { $0 + $1.content.count }
            _ = totalSize
        }
    }

    // MARK: - Batch Operation Performance
    func testBatchDeletePerformance() {
        // Setup
        var messageIDs: [String] = []
        for i in 0..<500 {
            let message = BitchatMessage(
                id: UUID().uuidString,
                content: "Delete test \(i)",
                senderID: "perf_user",
                channelTag: "perf_test",
                timestamp: Date(),
                deliveryStatus: .sent,
                isRead: false
            )
            persistenceService.saveMessage(message)
            messageIDs.append(message.id)
        }

        self.measure {
            for id in messageIDs {
                persistenceService.deleteMessage(id)
            }
        }
    }

    // MARK: - String Operations Performance
    func testInputValidationPerformance() {
        let securityService = SecurityAuditService.shared

        self.measure {
            for i in 0..<1000 {
                let input = "Test message \(i) with validation"
                _ = securityService.validateAndSanitizeInput(input)
            }
        }
    }

    func testSQLInjectionDetectionPerformance() {
        let securityService = SecurityAuditService.shared
        let testInputs = [
            "'; DROP TABLE users; --",
            "1' OR '1'='1",
            "UNION SELECT * FROM passwords",
            "../../etc/passwd",
            "%2e%2e%2fetc%2fpasswd"
        ]

        self.measure {
            for i in 0..<500 {
                for input in testInputs {
                    _ = securityService.validateAndSanitizeInput(input)
                }
            }
        }
    }

    // MARK: - Data Migration Performance
    func testMassImportPerformance() {
        let messages = (0..<1000).map { i in
            BitchatMessage(
                id: UUID().uuidString,
                content: "Import test \(i)",
                senderID: "perf_user",
                channelTag: "perf_test",
                timestamp: Date().addingTimeInterval(TimeInterval(-i)),
                deliveryStatus: .sent,
                isRead: false
            )
        }

        self.measure {
            for message in messages {
                persistenceService.saveMessage(message)
            }
        }
    }

    func testQueryWithComplexFilterPerformance() {
        // Setup
        for i in 0..<2000 {
            let message = BitchatMessage(
                id: UUID().uuidString,
                content: "Complex filter test \(i)",
                senderID: "user_\(i % 50)",
                channelTag: "perf_test",
                timestamp: Date().addingTimeInterval(TimeInterval(-i * 3600)),
                deliveryStatus: i % 2 == 0 ? .delivered : .sent,
                isRead: i % 3 == 0
            )
            persistenceService.saveMessage(message)
        }

        let now = Date()
        let weekAgo = now.addingTimeInterval(-7 * 86400)

        self.measure {
            var criteria = SearchCriteria(keywords: ["test"])
            criteria.dateRange = weekAgo...now
            criteria.senderID = "user_1"
            let results = searchService.advancedSearch(criteria: criteria)
            _ = results.count
        }
    }
}
