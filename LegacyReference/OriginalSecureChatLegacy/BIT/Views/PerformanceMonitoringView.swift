import SwiftUI

// MARK: - Performance Metrics View
struct PerformanceMonitoringView: View {
    @StateObject private var profiler = PerformanceProfilerService.shared
    @State private var selectedMetricType: MetricType = .memory
    @State private var isRefreshing = false
    @State private var autoRefresh = true
    @State private var refreshInterval: Double = 2.0
    
    enum MetricType {
        case memory
        case cpu
        case database
        case network
        case search
        case encryption
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section("Übersicht") {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Speicher", systemImage: "memorychip")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                Text(formatMemory(profiler.metrics.memoryUsage))
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Label("CPU", systemImage: "cpu")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                Text(String(format: "%.1f%%", profiler.metrics.cpuUsage))
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                            }
                        }
                        .padding(12)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Thermischer Zustand", systemImage: "thermometer")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                Text(profiler.metrics.thermalState)
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(thermalStateColor)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Label("Stromspar", systemImage: "bolt.fill")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                Text(profiler.metrics.isLowPowerMode ? "AN" : "AUS")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(profiler.metrics.isLowPowerMode ? .orange : .green)
                            }
                        }
                        .padding(12)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                Section("Detaillierte Metriken") {
                    Picker("Kategorie", selection: $selectedMetricType) {
                        Text("Speicher").tag(MetricType.memory)
                        Text("CPU").tag(MetricType.cpu)
                        Text("Datenbank").tag(MetricType.database)
                        Text("Netzwerk").tag(MetricType.network)
                        Text("Suche").tag(MetricType.search)
                        Text("Verschlüsselung").tag(MetricType.encryption)
                    }
                    
                    metricDetails
                }
                
                Section("Einstellungen") {
                    Toggle("Auto-Aktualisierung", isOn: $autoRefresh)
                    
                    if autoRefresh {
                        Stepper("Intervall: \(String(format: "%.1f", refreshInterval))s", 
                               value: $refreshInterval, 
                               in: 0.5...10.0, 
                               step: 0.5)
                    }
                }
                
                Section {
                    Button(action: { exportReport() }) {
                        HStack {
                            Image(systemName: "arrow.down.doc")
                            Text("Bericht exportieren")
                        }
                    }
                    
                    Button(action: { profiler.reset() }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Zurücksetzen")
                        }
                    }
                }
            }
            .navigationTitle("Performance-Überwachung")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { refresh() }) {
                        if isRefreshing {
                            ProgressView()
                                .tint(.blue)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .onAppear {
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }
    
    @ViewBuilder
    private var metricDetails: some View {
        switch selectedMetricType {
        case .memory:
            VStack(alignment: .leading, spacing: 8) {
                MetricRow("Aktuell", formatMemory(profiler.metrics.memoryUsage))
                MetricRow("Peak", formatMemory(profiler.metrics.peakMemoryUsage))
                MetricRow("Verfügbar", formatMemory(profiler.metrics.availableMemory))
                MetricRow("Auslastung", String(format: "%.1f%%", profiler.metrics.memoryPercentage))
            }
            
        case .cpu:
            VStack(alignment: .leading, spacing: 8) {
                MetricRow("Aktuell", String(format: "%.1f%%", profiler.metrics.cpuUsage))
                MetricRow("Durchschnitt", String(format: "%.1f%%", profiler.metrics.avgCpuUsage))
                MetricRow("Peak", String(format: "%.1f%%", profiler.metrics.peakCpuUsage))
            }
            
        case .database:
            VStack(alignment: .leading, spacing: 8) {
                MetricRow("Durchschnittliche Abfrage", String(format: "%.2fms", profiler.metrics.avgDatabaseQueryTime))
                MetricRow("Schnellste Abfrage", String(format: "%.2fms", profiler.metrics.minDatabaseQueryTime))
                MetricRow("Langsamste Abfrage", String(format: "%.2fms", profiler.metrics.maxDatabaseQueryTime))
                MetricRow("Abfragen gesamt", "\(profiler.metrics.totalDatabaseQueries)")
            }
            
        case .network:
            VStack(alignment: .leading, spacing: 8) {
                MetricRow("Durchschnittliche Latenz", String(format: "%.0fms", profiler.metrics.avgNetworkLatency))
                MetricRow("Bandbreite (↓)", formatBandwidth(profiler.metrics.downloadBandwidth))
                MetricRow("Bandbreite (↑)", formatBandwidth(profiler.metrics.uploadBandwidth))
                MetricRow("Anfragen gesamt", "\(profiler.metrics.totalNetworkRequests)")
            }
            
        case .search:
            VStack(alignment: .leading, spacing: 8) {
                MetricRow("Durchschnittliche Zeit", String(format: "%.2fms", profiler.metrics.avgSearchTime))
                MetricRow("Schnellste Suche", String(format: "%.2fms", profiler.metrics.minSearchTime))
                MetricRow("Langsamste Suche", String(format: "%.2fms", profiler.metrics.maxSearchTime))
                MetricRow("Suchen gesamt", "\(profiler.metrics.totalSearches)")
            }
            
        case .encryption:
            VStack(alignment: .leading, spacing: 8) {
                MetricRow("Durchschnittliche Zeit", String(format: "%.2fms", profiler.metrics.avgEncryptionTime))
                MetricRow("Verschlüsselungen gesamt", "\(profiler.metrics.totalEncryptions)")
                MetricRow("Entschlüsselungen gesamt", "\(profiler.metrics.totalDecryptions)")
            }
        }
    }
    
    private var thermalStateColor: Color {
        switch profiler.metrics.thermalState {
        case "Kritisch": return .red
        case "Schwerwiegend": return .orange
        case "Nominal": return .green
        default: return .gray
        }
    }
    
    private func refresh() {
        isRefreshing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            profiler.refresh()
            isRefreshing = false
        }
    }
    
    private func startAutoRefresh() {
        // Implementation für Auto-Refresh Timer
    }
    
    private func stopAutoRefresh() {
        // Stop Auto-Refresh Timer
    }
    
    private func exportReport() {
        let report = profiler.generatePerformanceReport()
        // Export als Text/PDF
    }
    
    private func formatMemory(_ bytes: Double) -> String {
        let mb = bytes / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }
    
    private func formatBandwidth(_ bytesPerSecond: Double) -> String {
        let mbps = (bytesPerSecond * 8) / (1000 * 1000)
        return String(format: "%.2f Mbps", mbps)
    }
}

struct MetricRow: View {
    let label: String
    let value: String
    
    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
        }
        .padding(.vertical, 4)
    }
}
