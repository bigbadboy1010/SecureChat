import SwiftUI
import UIKit

struct ProductionReadinessView: View {
    @ObservedObject var service: ConversationService

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PrivateChatHeroCard(
                    eyebrow: "Phase 14.3",
                    title: productionTitle,
                    subtitle: productionSubtitle,
                    systemImage: productionIcon,
                    tint: productionTint,
                    footer: SecureChatProductionProfile.relayBaseURLString
                )

                productionRelayPanel
                readinessGrid
                runtimePanel
                serverHardeningPanel
                clientSecurityPanel
                deploymentPanel
                appStorePanel
            }
            .padding(.horizontal)
            .padding(.vertical, 18)
            .frame(maxWidth: 940, alignment: .center)
            .frame(maxWidth: .infinity)
        }
        .background(PrivateChatDesign.pageGradient.ignoresSafeArea())
        .navigationTitle("Production")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        await service.checkRelayHealth()
                        await service.fetchRelayStats()
                        service.refreshSecurityAIAssessment()
                    }
                } label: {
                    if service.isRelayHealthCheckRunning || service.isRelayStatsRunning {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .accessibilityLabel("Production-Status prüfen")
            }
        }
    }

    private var productionRelayPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            PrivateChatSectionHeader("Production Relay", subtitle: "Aktuelle öffentliche SecureChat-URL und Token-Status.")

            VStack(spacing: 0) {
                ProductionChecklistRow(title: "Relay URL", value: activeRelayURLText, systemImage: "globe", tint: relayURLTint)
                Divider().opacity(0.45)
                ProductionChecklistRow(title: "Profil", value: isUsingChatSecureRelay ? "chatsecure.ddns.net aktiv" : "nicht übernommen", systemImage: "checkmark.shield", tint: isUsingChatSecureRelay ? .green : .orange)
                Divider().opacity(0.45)
                ProductionChecklistRow(title: "Token", value: hasRelayToken ? "RELAY_AUTH_TOKEN gesetzt" : "fehlt", systemImage: "key", tint: hasRelayToken ? .green : .orange)
                Divider().opacity(0.45)
                ProductionChecklistRow(title: "Health", value: service.lastRelayHealthMessage ?? "noch nicht geprüft", systemImage: "heart", tint: service.lastRelayHealthMessage == nil ? .secondary : .green)
            }
            .privateChatGlassCard(padding: 0, cornerRadius: 22)

            HStack(spacing: 12) {
                PrivateChatActionButton(title: "Production-URL übernehmen", systemImage: "globe", tint: .accentColor) {
                    applyProductionRelayProfile()
                }

                PrivateChatActionButton(title: "Prüfen", systemImage: "bolt.shield", tint: productionTint) {
                    applyProductionRelayProfile()
                    Task {
                        await service.checkRelayHealth()
                        await service.fetchRelayStats()
                        service.refreshSecurityAIAssessment()
                    }
                }
            }

            Button {
                UIPasteboard.general.string = SecureChatProductionProfile.relayBaseURLString
            } label: {
                Label("Production-URL kopieren", systemImage: "doc.on.doc")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Text("Token-Hinweis: In die App gehört ausschließlich RELAY_AUTH_TOKEN aus \(SecureChatProductionProfile.relayTokenLocationHint). RELAY_ADMIN_TOKEN bleibt nur serverseitig.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .privateChatGlassCard()
    }

    private var readinessGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            PrivateChatSectionHeader("Readiness Snapshot", subtitle: "Roter Status nur bei echten Production-Blockern.")
            LazyVGrid(columns: columns, spacing: 12) {
                PrivateChatStatusCard(title: "Relay", value: relayEnabled ? "aktiv" : "aus", systemImage: "antenna.radiowaves.left.and.right", footnote: "Transportmodus", tint: relayEnabled ? .green : .orange)
                PrivateChatStatusCard(title: "HTTPS", value: relayURLIsProductionReady ? "bereit" : "prüfen", systemImage: "lock.shield", footnote: relayURLReadinessText, tint: relayURLIsProductionReady ? .green : .orange)
                PrivateChatStatusCard(title: "Policy", value: hasRelayToken ? "Token" : "fehlt", systemImage: "key.horizontal", footnote: "/v1/relay/* geschützt", tint: hasRelayToken ? .green : .orange)
                PrivateChatStatusCard(title: "Runtime", value: service.runtimeSecuritySnapshot.riskLevel.localizedTitle, systemImage: "lock", footnote: runtimeFootnote, tint: runtimeTint)
            }
        }
    }

    private var runtimePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            PrivateChatSectionHeader("Runtime Integrity", subtitle: service.runtimeSecuritySnapshot.isDevelopmentRuntime ? "Xcode-/Debug-Signale werden als Development klassifiziert." : "Production-like Runtime ohne Debugger erwartet.")
            VStack(spacing: 0) {
                ProductionChecklistRow(title: "Modus", value: runtimeModeText, systemImage: "hammer", tint: service.runtimeSecuritySnapshot.isDevelopmentRuntime ? .accentColor : .green)
                Divider().opacity(0.45)
                ProductionChecklistRow(title: "Debugger", value: service.runtimeSecuritySnapshot.isDebuggerAttached ? "erkannt" : "nein", systemImage: "ladybug", tint: service.runtimeSecuritySnapshot.isDebuggerAttached ? (service.runtimeSecuritySnapshot.isDevelopmentRuntime ? .accentColor : .red) : .green)
                Divider().opacity(0.45)
                ProductionChecklistRow(title: "Jailbreak", value: "\(service.runtimeSecuritySnapshot.jailbreakSignals.count) Signal(e)", systemImage: "iphone", tint: service.runtimeSecuritySnapshot.jailbreakSignals.isEmpty ? .green : .red)
                Divider().opacity(0.45)
                ProductionChecklistRow(title: "Relay-Block", value: service.securityState.restrictRelayOnRuntimeRisk ? "aktiv" : "optional aus", systemImage: "shield", tint: service.securityState.restrictRelayOnRuntimeRisk ? .green : .orange)
            }
            .privateChatGlassCard(padding: 0, cornerRadius: 22)
        }
        .privateChatGlassCard()
    }

    private var serverHardeningPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            PrivateChatSectionHeader("Server Hardening", subtitle: "Erwarteter Stand auf dem Lenovo/Caddy-Deployment.")
            VStack(spacing: 0) {
                ProductionChecklistRow(title: "Container", value: "securechat", systemImage: "archivebox", tint: .green)
                Divider().opacity(0.45)
                ProductionChecklistRow(title: "Caddy", value: "chatsecure.ddns.net → securechat:8080", systemImage: "network", tint: .green)
                Divider().opacity(0.45)
                ProductionChecklistRow(title: "Store", value: "STORE_TYPE=file", systemImage: "externaldrive", tint: .green)
                Divider().opacity(0.45)
                ProductionChecklistRow(title: "Admin", value: "RELAY_ADMIN_TOKEN getrennt", systemImage: "key", tint: .green)
                Divider().opacity(0.45)
                ProductionChecklistRow(title: "Purge", value: "Admin-only / clientseitig geschützt", systemImage: "trash.slash", tint: .green)
            }
            .privateChatGlassCard(padding: 0, cornerRadius: 22)
        }
        .privateChatGlassCard()
    }

    private var clientSecurityPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            PrivateChatSectionHeader("Client Security", subtitle: "Lokale App-Härtung und Privacy-Defaults.")
            LazyVGrid(columns: columns, spacing: 12) {
                PrivateChatStatusCard(title: "Biometrie", value: service.securityState.requireBiometricUnlock ? "aktiv" : "aus", systemImage: "faceid", footnote: "Unlock-Gate", tint: service.securityState.requireBiometricUnlock ? .green : .orange)
                PrivateChatStatusCard(title: "Previews", value: service.securityState.hideMessagePreviews ? "verborgen" : "sichtbar", systemImage: "eye.slash", footnote: "Listenansicht", tint: service.securityState.hideMessagePreviews ? .green : .secondary)
                PrivateChatStatusCard(title: "Keyboard", value: service.securityState.reduceKeyboardSuggestions ? "reduziert" : "normal", systemImage: "keyboard", footnote: "Composer", tint: service.securityState.reduceKeyboardSuggestions ? .green : .secondary)
                PrivateChatStatusCard(title: "Retention", value: "\(service.securityState.localMessageRetentionDays)d", systemImage: "calendar.badge.clock", footnote: "lokale Daten", tint: service.securityState.localMessageRetentionDays <= 90 ? .green : .orange)
            }
        }
    }

    private var deploymentPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            PrivateChatSectionHeader("Deployment Commands", subtitle: "Referenz für schnelle Nachprüfung ohne Secrets auszugeben.")
            commandBlock("curl -i https://chatsecure.ddns.net/health")
            commandBlock("curl -i https://chatsecure.ddns.net/v1/relay/security/policy")
            commandBlock("curl -i https://chatsecure.ddns.net/v1/relay/security/policy -H 'Authorization: Bearer <RELAY_AUTH_TOKEN>'")
        }
        .privateChatGlassCard()
    }

    private var appStorePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            PrivateChatSectionHeader("App Store Readiness", subtitle: "Produktionsrelevante Hinweise ohne Chat-Klartexte.")
            VStack(spacing: 0) {
                ProductionChecklistRow(title: "Tracking", value: "keine Tracking-SDKs", systemImage: "hand.raised", tint: .green)
                Divider().opacity(0.45)
                ProductionChecklistRow(title: "QR Pairing", value: "Camera Usage bleibt notwendig", systemImage: "qrcode.viewfinder", tint: .accentColor)
                Divider().opacity(0.45)
                ProductionChecklistRow(title: "LAN Relay", value: "Local Network Usage bleibt für Tests", systemImage: "network", tint: .accentColor)
                Divider().opacity(0.45)
                ProductionChecklistRow(title: "Diagnose", value: "keine Chat-Texte", systemImage: "doc.text.magnifyingglass", tint: .green)
            }
            .privateChatGlassCard(padding: 0, cornerRadius: 22)
        }
        .privateChatGlassCard()
    }

    private var relayEnabled: Bool {
        service.securityState.transportMode == .relayAllowed && service.securityState.relayConfiguration.isEnabled
    }

    private var activeRelayURLText: String {
        let value = service.securityState.relayConfiguration.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "fehlt" : value
    }

    private var hasRelayToken: Bool {
        service.securityState.relayConfiguration.registrationToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var isUsingChatSecureRelay: Bool {
        SecureChatProductionProfile.isConfiguredProductionRelay(service.securityState.relayConfiguration.baseURLString)
    }

    private var relayURLReadinessText: String {
        let value = service.securityState.relayConfiguration.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return "URL fehlt" }
        if isUsingChatSecureRelay { return "chatsecure.ddns.net" }
        if SecureChatProductionProfile.isLocalOrPrivateRelay(value) { return "LAN/Test" }
        if SecureChatProductionProfile.isHTTPSProductionCandidate(value) { return "HTTPS extern" }
        return "nicht production-ready"
    }

    private var relayURLIsProductionReady: Bool {
        SecureChatProductionProfile.isHTTPSProductionCandidate(service.securityState.relayConfiguration.baseURLString)
    }

    private var relayURLTint: Color {
        if isUsingChatSecureRelay { return .green }
        let url = service.securityState.relayConfiguration.baseURLString
        if SecureChatProductionProfile.isHTTPSProductionCandidate(url) { return .accentColor }
        if SecureChatProductionProfile.isLocalOrPrivateRelay(url) || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .secondary }
        return .orange
    }

    private var productionTitle: String {
        if relayEnabled && isUsingChatSecureRelay && hasRelayToken {
            return "SecureChat Production ist verbunden"
        }
        return "SecureChat Production vorbereiten"
    }

    private var productionSubtitle: String {
        if relayEnabled && isUsingChatSecureRelay && hasRelayToken {
            return "Die App nutzt die öffentliche HTTPS-Relay-URL chatsecure.ddns.net. Der nächste Schritt ist der App-Test mit zwei Geräten."
        }
        return "Nutze das Production-Profil für chatsecure.ddns.net und trage nur RELAY_AUTH_TOKEN ein. RELAY_ADMIN_TOKEN bleibt auf dem Server."
    }

    private var productionIcon: String {
        relayEnabled && isUsingChatSecureRelay && hasRelayToken ? "checkmark.seal" : "shield"
    }

    private var productionTint: Color {
        relayEnabled && isUsingChatSecureRelay && hasRelayToken ? .green : .accentColor
    }

    private var runtimeTint: Color {
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

    private var runtimeFootnote: String {
        service.runtimeSecuritySnapshot.isDevelopmentRuntime ? "Xcode/Test" : "Release erwartet"
    }

    private var runtimeModeText: String {
        var parts: [String] = []
        if service.runtimeSecuritySnapshot.isSimulator { parts.append("Simulator") }
        if service.runtimeSecuritySnapshot.isMacRuntime { parts.append("Mac Runtime") }
        if service.runtimeSecuritySnapshot.isDebugBuild { parts.append("Debug") }
        return parts.isEmpty ? "Production-like" : parts.joined(separator: " · ")
    }

    private func applyProductionRelayProfile() {
        var state = service.securityState
        let currentConfiguration = state.relayConfiguration
        state.transportMode = .relayAllowed
        state.relayConfiguration = RelayConfiguration(
            isEnabled: true,
            baseURLString: SecureChatProductionProfile.relayBaseURLString,
            registrationToken: currentConfiguration.registrationToken,
            inboxPollingLimit: currentConfiguration.inboxPollingLimit,
            autoPollingIntervalSeconds: currentConfiguration.autoPollingIntervalSeconds,
            retryFailedMessagesAutomatically: currentConfiguration.retryFailedMessagesAutomatically,
            autoPurgeRelayInboxAfterSuccessfulSync: currentConfiguration.autoPurgeRelayInboxAfterSuccessfulSync,
            verboseRelayLogging: currentConfiguration.verboseRelayLogging
        )
        service.updateSecurityState(state)
    }

    private func commandBlock(_ command: String) -> some View {
        Text(command)
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ProductionChecklistRow: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: Circle())

            Text(title)
                .font(.subheadline.weight(.semibold))

            Spacer(minLength: 12)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(14)
    }
}
