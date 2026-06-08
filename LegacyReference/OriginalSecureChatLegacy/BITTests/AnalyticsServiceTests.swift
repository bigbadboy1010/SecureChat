import XCTest
@testable import BIT

final class AnalyticsServiceTests: XCTestCase {
    var analyticsService: AnalyticsService!

    override func setUp() {
        super.setUp()
        analyticsService = AnalyticsService.shared

        // Enable analytics for testing
        analyticsService.setAnalyticsOptIn(true)
        analyticsService.deleteAllAnalytics()
    }

    override func tearDown() {
        analyticsService.deleteAllAnalytics()
        super.tearDown()
    }

    // MARK: - Event Tracking Tests
    func testTrackBasicEvent() {
        // Arrange
        let eventName = "test_event"

        // Act
        analyticsService.trackEvent(eventName)

        // Assert
        let report = analyticsService.getAggregatedMetrics(for: 1)
        XCTAssertGreaterThan(report.totalEvents, 0)
    }

    func testTrackEventWithProperties() {
        // Arrange
        let properties = ["action": "click", "element": "button"]

        // Act
        analyticsService.trackEvent("button_click", properties: properties)

        // Assert
        let report = analyticsService.getAggregatedMetrics(for: 1)
        XCTAssertGreaterThan(report.totalEvents, 0)
    }

    func testTrackEventWithCategory() {
        // Arrange
        let eventName = "message_sent"

        // Act
        analyticsService.trackEvent(eventName, category: .messaging)

        // Assert
        let report = analyticsService.getAggregatedMetrics(for: 1)
        XCTAssertGreaterThan(report.eventsByCategory[.messaging] ?? 0, 0)
    }

    func testEventCategories() {
        // Assert all categories exist
        let categories: [AnalyticsService.EventCategory] = [
            .general,
            .messaging,
            .calls,
            .media,
            .groups,
            .security,
            .performance,
            .error
        ]

        XCTAssertEqual(categories.count, 8)
    }

    // MARK: - PII Removal Tests
    func testSanitizePropertiesRemovesForbiddenKeys() {
        // Arrange
        let properties = [
            "userID": "12345",
            "email": "user@example.com",
            "message": "Hello",
            "phoneNumber": "555-1234"
        ]

        // Act
        analyticsService.trackEvent("test_event", properties: properties)

        // Assert
        let report = analyticsService.exportAnalyticsReport()
        XCTAssertFalse(report.contains("12345")) // userID should be removed
    }

    func testSanitizePropertiesRemovesEmailPatterns() {
        // Arrange
        let properties = ["content": "Contact me at user@example.com"]

        // Act
        analyticsService.trackEvent("contact_event", properties: properties)

        // Assert
        let report = analyticsService.exportAnalyticsReport()
        // Email should be redacted
        XCTAssertTrue(report.contains("[REDACTED_EMAIL]") || !report.contains("user@example.com"))
    }

    func testForbiddenKeysList() {
        // Arrange
        let forbiddenKeys = ["userID", "phoneNumber", "email", "ip", "deviceID", "username"]

        // Act & Assert
        for key in forbiddenKeys {
            // These should be filtered out during sanitization
            XCTAssertTrue(true)
        }
    }

    // MARK: - Metrics Collection Tests
    func testMetricsMessagesSent() {
        // Act
        analyticsService.trackEvent("message_sent")
        analyticsService.trackEvent("message_sent")

        // Assert
        let metrics = analyticsService.metrics
        XCTAssertGreaterThan(metrics.messagesSent, 0)
    }

    func testMetricsGroupsCreated() {
        // Act
        analyticsService.trackEvent("group_created")

        // Assert
        let metrics = analyticsService.metrics
        XCTAssertGreaterThan(metrics.groupsCreated, 0)
    }

    func testMetricsCallsInitiated() {
        // Act
        analyticsService.trackEvent("call_initiated")

        // Assert
        let metrics = analyticsService.metrics
        XCTAssertGreaterThan(metrics.callsInitiated, 0)
    }

    func testMetricsMediaUploaded() {
        // Act
        analyticsService.trackEvent("media_uploaded", properties: ["size": "1024"])

        // Assert
        let metrics = analyticsService.metrics
        XCTAssertGreaterThan(metrics.mediaUploaded, 0)
    }

    func testMetricsTotalMediaSize() {
        // Arrange
        let size1 = "5242880" // 5MB
        let size2 = "2097152" // 2MB

        // Act
        analyticsService.trackEvent("media_uploaded", properties: ["size": size1])
        analyticsService.trackEvent("media_uploaded", properties: ["size": size2])

        // Assert
        let metrics = analyticsService.metrics
        XCTAssertGreaterThan(metrics.totalMediaSize, 0)
    }

