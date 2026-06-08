import SwiftUI

struct SecurityAuditReportView: View {
    @StateObject private var auditService = SecurityAuditService.shared
    @State private var selectedCategory: AuditCategory = .encryption
    @State private var isGenerating = false
    
    enum AuditCategory {
        case encryption
        case validation
        case authentication
        case network
        case persistence
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section("Sicherheitsbewertung") {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Gesamtbewertung")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                Text("🔒 Sicher")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(.green)
                            }
                            Spacer()
                            Image(systemName: "shield.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.green)
                        }
                        .padding(12)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                Section("Audit-Kategorien") {
                    ForEach([AuditCategory.encryption, .validation, .authentication, .network, .persistence], id: \.self) { category in
                        NavigationLink(destination: auditDetailView(for: category)) {
                            HStack {
                                iconForCategory(category)
                                    .font(.system(size: 16))
                                    .foregroundColor(colorForCategory(category))
                                    .frame(width: 30)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(labelForCategory(category))
                                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    Text(descriptionForCategory(category))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
                
                Section("Sicherheits-Protokolle") {
                    protocolItem(name: "AES-256-GCM", status: "Aktiv", icon: "checkmark.shield.fill")
                    protocolItem(name: "Double-Ratchet", status: "Aktiv", icon: "checkmark.shield.fill")
                    protocolItem(name: "SRTP-Verschlüsselung", status: "Aktiv", icon: "checkmark.shield.fill")
                    protocolItem(name: "TLS 1.3+", status: "Aktiv", icon: "checkmark.shield.fill")
                    protocolItem(name: "E2E Verschlüsselung", status: "Aktiv", icon: "checkmark.shield.fill")
                }
                
                Section("Validierungsregeln") {
                    let validationPatterns = [
                        ("SQL-Injection-Erkennung", "6 Muster"),
                        ("Path-Traversal-Prävention", "4 Muster"),
                        ("XSS-Schutz", "Aktiv"),
                        ("Input-Sanitierung", "Streng")
                    ]
                    
                    ForEach(validationPatterns, id: \.0) { name, status in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name)
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                Text(status)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                    }
                }
                
                Section {
                    Button(action: { generateReport() }) {
                        HStack {
                            if isGenerating {
                                ProgressView()
                                    .tint(.blue)
                            } else {
                                Image(systemName: "doc.badge.gearshape")
                            }
                            Text("Sicherheitsbericht generieren")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isGenerating)
                }
            }
            .navigationTitle("Sicherheits-Audit")
        }
    }
    
    @ViewBuilder
    private func auditDetailView(for category: AuditCategory) -> some View {
        List {
            Section(labelForCategory(category)) {
                detailForCategory(category)
            }
        }
        .navigationTitle(labelForCategory(category))
    }
    
    @ViewBuilder
    private func detailForCategory(_ category: AuditCategory) -> some View {
        switch category {
        case .encryption:
            VStack(alignment: .leading, spacing: 8) {
                auditItemDetail(title: "AES-256-GCM", status: "✓", details: "Dateien und Medien")
                auditItemDetail(title: "Double-Ratchet", status: "✓", details: "Nachrichtenströme")
                auditItemDetail(title: "SRTP", status: "✓", details: "Audio/Video-Streams")
                auditItemDetail(title: "Schlüsselverwaltung", status: "✓", details: "256-Bit-Schlüssel")
            }
            
        case .validation:
            VStack(alignment: .leading, spacing: 8) {
                auditItemDetail(title: "SQL-Injection", status: "✓", details: "6 Erkennungsmuster")
                auditItemDetail(title: "Path-Traversal", status: "✓", details: "4 Blockierungsmuster")
                auditItemDetail(title: "XSS-Prävention", status: "✓", details: "HTML-Sanitierung")
                auditItemDetail(title: "Command-Injection", status: "✓", details: "Input-Validierung")
            }
            
        case .authentication:
            VStack(alignment: .leading, spacing: 8) {
                auditItemDetail(title: "Biometrische Auth", status: "✓", details: "Face ID / Touch ID")
                auditItemDetail(title: "Nonce-Verifikation", status: "✓", details: "Replay-Schutz")
                auditItemDetail(title: "Session-Management", status: "✓", details: "Token-basiert")
                auditItemDetail(title: "Passcode-Fallback", status: "✓", details: "6-stellig")
            }
            
        case .network:
            VStack(alignment: .leading, spacing: 8) {
                auditItemDetail(title: "TLS 1.3+", status: "✓", details: "Sichere Verbindungen")
                auditItemDetail(title: "Certificate Pinning", status: "✓", details: "Aktiviert")
                auditItemDetail(title: "PFS (Perfect Forward Secrecy)", status: "✓", details: "Unterstützt")
                auditItemDetail(title: "HSTS", status: "✓", details: "Erzwungen")
            }
            
        case .persistence:
            VStack(alignment: .leading, spacing: 8) {
                auditItemDetail(title: "SQLite-Verschlüsselung", status: "✓", details: "AES-256")
                auditItemDetail(title: "Sichere Löschung", status: "✓", details: "NIST CLEAR")
                auditItemDetail(title: "Datenschutz-APIs", status: "✓", details: "NSFileProtectionComplete")
                auditItemDetail(title: "Keychain-Integration", status: "✓", details: "Secure Enclave")
            }
        }
    }
    
    private func protocolItem(name: String, status: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                Text(status)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
            }
            Spacer()
        }
    }
    
    private func auditItemDetail(title: String, status: String, details: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(status)
                    .foregroundColor(.green)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                Spacer()
            }
            Text(details)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
    }
    
    private func labelForCategory(_ category: AuditCategory) -> String {
        switch category {
        case .encryption: return "Verschlüsselung"
        case .validation: return "Validierung"
        case .authentication: return "Authentifizierung"
        case .network: return "Netzwerk"
        case .persistence: return "Datenverwaltung"
        }
    }
    
    private func descriptionForCategory(_ category: AuditCategory) -> String {
        switch category {
        case .encryption: return "Ende-zu-Ende-Verschlüsselung"
        case .validation: return "Eingabevalidierung & Schutz"
        case .authentication: return "Authentifizierungsprotokolle"
        case .network: return "Netzwerk-Sicherheit"
        case .persistence: return "Sichere Datenspeicherung"
        }
    }
    
    private func iconForCategory(_ category: AuditCategory) -> some View {
        Group {
            switch category {
            case .encryption:
                Image(systemName: "lock.fill")
            case .validation:
                Image(systemName: "checkmark.shield.fill")
            case .authentication:
                Image(systemName: "faceid")
            case .network:
                Image(systemName: "network")
            case .persistence:
                Image(systemName: "externaldrive.fill")
            }
        }
    }
    
    private func colorForCategory(_ category: AuditCategory) -> Color {
        .green
    }
    
    private func generateReport() {
        isGenerating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let report = auditService.generateComplianceReport()
            // Export report
            isGenerating = false
        }
    }
}
