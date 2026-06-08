import SwiftUI

struct EnhancedSettingsView: View {
    @AppStorage("bit.analyticsEnabled") private var analyticsEnabled = true
    @AppStorage("bit.lowPowerMode") private var lowPowerMode = false
    @AppStorage("bit.requireBiometrics") private var requireBiometrics = false
    @AppStorage("bit.autoLockSeconds") private var autoLockSeconds: Double = 30
    @AppStorage("bit.showNotifications") private var showNotifications = true
    @State private var selectedTab: SettingsTab = .privacy
    @State private var showPrivacyInfo = false
    @State private var showSecurityInfo = false
    @State private var showAbout = false
    
    enum SettingsTab {
        case privacy
        case security
        case network
        case performance
        case advanced
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section("Einstellungskategorien") {
                    NavigationLink(destination: privacySection) {
                        Label("Datenschutz & Tracking", systemImage: "hand.raised.fill")
                    }
                    NavigationLink(destination: securitySection) {
                        Label("Sicherheit & Authentifizierung", systemImage: "lock.fill")
                    }
                    NavigationLink(destination: networkSection) {
                        Label("Netzwerk & Verbindung", systemImage: "network")
                    }
                    NavigationLink(destination: performanceSection) {
                        Label("Performance-Überwachung", systemImage: "speedometer")
                    }
                    NavigationLink(destination: advancedSection) {
                        Label("Erweiterte Optionen", systemImage: "gearshape.2.fill")
                    }
                }
                
                Section("Info & Support") {
                    NavigationLink(destination: aboutSection) {
                        Label("Über BIT SecureChat", systemImage: "info.circle.fill")
                    }
                    Button(action: { showPrivacyInfo = true }) {
                        Label("Datenschutzerklärung", systemImage: "doc.text.fill")
                    }
                }
            }
            .navigationTitle("Einstellungen")
        }
        .sheet(isPresented: $showPrivacyInfo) {
            PrivacyPolicyView()
        }
    }
    
    @ViewBuilder
    private var privacySection: some View {
        List {
            Section("Tracking & Analytics") {
                Toggle("Analytics aktivieren", isOn: $analyticsEnabled)
                    .help("Hilft uns, die App zu verbessern")
                
                if analyticsEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Datentypen")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Keine persönl. Daten", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.green)
                                
                                Label("Keine Nachrichten", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.green)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Keine Kontakte", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.green)
                                
                                Label("Nur anonyme Metriken", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            Section("Benachrichtigungen") {
                Toggle("Benachrichtigungen", isOn: $showNotifications)
            }
            
            Section {
                Button(action: { deleteAllAnalyticsData() }) {
                    HStack {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.red)
                        Text("Alle Analytics löschen")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .navigationTitle("Datenschutz")
    }
    
    @ViewBuilder
    private var securitySection: some View {
        List {
            Section("Biometrische Authentifizierung") {
                Toggle("Face ID / Touch ID erforderlich", isOn: $requireBiometrics)
                
                if requireBiometrics {
                    Stepper("Auto-Lock nach \(Int(autoLockSeconds))s", 
                           value: $autoLockSeconds, 
                           in: 10...300, 
                           step: 10)
                }
            }
            
            Section {
                NavigationLink(destination: SecurityAuditReportView()) {
                    Label("Sicherheits-Audit", systemImage: "checkmark.shield.fill")
                }
            }
            
            Section("Verschlüsselung") {
                HStack {
                    Label("Ende-zu-Ende", systemImage: "lock.fill")
                    Spacer()
                    Text("AES-256-GCM")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.green)
                }
                
                HStack {
                    Label("Nachrichtenströme", systemImage: "arrow.left.arrow.right.circle.fill")
                    Spacer()
                    Text("Double-Ratchet")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.green)
                }
                
                HStack {
                    Label("Audio/Video", systemImage: "video.fill")
                    Spacer()
                    Text("SRTP")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.green)
                }
            }
        }
        .navigationTitle("Sicherheit")
    }
    
    @ViewBuilder
    private var networkSection: some View {
        List {
            Section {
                NavigationLink(destination: NetworkDiagnosticsView()) {
                    Label("Netzwerk-Diagnostik", systemImage: "waveform.circle")
                }
            }
            
            Section("Verbindungsoptionen") {
                HStack {
                    Label("TLS Version", systemImage: "lock.shield.fill")
                    Spacer()
                    Text("1.3+")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
                
                HStack {
                    Label("Certificate Pinning", systemImage: "checkmark.shield.fill")
                    Spacer()
                    Text("✓ Aktiv")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.green)
                }
                
                Toggle("Stromspar-Modus", isOn: $lowPowerMode)
            }
        }
        .navigationTitle("Netzwerk")
    }
    
    @ViewBuilder
    private var performanceSection: some View {
        List {
            Section {
                NavigationLink(destination: PerformanceMonitoringView()) {
                    Label("Performance-Monitor", systemImage: "speedometer")
                }
            }
        }
        .navigationTitle("Performance")
    }
    
    @ViewBuilder
    private var advancedSection: some View {
        List {
            Section("Entwickler-Tools") {
                NavigationLink(destination: ErrorHistoryView()) {
                    Label("Fehlerhistorie", systemImage: "exclamationmark.triangle.fill")
                }
            }
            
            Section {
                Button(action: { exportDiagnostics() }) {
                    HStack {
                        Image(systemName: "doc.badge.gearshape")
                        Text("Diagnose exportieren")
                    }
                }
                
                Button(action: { resetAppState() }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("App zurücksetzen")
                    }
                }
            }
        }
        .navigationTitle("Erweitert")
    }
    
    @ViewBuilder
    private var aboutSection: some View {
        List {
            Section("App-Informationen") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.gray)
                }
                
                HStack {
                    Text("Build")
                    Spacer()
                    Text("2026.1")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.gray)
                }
                
                HStack {
                    Text("Bundel-ID")
                    Spacer()
                    Text("org.miggu69.BIT")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }
            
            Section("Lizenzen") {
                Text("BIT SecureChat ist frei zugänglich und quelloffen (MIT Lizenz)")
                    .font(.system(size: 12, design: .monospaced))
            }
            
            Section {
                Link(destination: URL(string: "https://github.com/miggu69")!) {
                    Label("GitHub Repository", systemImage: "link.circle.fill")
                }
                
                Link(destination: URL(string: "mailto:miggu69@gmail.com")!) {
                    Label("E-Mail Support", systemImage: "envelope.fill")
                }
            }
        }
        .navigationTitle("Über")
    }
    
    private func deleteAllAnalyticsData() {
        // Delete analytics data
    }
    
    private func exportDiagnostics() {
        // Export diagnostics
    }
    
    private func resetAppState() {
        // Reset app to initial state
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Datenschutzerklärung")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                    
                    Text("Zuletzt aktualisiert: Mai 2026")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.gray)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Datenschutz an erster Stelle")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        Text("BIT SecureChat sammelt keine persönlichen Daten. Alle Nachrichten sind durchgehend verschlüsselt.")
                            .font(.system(size: 12, design: .monospaced))
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("2. Verschlüsselung")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        Text("Alle Kommunikation ist mit AES-256-GCM und Double-Ratchet-Algorithmus verschlüsselt.")
                            .font(.system(size: 12, design: .monospaced))
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("3. Datenspeicherung")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        Text("Daten werden lokal auf Ihrem Gerät gespeichert und gelöscht nach Ihrer Anforderung.")
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .navigationTitle("Datenschutz")
        }
    }
}
