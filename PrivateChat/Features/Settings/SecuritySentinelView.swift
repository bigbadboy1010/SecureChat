import SwiftUI

struct SecuritySentinelView: View {
    @ObservedObject var service: ConversationService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PrivateChatHeroCard(
                    eyebrow: "Phase 12",
                    title: "Lokaler Security Sentinel",
                    subtitle: service.securityAISnapshot.summary,
                    systemImage: riskIcon,
                    tint: riskColor,
                    footer: "Keine Klartexte · kein externer KI-Dienst · lokales Risk-Scoring"
                )

                HStack(alignment: .center, spacing: 18) {
                    ZStack {
                        Circle()
                            .stroke(riskColor.opacity(0.18), lineWidth: 14)
                        Circle()
                            .trim(from: 0, to: CGFloat(service.securityAISnapshot.score) / 100)
                            .stroke(riskColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 2) {
                            Text("\(service.securityAISnapshot.score)")
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                            Text("/100")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 132, height: 132)

                    VStack(alignment: .leading, spacing: 10) {
                        PrivateChatStatusPill(title: service.securityAISnapshot.riskLevel.localizedTitle, systemImage: riskIcon, tint: riskColor)
                        Text(sentinalExplanation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            service.refreshRuntimeSecurityAssessment()
                            service.refreshSecurityAIAssessment()
                        } label: {
                            Label("Security Sentinel neu bewerten", systemImage: "brain.head.profile")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(riskColor)
                    }
                    Spacer(minLength: 0)
                }
                .privateChatGlassCard()

                findingGroupsSection

                VStack(alignment: .leading, spacing: 12) {
                    PrivateChatSectionHeader("Grenzen & Roadmap", subtitle: "Der Sentinel ist ein lokaler Sicherheits-Assistent, kein Ersatz für geprüfte Kryptografie.")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        PrivateChatStatusCard(title: "Datenfluss", value: "lokal", systemImage: "wifi.slash", footnote: "keine externen KI-Dienste", tint: .green)
                        PrivateChatStatusCard(title: "Klartexte", value: "ausgeschlossen", systemImage: "lock.doc", footnote: "keine Chat-Inhalte", tint: .green)
                        PrivateChatStatusCard(title: "Scoring", value: "regelbasiert", systemImage: "slider.horizontal.3", footnote: "später CoreML möglich", tint: .accentColor)
                        PrivateChatStatusCard(title: "Crypto", value: "agil", systemImage: "lock.shield", footnote: "PQC-Hybrid später", tint: .accentColor)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 18)
            .frame(maxWidth: 980, alignment: .center)
            .frame(maxWidth: .infinity)
        }
        .background(PrivateChatDesign.pageGradient.ignoresSafeArea())
        .navigationTitle("Security Sentinel")
    }

    private var findingGroupsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PrivateChatSectionHeader("Findings", subtitle: "Production-Risiken, empfohlene Maßnahmen und Development-Hinweise getrennt dargestellt.")

            if criticalFindings.isEmpty && actionFindings.isEmpty && infoFindings.isEmpty {
                Text("Keine Findings vorhanden.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .privateChatGlassCard()
            } else {
                if criticalFindings.isEmpty == false {
                    findingGroupCard(title: "Production-Risiken", subtitle: "Vor Release beheben", findings: criticalFindings, tint: .red)
                }
                if actionFindings.isEmpty == false {
                    findingGroupCard(title: "Empfohlene Maßnahmen", subtitle: "Security-Hygiene und Betrieb", findings: actionFindings, tint: .orange)
                }
                if infoFindings.isEmpty == false {
                    findingGroupCard(title: "Development & Info", subtitle: "Erwartete Hinweise im Xcode-/Testbetrieb", findings: infoFindings, tint: .accentColor)
                }
            }
        }
    }

    private func findingGroupCard(title: String, subtitle: String, findings: [SecurityAIFinding], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(findings.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(tint.opacity(0.11), in: Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            VStack(spacing: 0) {
                ForEach(findings) { finding in
                    SecurityFindingRow(finding: finding)
                    if finding.id != findings.last?.id {
                        Divider().opacity(0.45)
                    }
                }
            }
        }
        .privateChatGlassCard(padding: 0, cornerRadius: 22)
    }

    private var criticalFindings: [SecurityAIFinding] {
        service.securityAISnapshot.topFindings.filter { $0.severity == .critical || $0.severity == .high }
    }

    private var actionFindings: [SecurityAIFinding] {
        service.securityAISnapshot.topFindings.filter { $0.severity == .warning }
    }

    private var infoFindings: [SecurityAIFinding] {
        service.securityAISnapshot.topFindings.filter { $0.severity == .info }
    }

    private var sentinalExplanation: String {
        if service.runtimeSecuritySnapshot.isDevelopmentRuntime {
            return "Development-Modus erkannt. Xcode/Debug-Hinweise werden nicht als echte Production-Kompromittierung gewertet. Für Production-Score: Release/TestFlight auf physischem iPhone testen."
        }
        if SecureChatProductionProfile.isConfiguredProductionRelay(service.securityState.relayConfiguration.baseURLString) {
            return "Bewertet Runtime, chatsecure.ddns.net, Token-Status, Privacy, Outbox, Trust-Status und lokale Sicherheitsindikatoren."
        }
        return "Bewertet Runtime, Relay-Konfiguration, Privacy, Outbox, Trust-Status und lokale Sicherheitsindikatoren."
    }

    private var riskIcon: String {
        switch service.securityAISnapshot.riskLevel {
        case .optimal:
            return "checkmark.seal"
        case .guarded:
            return "shield"
        case .elevated:
            return "exclamationmark.triangle"
        case .critical:
            return "xmark.octagon"
        }
    }

    private var riskColor: Color {
        switch service.securityAISnapshot.riskLevel {
        case .optimal:
            return .green
        case .guarded:
            return .accentColor
        case .elevated:
            return .orange
        case .critical:
            return .red
        }
    }
}

private struct SecurityFindingRow: View {
    let finding: SecurityAIFinding

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: severityIcon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(severityColor)
                .frame(width: 28, height: 28)
                .background(severityColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(finding.severity.localizedTitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(severityColor)
                    Spacer(minLength: 0)
                }
                Text(finding.title)
                    .font(.headline.weight(.semibold))
                Text(finding.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Empfehlung: \(finding.recommendation)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
    }

    private var severityIcon: String {
        switch finding.severity {
        case .info:
            return "info.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .high:
            return "exclamationmark.shield"
        case .critical:
            return "xmark.octagon"
        }
    }

    private var severityColor: Color {
        switch finding.severity {
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .high:
            return .red
        case .critical:
            return .red
        }
    }
}
