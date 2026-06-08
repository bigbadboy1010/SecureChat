import Foundation

final class AnalyticsService {
    static let shared = AnalyticsService()

    @Published private(set) var metrics: AnalyticsMetrics = AnalyticsMetrics()

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.secureChat.analytics", attributes: .concurrent)
    private var events: [AnalyticsEvent] = []
    private var isOptedIn: Bool {
        UserDefaults.standard.bool(forKey: "analyticsOptIn")
    }

    private init() {
        loadAnalytics()
    }

    // MARK: - Event Tracking
    func trackEvent(
        _ eventName: String,
        properties: [String: String]? = nil,
        category: EventCategory = .general
    ) {
        guard isOptedIn else { return }

        let event = AnalyticsEvent(
            name: eventName,
            timestamp: Date(),
            category: category,
            properties: sanitizeProperties(properties ?? [:]),
            sessionID: getSessionID()
        )

        queue.async(flags: .barrier) {
            self.events.append(event)
            self.updateMetrics(event)
            self.saveAnalytics()
        }
    }

    // MARK: - Metrics Collection
    private func updateMetrics(_ event: AnalyticsEvent) {
        switch event.name {
        case "message_sent":
            metrics.messagesSent += 1
            metrics.lastActiveTime = Date()

        case "group_created":
            metrics.groupsCreated += 1

        case "call_initiated":
            metrics.callsInitiated += 1

        case "media_uploaded":
            metrics.mediaUploaded += 1
            if let sizeStr = event.properties["size"],
               let size = Int64(sizeStr) {
                metrics.totalMediaSize += size
            }

        case "app_opened":
            metrics.sessionCount += 1
            metrics.lastSessionStart = Date()

        default:
            break
        }
    }

    enum EventCategory: String {
        case general
        case messaging
        case calls
        case media
        case groups
        case security
        case performance
        case error
    }

    // MARK: - Privacy Protection
    private func sanitizeProperties(_ properties: [String: String]) -> [String: String] {
        var sanitized = properties

        // Remove PII
        let forbiddenKeys = ["userID", "phoneNumber", "email", "ip", "deviceID", "username"]
        for key in forbiddenKeys {
            sanitized.removeValue(forKey: key)
        }

        // Anonymize values
        sanitized = sanitized.mapValues { value in
            // Remove email patterns
            return value.replacingOccurrences(
                of: "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}",
                with: "[REDACTED_EMAIL]",
                options: .regularExpression
            )
        }

        return sanitized
    }

