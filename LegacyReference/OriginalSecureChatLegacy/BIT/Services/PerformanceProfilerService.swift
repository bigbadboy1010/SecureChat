import Foundation
import os.log

final class PerformanceProfilerService: ObservableObject {
    static let shared = PerformanceProfilerService()

    @Published private(set) var metrics: PerformanceMetrics = PerformanceMetrics()
    @Published private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    @Published private(set) var lowPowerMode: Bool = false

    private let queue = DispatchQueue(label: "com.secureChat.profiler", attributes: .concurrent)
    private let logger = os.Logger(subsystem: "com.secureChat", category: "performance")
    private var operationMetrics: [String: OperationMetrics] = [:]
    private var memoryMonitor: Timer?
    private var cpuMonitor: Timer?

    private init() {
        setupMonitoring()
    }

    // MARK: - Operation Tracking
    func startOperation(_ name: String) -> OperationHandle {
        let handle = OperationHandle(operationID: UUID().uuidString, name: name)

        queue.async(flags: .barrier) {
            self.operationMetrics[handle.operationID] = OperationMetrics(
                name: name,
                startTime: Date(),
                startMemory: self.getCurrentMemoryUsage()
            )
        }

        return handle
    }

    func endOperation(_ handle: OperationHandle, success: Bool = true) {
        let duration = Date().timeIntervalSince(Date()) // Placeholder, should use start time

        queue.async(flags: .barrier) {
            guard let metric = self.operationMetrics[handle.operationID] else { return }

            let endMemory = self.getCurrentMemoryUsage()
            let memoryDelta = endMemory - metric.startMemory

            let completed = OperationMetrics(
                name: metric.name,
                startTime: metric.startTime,
                endTime: Date(),
                startMemory: metric.startMemory,
                endMemory: endMemory,
                peakMemory: max(metric.startMemory, endMemory),
                success: success,
                errorDescription: success ? nil : "Operation failed"
            )

            self.operationMetrics[handle.operationID] = completed
            self.updateAggregateMetrics(completed)
        }
    }

    // MARK: - CPU Monitoring
    private func getCPUUsage() -> Double {
        var info = rusage()
        guard getrusage(RUSAGE_SELF, &info) == 0 else { return 0 }

        let userTime = Double(info.ru_utime.tv_sec) + Double(info.ru_utime.tv_usec) / 1_000_000
        let sysTime = Double(info.ru_stime.tv_sec) + Double(info.ru_stime.tv_usec) / 1_000_000
        let totalTime = userTime + sysTime

        return min(totalTime, 100.0) // Cap at 100%
    }

