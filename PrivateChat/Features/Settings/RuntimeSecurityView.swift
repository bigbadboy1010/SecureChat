import SwiftUI
import UIKit

struct RuntimeSecurityView: View {
    @ObservedObject var service: ConversationService

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PrivateChatHeroCard(
                    eyebrow: "Phase 11",
                    title: "App Hardening & Runtime Integrity",
                    subtitle: heroSubtitle,
                    systemImage: riskIcon,
                    tint: riskColor,
                    footer: "Bewertung: \(service.runtimeSecuritySnapshot.riskLevel.localizedTitle)"
                )

                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    PrivateChatStatusCard(title: "Runtime", value: service.runtimeSecuritySnapshot.localizedSummary, systemImage: "lock.shield", footnote: runtimeModeText, tint: riskColor)
                    PrivateChatStatusCard(title: "Debugger", value: service.runtimeSecuritySnapshot.isDebuggerAttached ? "erkannt" : "nein", systemImage: "ladybug", footnote: debuggerFootnote, tint: service.runtimeSecuritySnapshot.isDebuggerAttached ? Color.orange : Color.green)
                    PrivateChatStatusCard(title: "Jailbreak", value: "\(service.runtimeSecuritySnapshot.jailbreakSignals.count) Signal(e)", systemImage: "iphone", footnote: jailbreakFootnote, tint: service.runtimeSecuritySnapshot.jailbreakSignals.isEmpty ? Color.green : Color.red)
                    PrivateChatStatusCard(title: "DYLD", value: service.runtimeSecuritySnapshot.hasInjectedDynamicLibraries ? "Hinweis" : "nein", systemImage: "puzzlepiece", footnote: dyldFootnote, tint: service.runtimeSecuritySnapshot.hasInjectedDynamicLibraries ? Color.orange : Color.green)
                }

                VStack(alignment: .leading, spacing: 12) {
                    PrivateChatSectionHeader("Findings", subtitle: "Entwicklungsmodus wird separat bewertet. Debugger/Xcode sind im Test nicht automatisch kompromittiert.")
                    VStack(spacing: 0) {
                        ForEach(service.runtimeSecuritySnapshot.findings) { finding in
                            RuntimeFindingRow(finding: finding)
                            if finding.id != service.runtimeSecuritySnapshot.findings.last?.id {
                                Divider().opacity(0.45)
                            }
                        }
                    }
                    .privateChatGlassCard(padding: 0, cornerRadius: 22)
                }

                VStack(alignment: .leading, spacing: 14) {
                    PrivateChatSectionHeader("Policy", subtitle: "Für Production scharf, für Xcode-/Mac-Tests nachvollziehbar.")

                    Toggle("Runtime-Warnungen anzeigen", isOn: runtimeWarningBinding)
                    Toggle("Relay bei kritischem Production-Runtime-Risiko blockieren", isOn: runtimeRelayBlockBinding)

                    HStack(spacing: 12) {
                        PrivateChatActionButton(title: "Neu prüfen", systemImage: "arrow.clockwise", tint: .accentColor) {
                            service.refreshRuntimeSecurityAssessment()
                        }

                        ShareLink(item: service.appDiagnosticsReport()) {
                            Label("Diagnose teilen", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        UIPasteboard.general.string = service.appDiagnosticsReport()
                    } label: {
                        Label("Diagnosebericht kopieren", systemImage: "doc.on.doc")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Text("Der Relay-Block greift nur bei kritischen Signalen in produktionsähnlicher Runtime. Debugger/Debug-Builds in Xcode werden als Development klassifiziert.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .privateChatGlassCard()
            }
            .padding(.horizontal)
            .padding(.vertical, 18)
            .frame(maxWidth: 980, alignment: .center)
            .frame(maxWidth: .infinity)
        }
        .background(PrivateChatDesign.pageGradient.ignoresSafeArea())
        .navigationTitle("App Hardening")
        .onAppear {
            service.refreshRuntimeSecurityAssessment()
        }
    }

    private var heroSubtitle: String {
        if service.runtimeSecuritySnapshot.isDevelopmentRuntime {
            return "Development-/Testmodus erkannt. Das ist bei Xcode normal. Für echte Bewertung einen Release/TestFlight-Build auf echter iPhone-Hardware verwenden."
        }
        return "Prüft Debugger, Jailbreak-Indikatoren und Dynamic-Library-Injection ohne Nachrichteninhalte zu analysieren."
    }

    private var runtimeModeText: String {
        var parts: [String] = []
        if service.runtimeSecuritySnapshot.isSimulator { parts.append("Simulator") }
        if service.runtimeSecuritySnapshot.isMacRuntime { parts.append("Mac Runtime") }
        if service.runtimeSecuritySnapshot.isDebugBuild { parts.append("Debug") }
        return parts.isEmpty ? "Production-like" : parts.joined(separator: " · ")
    }

    private var debuggerFootnote: String {
        service.runtimeSecuritySnapshot.isDevelopmentRuntime ? "bei Xcode erwartbar" : "in Production kritisch"
    }

    private var jailbreakFootnote: String {
        service.runtimeSecuritySnapshot.isDevelopmentRuntime ? "in Dev/Mac nicht gewertet" : "nur echte iOS-Hardware"
    }

    private var dyldFootnote: String {
        service.runtimeSecuritySnapshot.isDevelopmentRuntime ? "Dev-Hinweis" : "Production prüfen"
    }

    private var riskIcon: String {
        switch service.runtimeSecuritySnapshot.riskLevel {
        case .normal:
            return "checkmark.shield"
        case .development:
            return "hammer"
        case .elevated:
            return "exclamationmark.triangle"
        case .compromised:
            return "xmark.shield"
        }
    }

    private var riskColor: Color {
        switch service.runtimeSecuritySnapshot.riskLevel {
        case .normal:
            return .green
        case .development:
            return .accentColor
        case .elevated:
            return .orange
        case .compromised:
            return .red
        }
    }

    private var runtimeWarningBinding: Binding<Bool> {
        Binding(
            get: { service.securityState.warnOnRuntimeRisk },
            set: { newValue in
                var state = service.securityState
                state.warnOnRuntimeRisk = newValue
                service.updateSecurityState(state)
            }
        )
    }

    private var runtimeRelayBlockBinding: Binding<Bool> {
        Binding(
            get: { service.securityState.restrictRelayOnRuntimeRisk },
            set: { newValue in
                var state = service.securityState
                state.restrictRelayOnRuntimeRisk = newValue
                service.updateSecurityState(state)
            }
        )
    }
}

private struct RuntimeFindingRow: View {
    let finding: RuntimeSecurityFinding

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(finding.title)
                    .font(.subheadline.weight(.semibold))
                Text(finding.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private var icon: String {
        switch finding.severity {
        case .info:
            return "info.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .critical:
            return "xmark.octagon"
        }
    }

    private var color: Color {
        switch finding.severity {
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }
}