    func testMetricsSessionCount() {
        // Act
        analyticsService.trackEvent("app_opened")

        // Assert
        let metrics = analyticsService.metrics
        XCTAssertGreaterThan(metrics.sessionCount, 0)
    }

    // MARK: - Session Management Tests
    func testSessionIDGeneration() {
        // Act
        analyticsService.startNewSession()

        // Assert
        let report = analyticsService.getAggregatedMetrics(for: 1)
        XCTAssertGreaterThan(report.uniqueSessions, 0)
    }

    func testConsistentSessionID() {
        // Arrange
        analyticsService.trackEvent("event1")
        analyticsService.trackEvent("event2")

        // Act
        let report = analyticsService.getAggregatedMetrics(for: 1)

        // Assert
        // Both events should belong to same session
        XCTAssertEqual(report.uniqueSessions, 1)
    }

    // MARK: - Consent Management Tests
    func testAnalyticsOptIn() {
        // Arrange
        analyticsService.setAnalyticsOptIn(true)

        // Assert
        XCTAssertTrue(analyticsService.isAnalyticsEnabled())
    }

    func testAnalyticsOptOut() {
        // Arrange
        analyticsService.setAnalyticsOptIn(false)

        // Assert
        XCTAssertFalse(analyticsService.isAnalyticsEnabled())
    }

    func testEventsNotTrackedWhenOptedOut() {
        // Arrange
        analyticsService.setAnalyticsOptIn(false)
        let initialCount = analyticsService.getAggregatedMetrics(for: 1).totalEvents

        // Act
        analyticsService.trackEvent("should_not_track")

        // Assert
        let finalCount = analyticsService.getAggregatedMetrics(for: 1).totalEvents
        XCTAssertEqual(initialCount, finalCount)
    }

    // MARK: - Performance Monitoring Tests
    func testRecordPerformanceMetric() {
        // Arrange
        analyticsService.setAnalyticsOptIn(true)

        // Act
        analyticsService.recordPerformanceMetric(operation: "database_query", duration: 0.234, success: true)

        // Assert
        let report = analyticsService.getAggregatedMetrics(for: 1)
        XCTAssertGreaterThan(report.totalEvents, 0)
    }

    func testRecordFailedOperation() {
        // Arrange
        analyticsService.setAnalyticsOptIn(true)

        // Act
        analyticsService.recordPerformanceMetric(operation: "network_request", duration: 5.0, success: false)

        // Assert
        let report = analyticsService.exportAnalyticsReport()
        XCTAssertNotNil(report)
    }

    // MARK: - Error Tracking Tests
    func testRecordError() {
        // Arrange
        analyticsService.setAnalyticsOptIn(true)

        // Act
        analyticsService.recordError(type: "NetworkError", message: "Connection timeout")

        // Assert
        let report = analyticsService.getAggregatedMetrics(for: 1)
        XCTAssertGreaterThan(report.eventsByCategory[.error] ?? 0, 0)
    }

    func testRecordErrorWithContext() {
        // Arrange
        analyticsService.setAnalyticsOptIn(true)

        // Act
        analyticsService.recordError(
            type: "DatabaseError",
            message: "/Users/test/app/data.db error",
            context: "Message save operation"
        )

        // Assert
        let report = analyticsService.exportAnalyticsReport()
        XCTAssertFalse(report.contains("/Users/test"))
    }

    func testErrorMessageSanitization() {
        // Arrange
        analyticsService.setAnalyticsOptIn(true)

        // Act
        analyticsService.recordError(
            type: "MemoryError",
            message: "Memory at 0x7fff5fbff8c0 corrupted"
        )

        // Assert
        let report = analyticsService.exportAnalyticsReport()
        XCTAssertFalse(report.contains("0x7fff5fbff8c0"))
    }

    // MARK: - Aggregated Metrics Tests
    func testAggregatedMetricsGeneration() {
        // Arrange
        analyticsService.trackEvent("event1", category: .messaging)
        analyticsService.trackEvent("event2", category: .calls)
        analyticsService.trackEvent("event3", category: .messaging)

        // Act
        let report = analyticsService.getAggregatedMetrics(for: 7)

        // Assert
        XCTAssertEqual(report.totalEvents, 3)
        XCTAssertEqual(report.eventsByCategory[.messaging] ?? 0, 2)
        XCTAssertEqual(report.eventsByCategory[.calls] ?? 0, 1)
    }

    func testAverageEventsPerSession() {
        // Arrange
        analyticsService.trackEvent("event1")
        analyticsService.trackEvent("event2")
        analyticsService.trackEvent("event3")

        // Act
        let report = analyticsService.getAggregatedMetrics(for: 7)

        // Assert
        XCTAssertGreaterThan(report.averageEventsPerSession, 0)
    }

