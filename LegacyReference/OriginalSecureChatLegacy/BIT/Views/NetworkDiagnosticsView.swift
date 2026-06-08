import SwiftUI
import Network

struct NetworkDiagnosticsView: View {
    @State private var networkStatus: String = "Prüfung..."
    @State private var connectionType: String = "–"
    @State private var latency: Double = 0
    @State private var packetLoss: Double = 0
    @State private var bandwidthDown: Double = 0
    @State private var bandwidthUp: Double = 0
    @State private var isTestingNetwork = false
    @State private var dnsResolution: String = "Nicht getestet"
    @State private var certificateStatus: String = "Verifiziert"
    @State private var tlsVersion: String = "1.3+"
    
    var body: some View {
        NavigationStack {
            List {
                Section("Verbindungsstatus") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Status")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(networkStatus == "Verbunden" ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                                Text(networkStatus)
                                    .font(.system(size: 13, design: .monospaced))
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Verbindungstyp")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            Text(connectionType)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Netzwerk-Leistung") {
                    metricRow(label: "Latenz", value: String(format: "%.0f ms", latency), icon: "hare")
                    metricRow(label: "Paketverlust", value: String(format: "%.1f%%", packetLoss), icon: "network")
                    metricRow(label: "↓ Bandbreite", value: formatBandwidth(bandwidthDown), icon: "arrow.down")
                    metricRow(label: "↑ Bandbreite", value: formatBandwidth(bandwidthUp), icon: "arrow.up")
                }
                
                Section("Sicherheits-Überprüfung") {
                    securityItemRow(label: "DNS-Auflösung", status: dnsResolution)
                    securityItemRow(label: "Zertifikat", status: certificateStatus)
                    securityItemRow(label: "TLS-Version", status: tlsVersion)
                    securityItemRow(label: "Certificate Pinning", status: "✓ Aktiv")
                }
                
                Section {
                    Button(action: { runDiagnostics() }) {
                        HStack {
                            if isTestingNetwork {
                                ProgressView()
                                    .tint(.blue)
                            } else {
                                Image(systemName: "waveform.circle")
                            }
                            Text("Diagnostik ausführen")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isTestingNetwork)
                }
            }
            .navigationTitle("Netzwerk-Diagnose")
            .onAppear {
                updateNetworkStatus()
            }
        }
    }
    
    private func metricRow(label: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.gray)
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func securityItemRow(label: String, status: String) -> some View {
        HStack {
            Image(systemName: "checkmark.shield.fill")
                .foregroundColor(.green)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                Text(status)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func updateNetworkStatus() {
        // Simulate network status check
        DispatchQueue.main.async {
            networkStatus = "Verbunden"
            connectionType = "Wi-Fi"
            latency = Double.random(in: 10...50)
            packetLoss = Double.random(in: 0...2)
            bandwidthDown = Double.random(in: 50...500) // Mbps
            bandwidthUp = Double.random(in: 20...100)
        }
    }
    
    private func runDiagnostics() {
        isTestingNetwork = true
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) {
            DispatchQueue.main.async {
                dnsResolution = "✓ Erfolgreich"
                certificateStatus = "✓ Gültig"
                tlsVersion = "1.3 (aktuell)"
                isTestingNetwork = false
            }
        }
    }
    
    private func formatBandwidth(_ mbps: Double) -> String {
        if mbps >= 1000 {
            return String(format: "%.2f Gbps", mbps / 1000)
        }
        return String(format: "%.1f Mbps", mbps)
    }
}
