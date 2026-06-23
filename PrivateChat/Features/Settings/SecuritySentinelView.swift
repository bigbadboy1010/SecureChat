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
            return "Bewertet Runtime, securechat.team, Token-Status, Privacy, Outbox, Trust-Status und lokale Sicherheitsindikatoren."
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
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                        if let v2Badge = v2Badge {
                            Text(v2Badge)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.green, in: Capsule())
                        }
                        Spacer(minLength: 0)
                    }
                    Text(finding.title)
                        .font(.headline.weight(.semibold))
                    Text(finding.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Sprint 12-1: expandable
            // "Was heißt das?" disclosure so the
            // user can drill into the meaning of
            // a v1 / v2 envelope finding without
            // leaving the Sentinel screen.
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "info.circle")
                        .font(.caption.weight(.semibold))
                    Text(isExpanded ? "Weniger" : "Was heißt das?")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(severityColor)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Empfehlung")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(severityColor)
                    Text(finding.recommendation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let explanation = v2Explanation {
                        Text(explanation.headline)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ForEach(explanation.lines, id: \.self) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text(line)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(severityColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14)
    }

    /// Short badge label for v2-envelope
    /// findings (Sprint 12-1). v1 findings
    /// stay unbadged so the visual contrast
    /// matches the warning severity.
    private var v2Badge: String? {
        guard finding.title.contains("v2") else { return nil }
        return "v2"
    }

    /// Longer "was heißt das" copy for
    /// v1 / v2 envelope findings so the
    /// user understands the difference
    /// without leaving the app.
    private var v2Explanation: (headline: String, lines: [String])? {
        if finding.title.contains("v2") {
            return (
                headline: "Was ist der v2-Envelope?",
                lines: [
                    "X3DH-Initial-Bundle leitet einen geteilten 32-Byte Root-Key ab.",
                    "Double Ratchet rotiert die Chain-Keys pro Nachricht (Forward Secrecy).",
                    "Selbst bei kompromittiertem Langzeit-Key heilt die Ratchet innerhalb weniger Messages (Post-Compromise Security).",
                    "Identitäts-Commitment läuft über die v1-Envelope-Signatur (Sprint 7)."
                ]
            )
        }
        if finding.title.contains("v1") {
            return (
                headline: "Was ist der v1-Envelope?",
                lines: [
                    "Curve25519-ECDH + AES-GCM (ADR-002) — kein Forward Secrecy pro Nachricht.",
                    "Wird durch das automatische Pairing-Opt-in seit Sprint 10 für neue Konversationen durch v2 ersetzt.",
                    "Bestehende v1-Sitzungen bleiben lesbar; ein Re-Pairing aktiviert v2."
                ]
            )
        }
        return nil
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