    // MARK: - Session Management
    private var sessionID: String {
        if let stored = UserDefaults.standard.string(forKey: "analyticsSessionID") {
            return stored
        }

        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: "analyticsSessionID")
        return new
    }

    private func getSessionID() -> String {
        return sessionID
    }

    func startNewSession() {
        UserDefaults.standard.removeObject(forKey: "analyticsSessionID")
        trackEvent("session_started", category: .general)
    }

    // MARK: - Aggregated Reports
    func getAggregatedMetrics(for days: Int = 7) -> AggregatedReport {
        var report = AggregatedReport()

        let cutoffDate = Date().addingTimeInterval(-TimeInterval(days * 86400))

        queue.sync {
            let recentEvents = self.events.filter { $0.timestamp > cutoffDate }

            report.totalEvents = recentEvents.count
            report.uniqueSessions = Set(recentEvents.map { $0.sessionID }).count
            report.averageEventsPerSession = report.totalEvents / max(report.uniqueSessions, 1)

            let categories = Dictionary(grouping: recentEvents, by: { $0.category })
            report.eventsByCategory = categories.mapValues { $0.count }

            // Performance metrics
            if !recentEvents.isEmpty {
                report.generatedAt = Date()
            }
        }

        return report
    }

    struct AggregatedReport {
        var totalEvents: Int = 0
        var uniqueSessions: Int = 0
        var averageEventsPerSession: Int = 0
        var eventsByCategory: [EventCategory: Int] = [:]
        var generatedAt: Date = Date()
    }

    // MARK: - Performance Monitoring
    func recordPerformanceMetric(
        operation: String,
        duration: TimeInterval,
        success: Bool
    ) {
        guard isOptedIn else { return }

        var properties = [
            "duration_ms": String(Int(duration * 1000)),
            "success": String(success)
        ]

        trackEvent(
            "performance_\(operation)",
            properties: properties,
            category: .performance
        )
    }

    // MARK: - Error Tracking
    func recordError(
        type: String,
        message: String,
        context: String? = nil
    ) {
        guard isOptedIn else { return }

        var properties = [
            "error_type": type,
            "error_message": sanitizeErrorMessage(message)
        ]

        if let context = context {
            properties["context"] = context
        }

        trackEvent(
            "error_occurred",
            properties: properties,
            category: .error
        )
    }

    private func sanitizeErrorMessage(_ message: String) -> String {
        // Remove paths, user data, etc.
        var sanitized = message
        sanitized = sanitized.replacingOccurrences(
            of: "/Users/[^/]+",
            with: "/Users/[REDACTED]",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: "0x[0-9a-f]+",
            with: "0x[REDACTED]",
            options: .regularExpression
        )
        return sanitized
    }

    // MARK: - Consent Management
    func setAnalyticsOptIn(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "analyticsOptIn")

        if enabled {
            trackEvent("analytics_enabled", category: .general)
        }

        print(enabled ? "✅ Analytics enabled" : "🔴 Analytics disabled")
    }

    func isAnalyticsEnabled() -> Bool {
        return isOptedIn
    }

    func deleteAllAnalytics() {
        queue.async(flags: .barrier) {
            self.events.removeAll()
            self.metrics = AnalyticsMetrics()
            self.saveAnalytics()
        }

        print("✅ All analytics deleted")
    }

    // MARK: - Export
    func exportAnalyticsReport() -> String {
        var report = "# Analytics Report\n"
        report += "Generated: \(ISO8601DateFormatter().string(from: Date()))\n\n"

        let aggregated = getAggregatedMetrics(for: 30)

        report += "## Summary (Last 30 Days)\n"
        report += "- Total Events: \(aggregated.totalEvents)\n"
        report += "- Unique Sessions: \(aggregated.uniqueSessions)\n"
        report += "- Avg Events/Session: \(aggregated.averageEventsPerSession)\n\n"

        report += "## Events by Category\n"
        for (category, count) in aggregated.eventsByCategory.sorted(by: { $0.value > $1.value }) {
            report += "- \(category.rawValue): \(count)\n"
        }

        report += "\n## Metrics\n"
        report += "- Messages Sent: \(metrics.messagesSent)\n"
        report += "- Groups Created: \(metrics.groupsCreated)\n"
        report += "- Calls Initiated: \(metrics.callsInitiated)\n"
        report += "- Media Uploaded: \(metrics.mediaUploaded)\n"
        report += "- Total Media Size: \(formatBytes(metrics.totalMediaSize))\n"
        report += "- Total Sessions: \(metrics.sessionCount)\n"

        return report
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Persistence
    private func saveAnalytics() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(events) else { return }

        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let analyticsPath = paths[0].appendingPathComponent("analytics.json")

        try? data.write(to: analyticsPath)
    }

    private func loadAnalytics() {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let analyticsPath = paths[0].appendingPathComponent("analytics.json")

        guard let data = try? Data(contentsOf: analyticsPath) else { return }

        let decoder = JSONDecoder()
        if let events = try? decoder.decode([AnalyticsEvent].self, from: data) {
            queue.async(flags: .barrier) {
                self.events = events
            }
        }
    }

    // MARK: - Models
    struct AnalyticsEvent: Codable {
        let name: String
        let timestamp: Date
        let category: EventCategory
        let properties: [String: String]
        let sessionID: String
    }

    struct AnalyticsMetrics: Codable {
        var messagesSent: Int = 0
        var groupsCreated: Int = 0
        var callsInitiated: Int = 0
        var mediaUploaded: Int = 0
        var totalMediaSize: Int64 = 0
        var sessionCount: Int = 0
        var lastActiveTime: Date = Date()
        var lastSessionStart: Date?
    }
}