    // MARK: - Memory Monitoring
    private func getCurrentMemoryUsage() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size/4)

        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    $0,
                    &count
                )
            }
        }

        guard kerr == KERN_SUCCESS else { return 0 }
        return Int64(info.phys_footprint)
    }

    // MARK: - Database Performance
    func recordDatabaseQuery(
        operation: String,
        table: String,
        rowCount: Int,
        duration: TimeInterval
    ) {
        queue.async(flags: .barrier) {
            var dbMetric = self.metrics.databaseMetrics
            dbMetric.totalQueries += 1
            dbMetric.totalDuration += duration
            dbMetric.averageQueryTime = dbMetric.totalDuration / Double(dbMetric.totalQueries)

            if duration > dbMetric.slowestQueryTime {
                dbMetric.slowestQueryTime = duration
                dbMetric.slowestQuery = "\(operation) on \(table)"
            }

            if duration < dbMetric.fastestQueryTime || dbMetric.fastestQueryTime == 0 {
                dbMetric.fastestQueryTime = duration
            }

            dbMetric.rowsProcessed += rowCount
            self.metrics.databaseMetrics = dbMetric

            if duration > 0.1 { // Log slow queries
                self.logger.warning("Slow query: \(operation) on \(table) took \(String(format: "%.3f", duration))s")
            }
        }
    }

    // MARK: - Network Performance
    func recordNetworkRequest(
        endpoint: String,
        method: String,
        statusCode: Int,
        duration: TimeInterval,
        bytesTransferred: Int
    ) {
        queue.async(flags: .barrier) {
            var networkMetric = self.metrics.networkMetrics
            networkMetric.totalRequests += 1
            networkMetric.totalDuration += duration
            networkMetric.bytesTransferred += bytesTransferred
            networkMetric.averageLatency = networkMetric.totalDuration / Double(networkMetric.totalRequests)

            if statusCode >= 400 {
                networkMetric.failedRequests += 1
            }

            if duration > networkMetric.slowestRequestTime {
                networkMetric.slowestRequestTime = duration
                networkMetric.slowestEndpoint = "\(method) \(endpoint)"
            }

            self.metrics.networkMetrics = networkMetric
        }
    }

    // MARK: - Search Performance
    func recordSearchOperation(
        query: String,
        resultCount: Int,
        duration: TimeInterval
    ) {
        queue.async(flags: .barrier) {
            var searchMetric = self.metrics.searchMetrics
            searchMetric.totalSearches += 1
            searchMetric.totalDuration += duration
            searchMetric.averageSearchTime = searchMetric.totalDuration / Double(searchMetric.totalSearches)
            searchMetric.totalResultsReturned += resultCount

            if resultCount > 0 {
                searchMetric.averageResultsPerSearch = Double(searchMetric.totalResultsReturned) / Double(searchMetric.totalSearches)
            }

            if duration > searchMetric.slowestSearchTime {
                searchMetric.slowestSearchTime = duration
            }

            self.metrics.searchMetrics = searchMetric
        }
    }

    // MARK: - Encryption Performance
    func recordEncryptionOperation(
        operation: String,
        dataSize: Int,
        duration: TimeInterval,
        success: Bool
    ) {
        queue.async(flags: .barrier) {
            var cryptoMetric = self.metrics.cryptographicMetrics
            cryptoMetric.totalOperations += 1

            if operation.contains("encrypt") {
                cryptoMetric.encryptionOps += 1
                cryptoMetric.encryptionDuration += duration
            } else if operation.contains("decrypt") {
                cryptoMetric.decryptionOps += 1
                cryptoMetric.decryptionDuration += duration
            }

            cryptoMetric.bytesProcessed += dataSize

            if !success {
                cryptoMetric.failedOperations += 1
            }

            self.metrics.cryptographicMetrics = cryptoMetric
        }
    }

    // MARK: - Battery Usage Monitoring
    private func setupMonitoring() {
        // Monitor thermal state
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateDidChange),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )

        // Monitor low power mode
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateDidChange),
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )

        // Start periodic memory monitoring
        startMemoryMonitoring()
    }

    @objc private func thermalStateDidChange() {
        DispatchQueue.main.async {
            self.thermalState = ProcessInfo.processInfo.thermalState
            self.logger.info("Thermal state changed: \(self.thermalState.description)")
        }
    }

    @objc private func powerStateDidChange() {
        DispatchQueue.main.async {
            self.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            self.logger.info("Low power mode: \(self.lowPowerMode)")
        }
    }

    // MARK: - Memory Monitoring Loop
    private func startMemoryMonitoring() {
        memoryMonitor = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateMemoryMetrics()
        }

        cpuMonitor = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateCPUMetrics()
        }
    }

    private func updateMemoryMetrics() {
        let currentMemory = getCurrentMemoryUsage()

        queue.async(flags: .barrier) {
            var memoryMetric = self.metrics.memoryMetrics
            memoryMetric.currentUsage = currentMemory
            memoryMetric.peakUsage = max(memoryMetric.peakUsage, currentMemory)
            memoryMetric.averageUsage = (memoryMetric.averageUsage + Double(currentMemory)) / 2

            let systemMemory = ProcessInfo.processInfo.physicalMemory
            memoryMetric.usagePercentage = Double(currentMemory) / Double(systemMemory) * 100

            self.metrics.memoryMetrics = memoryMetric
        }
    }

    private func updateCPUMetrics() {
        let cpuUsage = getCPUUsage()

        queue.async(flags: .barrier) {
            var cpuMetric = self.metrics.cpuMetrics
            cpuMetric.currentUsage = cpuUsage
            cpuMetric.peakUsage = max(cpuMetric.peakUsage, cpuUsage)
            cpuMetric.averageUsage = (cpuMetric.averageUsage + cpuUsage) / 2

            self.metrics.cpuMetrics = cpuMetric
        }
    }

    // MARK: - Aggregate Metrics
    private func updateAggregateMetrics(_ operation: OperationMetrics) {
        var aggregate = metrics.aggregateMetrics
        aggregate.totalOperations += 1

        if operation.success {
            aggregate.successfulOperations += 1
        } else {
            aggregate.failedOperations += 1
        }

        let duration = operation.endTime?.timeIntervalSince(operation.startTime) ?? 0
        aggregate.totalDuration += duration
        aggregate.averageOperationTime = aggregate.totalDuration / Double(aggregate.totalOperations)

        if operation.peakMemory > aggregate.peakMemory {
            aggregate.peakMemory = operation.peakMemory
        }

        metrics.aggregateMetrics = aggregate
    }

    // MARK: - Report Generation
    func generatePerformanceReport() -> String {
        var report = "# Performance Report\n"
        report += "Generated: \(ISO8601DateFormatter().string(from: Date()))\n\n"

        report += "## System Status\n"
        report += "- Thermal State: \(thermalState.description)\n"
        report += "- Low Power Mode: \(lowPowerMode ? "ON" : "OFF")\n\n"

        report += "## Memory\n"
        report += "- Current: \(formatBytes(metrics.memoryMetrics.currentUsage))\n"
        report += "- Peak: \(formatBytes(metrics.memoryMetrics.peakUsage))\n"
        report += "- Usage: \(String(format: "%.1f", metrics.memoryMetrics.usagePercentage))%\n\n"

        report += "## CPU\n"
        report += "- Current: \(String(format: "%.1f", metrics.cpuMetrics.currentUsage))%\n"
        report += "- Peak: \(String(format: "%.1f", metrics.cpuMetrics.peakUsage))%\n"
        report += "- Average: \(String(format: "%.1f", metrics.cpuMetrics.averageUsage))%\n\n"

        report += "## Database\n"
        report += "- Queries: \(metrics.databaseMetrics.totalQueries)\n"
        report += "- Avg Query Time: \(String(format: "%.3f", metrics.databaseMetrics.averageQueryTime))s\n"
        report += "- Slowest: \(metrics.databaseMetrics.slowestQuery) (\(String(format: "%.3f", metrics.databaseMetrics.slowestQueryTime))s)\n"
        report += "- Rows: \(metrics.databaseMetrics.rowsProcessed)\n\n"

        report += "## Network\n"
        report += "- Requests: \(metrics.networkMetrics.totalRequests)\n"
        report += "- Failed: \(metrics.networkMetrics.failedRequests)\n"
        report += "- Avg Latency: \(String(format: "%.3f", metrics.networkMetrics.averageLatency))s\n"
        report += "- Data: \(formatBytes(metrics.networkMetrics.bytesTransferred))\n\n"

        report += "## Search\n"
        report += "- Searches: \(metrics.searchMetrics.totalSearches)\n"
        report += "- Avg Time: \(String(format: "%.3f", metrics.searchMetrics.averageSearchTime))s\n"
        report += "- Avg Results: \(String(format: "%.1f", metrics.searchMetrics.averageResultsPerSearch))\n\n"

        report += "## Cryptography\n"
        report += "- Operations: \(metrics.cryptographicMetrics.totalOperations)\n"
        report += "- Encryptions: \(metrics.cryptographicMetrics.encryptionOps)\n"
        report += "- Decryptions: \(metrics.cryptographicMetrics.decryptionOps)\n"
        report += "- Data Processed: \(formatBytes(metrics.cryptographicMetrics.bytesProcessed))\n"
        report += "- Failed: \(metrics.cryptographicMetrics.failedOperations)\n\n"

        report += "## Overall\n"
        report += "- Operations: \(metrics.aggregateMetrics.totalOperations)\n"
        report += "- Success Rate: \(String(format: "%.1f", Double(metrics.aggregateMetrics.successfulOperations) / Double(max(metrics.aggregateMetrics.totalOperations, 1)) * 100))%\n"
        report += "- Avg Time: \(String(format: "%.3f", metrics.aggregateMetrics.averageOperationTime))s\n"

        return report
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    deinit {
        memoryMonitor?.invalidate()
        cpuMonitor?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Models
struct PerformanceMetrics: Codable {
    var memoryMetrics: MemoryMetrics = MemoryMetrics()
    var cpuMetrics: CPUMetrics = CPUMetrics()
    var databaseMetrics: DatabaseMetrics = DatabaseMetrics()
    var networkMetrics: NetworkMetrics = NetworkMetrics()
    var searchMetrics: SearchMetrics = SearchMetrics()
    var cryptographicMetrics: CryptographicMetrics = CryptographicMetrics()
    var aggregateMetrics: AggregateMetrics = AggregateMetrics()
}

struct MemoryMetrics: Codable {
    var currentUsage: Int64 = 0
    var peakUsage: Int64 = 0
    var averageUsage: Double = 0
    var usagePercentage: Double = 0
}

struct CPUMetrics: Codable {
    var currentUsage: Double = 0
    var peakUsage: Double = 0
    var averageUsage: Double = 0
}

struct DatabaseMetrics: Codable {
    var totalQueries: Int = 0
    var totalDuration: TimeInterval = 0
    var averageQueryTime: TimeInterval = 0
    var slowestQueryTime: TimeInterval = 0
    var fastestQueryTime: TimeInterval = Double.infinity
    var slowestQuery: String = ""
    var rowsProcessed: Int = 0
}

struct NetworkMetrics: Codable {
    var totalRequests: Int = 0
    var failedRequests: Int = 0
    var totalDuration: TimeInterval = 0
    var averageLatency: TimeInterval = 0
    var slowestRequestTime: TimeInterval = 0
    var slowestEndpoint: String = ""
    var bytesTransferred: Int = 0
}

struct SearchMetrics: Codable {
    var totalSearches: Int = 0
    var totalDuration: TimeInterval = 0
    var averageSearchTime: TimeInterval = 0
    var slowestSearchTime: TimeInterval = 0
    var totalResultsReturned: Int = 0
    var averageResultsPerSearch: Double = 0
}

struct CryptographicMetrics: Codable {
    var totalOperations: Int = 0
    var encryptionOps: Int = 0
    var decryptionOps: Int = 0
    var encryptionDuration: TimeInterval = 0
    var decryptionDuration: TimeInterval = 0
    var bytesProcessed: Int = 0
    var failedOperations: Int = 0
}

struct AggregateMetrics: Codable {
    var totalOperations: Int = 0
    var successfulOperations: Int = 0
    var failedOperations: Int = 0
    var totalDuration: TimeInterval = 0
    var averageOperationTime: TimeInterval = 0
    var peakMemory: Int64 = 0
}

struct OperationMetrics: Codable {
    let name: String
    let startTime: Date
    var endTime: Date?
    var startMemory: Int64 = 0
    var endMemory: Int64 = 0
    var peakMemory: Int64 = 0
    var success: Bool = true
    var errorDescription: String?
}

struct OperationHandle {
    let operationID: String
    let name: String
    let startTime: Date = Date()
}

extension ProcessInfo.ThermalState {
    var description: String {
        switch self {
        case .nominal:
            return "Nominal"
        case .fair:
            return "Fair"
        case .serious:
            return "Serious"
        case .critical:
            return "Critical"
        @unknown default:
            return "Unknown"
        }
    }
}

// MARK: - Mach imports for CPU usage
import Darwin

let TASK_VM_INFO = Int32(22)
let TASK_VM_INFO_COUNT = MemoryLayout<task_vm_info>.size / MemoryLayout<natural_t>.size

struct task_vm_info {
    var resident_size: UInt64 = 0
    var virtual_size: UInt64 = 0
    var external_footprint: UInt64 = 0
    var resident_size_peak: UInt64 = 0
    var phys_footprint: UInt64 = 0
    var phys_footprint_peak: UInt64 = 0
    var internal: UInt64 = 0
    var internal_compressed: UInt64 = 0
    var external: UInt64 = 0
    var external_compressed: UInt64 = 0
    var reusable: UInt64 = 0
    var reusable_compressed: UInt64 = 0
    var purgeable_volatile_purgeable: UInt64 = 0
    var purgeable_volatile_nonpurgeable: UInt64 = 0
    var purgeable_nonvolatile_purgeable: UInt64 = 0
    var purgeable_nonvolatile_nonpurgeable: UInt64 = 0
    var compressed: UInt64 = 0
    var compressed_peak: UInt64 = 0
    var compressed_lifetime: UInt64 = 0
    var added_externalFootprint: UInt64 = 0
    var footprint_excluded_as_swapped: UInt64 = 0
    var memory_sharing_bytes_now: UInt64 = 0
    var memory_sharing_bytes_peak: UInt64 = 0
    var ext_mod_base: UInt64 = 0
    var ext_mod_size: UInt64 = 0
}

var task_vm_info_data_t = task_vm_info()