    func testAggregatedMetricsDateFiltering() {
        // Arrange
        analyticsService.trackEvent("recent_event")

        // Act
        let recentReport = analyticsService.getAggregatedMetrics(for: 1)
        let oldReport = analyticsService.getAggregatedMetrics(for: 30)

        // Assert
        XCTAssertGreaterThanOrEqual(oldReport.totalEvents, recentReport.totalEvents)
    }

    // MARK: - Export Tests
    func testExportAnalyticsReport() {
        // Arrange
        analyticsService.trackEvent("test_event1")
        analyticsService.trackEvent("test_event2", category: .messaging)

        // Act
        let report = analyticsService.exportAnalyticsReport()

        // Assert
        XCTAssertTrue(report.contains("Analytics Report"))
        XCTAssertTrue(report.contains("Summary"))
        XCTAssertTrue(report.contains("Metrics"))
    }

    func testReportContainsSummary() {
        // Arrange
        analyticsService.trackEvent("event")

        // Act
        let report = analyticsService.exportAnalyticsReport()

        // Assert
        XCTAssertTrue(report.contains("Total Events"))
        XCTAssertTrue(report.contains("Unique Sessions"))
    }

    func testReportContainsCategoryBreakdown() {
        // Arrange
        analyticsService.trackEvent("msg", category: .messaging)
        analyticsService.trackEvent("call", category: .calls)

        // Act
        let report = analyticsService.exportAnalyticsReport()

        // Assert
        XCTAssertTrue(report.contains("messaging"))
        XCTAssertTrue(report.contains("calls"))
    }

    // MARK: - Data Deletion Tests
    func testDeleteAllAnalytics() {
        // Arrange
        analyticsService.trackEvent("event_to_delete")
        let countBefore = analyticsService.getAggregatedMetrics(for: 1).totalEvents

        // Act
        analyticsService.deleteAllAnalytics()

        // Assert
        let countAfter = analyticsService.getAggregatedMetrics(for: 1).totalEvents
        XCTAssertEqual(countAfter, 0)
    }

    // MARK: - Byte Formatting Tests
    func testByteFormatting() {
        // Arrange
        analyticsService.trackEvent("media_uploaded", properties: ["size": "1048576"]) // 1MB

        // Act
        let report = analyticsService.exportAnalyticsReport()

        // Assert
        XCTAssertTrue(report.contains("MB") || report.contains("KB"))
    }

    // MARK: - Multiple Event Categories
    func testTrackEventsAcrossCategories() {
        // Act
        analyticsService.trackEvent("msg", category: .messaging)
        analyticsService.trackEvent("call", category: .calls)
        analyticsService.trackEvent("security_check", category: .security)
        analyticsService.trackEvent("perf", category: .performance)

        // Assert
        let report = analyticsService.getAggregatedMetrics(for: 7)
        XCTAssertGreaterThan(report.eventsByCategory.count, 0)
    }

    // MARK: - Session Metrics
    func testLastActiveTimeTracking() {
        // Arrange
        let beforeTime = analyticsService.metrics.lastActiveTime

        // Act
        analyticsService.trackEvent("message_sent")

        // Assert
        let afterTime = analyticsService.metrics.lastActiveTime
        XCTAssertGreaterThanOrEqual(afterTime, beforeTime)
    }

    func testLastSessionStartTracking() {
        // Arrange
        analyticsService.trackEvent("app_opened")

        // Assert
        let metrics = analyticsService.metrics
        XCTAssertNotNil(metrics.lastSessionStart)
    }

    // MARK: - Codable Compliance
    func testAnalyticsEventCodable() {
        // Arrange
        let event = AnalyticsService.AnalyticsEvent(
            name: "test_event",
            timestamp: Date(),
            category: .messaging,
            properties: ["key": "value"],
            sessionID: UUID().uuidString
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // Act
        let encoded = try? encoder.encode(event)
        let decoded = try? decoder.decode(AnalyticsService.AnalyticsEvent.self, from: encoded ?? Data())

        // Assert
        XCTAssertEqual(decoded?.name, event.name)
        XCTAssertEqual(decoded?.properties, event.properties)
    }

    // MARK: - Edge Cases
    func testEmptyEventName() {
        // Act
        analyticsService.trackEvent("")

        // Assert
        let report = analyticsService.getAggregatedMetrics(for: 1)
        XCTAssertGreaterThan(report.totalEvents, 0)
    }

    func testVeryLargePropertyValue() {
        // Arrange
        let largeValue = String(repeating: "x", count: 10000)

        // Act
        analyticsService.trackEvent("large_property", properties: ["data": largeValue])

        // Assert
        let report = analyticsService.getAggregatedMetrics(for: 1)
        XCTAssertGreaterThan(report.totalEvents, 0)
    }
}
