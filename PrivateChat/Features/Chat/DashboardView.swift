import SwiftUI

struct DashboardView: View {
    @ObservedObject var service: ConversationService

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    testFlightGuidancePanel
                    healthGrid
                    relayPanel
                    activityPanel
                    securitySentinelPanel
                    securityPanel
                    quickActions
                }
                .padding()
            }
            .background(SecureChatDesign.pageGradient.ignoresSafeArea())
            .navigationTitle("Status-Center")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await service.checkRelayHealth()
                            await service.fetchRelayStats()
                            await service.syncRelayInbox()
                            service.refreshSecurityAIAssessment()
                        }
                    } label: {
                        if service.isRelayHealthCheckRunning || service.isRelayStatsRunning || service.isRelaySyncRunning {
                            ProgressView()
                        } else {
                            Image(systemName: "bolt.shield")
                        }
                    }
                    .accessibilityLabel("Sicherheitsstatus aktualisieren")
                }
            }
            .refreshable {
                await service.checkRelayHealth()
                await service.fetchRelayStats()
                await service.syncRelayInbox()
                service.refreshSecurityAIAssessment()
            }
            .privateChatErrorAlert(service: service)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            SecureChatHeroCard(
                eyebrow: "Secure Operations",
                title: commandCenterTitle,
                subtitle: commandCenterSubtitle,
                systemImage: isUsingProductionRelay ? "checkmark.seal.fill" : (service.securityState.transportMode == .relayAllowed ? "shield.fill" : "lock"),
                tint: isUsingProductionRelay ? SecureChatDesign.success : (service.securityState.transportMode == .relayAllowed ? SecureChatDesign.success : SecureChatDesign.warning),
                footer: shortIdentity
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if isUsingProductionRelay {
                        SecureChatStatusPill(title: "Production Relay", systemImage: "globe", tint: SecureChatDesign.success)
                    }
                    SecureChatStatusPill(title: service.isRelayAutoPollingActive ? "Auto-Sync aktiv" : "Auto-Sync bereit", systemImage: "arrow.triangle.2.circlepath", tint: service.isRelayAutoPollingActive ? SecureChatDesign.success : SecureChatDesign.textTertiary)
                    SecureChatStatusPill(title: service.runtimeSecuritySnapshot.riskLevel.localizedTitle, systemImage: "lock.shield", tint: runtimeTint)
                    SecureChatStatusPill(title: service.securityAISnapshot.riskLevel.localizedTitle, systemImage: "brain.head.profile", tint: securityAITint)
                    if service.securityState.hideMessagePreviews {
                        SecureChatStatusPill(title: "Privacy", systemImage: "eye.slash", tint: SecureChatDesign.success)
                    }
                }
            }
        }
        .privateChatGlassCard(padding: 16)
    }

    private var testFlightGuidancePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            PrivateChatSectionHeader("TestFlight Einstieg", subtitle: service.conversations.isEmpty ? "Erste Schritte für Solo-Tests" : "Schnellstart bleibt verfügbar")

            VStack(alignment: .leading, spacing: 8) {
                Label("Pairing benötigt zwei Geräte oder zwei Installationen.", systemImage: "qrcode")
                Label("Der Solo-Test-Chat prüft lokale Speicherung, Composer und Chat-UI ohne Relay.", systemImage: "lock.doc")
                Label("Production Relay: securechat.team plus RELAY_AUTH_TOKEN.", systemImage: "globe")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            HStack {
                Button {
                    _ = service.createSoloTestConversation()
                } label: {
                    Label("Solo-Test-Chat anlegen", systemImage: "plus.message")
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                ShareLink(item: service.appDiagnosticsReport()) {
                    Label("Diagnose teilen", systemImage: "square.and.arrow.up")
                }
            }
        }
        .privateChatGlassCard(padding: 16)
    }

    private var healthGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            PrivateChatStatusCard(title: "Chats", value: "\(service.activeConversationCount())", systemImage: "message", footnote: "\(service.archivedConversationCount()) archiviert")
            PrivateChatStatusCard(title: "Ungelesen", value: "\(service.totalUnreadCount())", systemImage: "bell.badge", footnote: "lokal gezählt", tint: service.totalUnreadCount() == 0 ? Color.green : Color.orange)
            PrivateChatStatusCard(title: "Outbox", value: "\(service.pendingOutboxCount())", systemImage: "tray.and.arrow.up", footnote: "queued/failed", tint: service.pendingOutboxCount() == 0 ? Color.green : Color.orange)
            PrivateChatStatusCard(title: "Markiert", value: "\(service.starredMessageCount())", systemImage: "star", footnote: "wichtige Nachrichten", tint: Color.orange)
            PrivateChatStatusCard(title: "Verifiziert", value: "\(service.verifiedPeerCount())", systemImage: "checkmark.seal", footnote: "\(service.blockedPeerCount()) blockiert", tint: Color.green)
            PrivateChatStatusCard(title: "Stumm", value: "\(service.mutedConversationCount())", systemImage: "bell.slash", footnote: "Chats ohne Badge-Druck", tint: Color.secondary)
        }
    }

    private var relayPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            PrivateChatSectionHeader("Relay", subtitle: relaySubtitle)

            HStack(spacing: 12) {
                PrivateChatStatusCard(title: "Pakete", value: relayStoredPackets, systemImage: "archivebox", footnote: "serverseitig")
                PrivateChatStatusCard(title: "ACKs", value: relayTombstones, systemImage: "checkmark.seal", footnote: "Tombstones")
            }

            if let summary = service.lastRelaySyncSummary {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Letzter Sync: \(summary.processedCount) verarbeitet, \(summary.duplicateCount) Duplikate, \(summary.deletedCount) ACKs", systemImage: "waveform.path.ecg")
                    Label("Receipts: \(summary.deliveryReceiptSentCount), ACK-Fehler: \(summary.acknowledgementFailureCount)", systemImage: "paperplane.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .privateChatGlassCard(padding: 16)
    }

    private var activityPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            PrivateChatSectionHeader("Aktivität", subtitle: "Lokale Qualitätsindikatoren")

            VStack(alignment: .leading, spacing: 8) {
                ReadinessRow(title: "Relay-Kette", value: service.securityState.transportMode == .relayAllowed ? "aktiv" : "lokal", systemImage: "antenna.radiowaves.left.and.right", tint: service.securityState.transportMode == .relayAllowed ? Color.green : Color.orange)
                ReadinessRow(title: "Relay-Verbindung", value: relayConnectivityText, systemImage: relayConnectivityIcon, tint: relayConnectivityTint)
                ReadinessRow(title: "Fehlgeschlagene Nachrichten", value: "\(service.failedMessageCount())", systemImage: "exclamationmark.triangle", tint: service.failedMessageCount() == 0 ? Color.green : Color.red)
                ReadinessRow(title: "Auto-Polling", value: service.isRelayAutoPollingActive ? "läuft" : "bereit", systemImage: "arrow.triangle.2.circlepath", tint: service.isRelayAutoPollingActive ? Color.green : Color.secondary)
                ReadinessRow(title: "Retention", value: "\(service.securityState.localMessageRetentionDays) Tage", systemImage: "calendar.badge.clock", tint: Color.accentColor)
                ReadinessRow(title: "Vorschau-Schutz", value: service.securityState.hideMessagePreviews ? "aktiv" : "aus", systemImage: service.securityState.hideMessagePreviews ? "eye.slash" : "eye", tint: service.securityState.hideMessagePreviews ? Color.green : Color.secondary)
                ReadinessRow(title: "Keyboard-Schutz", value: service.securityState.reduceKeyboardSuggestions ? "reduziert" : "normal", systemImage: "keyboard", tint: service.securityState.reduceKeyboardSuggestions ? Color.green : Color.secondary)
                ReadinessRow(title: "Runtime", value: service.runtimeSecuritySnapshot.riskLevel.localizedTitle, systemImage: "lock.shield", tint: runtimeTint)
            }
        }
        .privateChatGlassCard(padding: 16)
    }

    private var securitySentinelPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            PrivateChatSectionHeader("Security Sentinel", subtitle: service.securityAISnapshot.summary)

            HStack(spacing: 12) {
                PrivateChatStatusCard(
                    title: "Score",
                    value: "\(service.securityAISnapshot.score)",
                    systemImage: "brain.head.profile",
                    footnote: service.securityAISnapshot.riskLevel.localizedTitle,
                    tint: securityAITint
                )
                PrivateChatStatusCard(
                    title: "Findings",
                    value: "\(service.securityAISnapshot.findings.count)",
                    systemImage: "checklist",
                    footnote: "lokal bewertet",
                    tint: service.securityAISnapshot.findings.isEmpty ? Color.green : Color.orange
                )
            }

            if let topFinding = service.securityAISnapshot.topFindings.first {
                Label(topFinding.title, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(securityAITint)
            }
        }
        .privateChatGlassCard(padding: 16)
    }

    private var securityPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            PrivateChatSectionHeader("Security Baseline", subtitle: "Status der lokalen Härtung")
            Label("Nachrichtenstore: AES-GCM + Keychain-Key", systemImage: "lock.doc")
            Label("Pairing: QR/Code + Safety Number", systemImage: "qrcode.viewfinder")
            Label("Transportpakete: Signatur + AEAD", systemImage: "signature")
            Label("Delivery-Status: sentToRelay → delivered", systemImage: "checkmark.seal")
            Label("Runtime-Härtung: Debugger/Jailbreak/Injection-Indikatoren", systemImage: "lock.shield")
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .privateChatGlassCard(padding: 16)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            PrivateChatSectionHeader("Schnellaktionen", subtitle: "Manuelle Steuerung für Sync, Outbox und Relay-Purge")
            HStack {
                Button {
                    Task { await service.syncRelayInbox() }
                } label: {
                    Label("Sync", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(service.isRelaySyncRunning || service.securityState.transportMode != .relayAllowed)

                Button {
                    Task { await service.retryPendingOutboundMessages() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(service.isOutboxRetryRunning || service.pendingOutboxCount() == 0)

                Button(role: .destructive) {
                    Task { await service.purgeRelayInbox() }
                } label: {
                    Label("Purge", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(service.isRelayPurgeRunning || service.securityState.transportMode != .relayAllowed)
            }
        }
        .privateChatGlassCard(padding: 16)
    }

    private var relayConnectivityText: String {
        if service.relayConnectivityStatus.isPaused {
            return "Pause \(service.relayConnectivityStatus.remainingPauseSeconds)s"
        }
        return service.relayConnectivityStatus.localizedStateTitle
    }

    private var relayConnectivityIcon: String {
        switch service.relayConnectivityStatus.state {
        case .healthy:
            return "checkmark.circle"
        case .degraded:
            return "exclamationmark.triangle"
        case .paused:
            return service.relayConnectivityStatus.isPaused ? "pause.circle" : "play.circle"
        }
    }

    private var relayConnectivityTint: Color {
        switch service.relayConnectivityStatus.state {
        case .healthy:
            return Color.green
        case .degraded:
            return Color.orange
        case .paused:
            return service.relayConnectivityStatus.isPaused ? Color.orange : Color.green
        }
    }

    private var commandCenterTitle: String {
        isUsingProductionRelay ? "SecureChat Production ist bereit" : "PrivateChat ist einsatzbereit"
    }

    private var commandCenterSubtitle: String {
        if isUsingProductionRelay {
            return "E2E-Verschlüsselung, HTTPS-Relay securechat.team, Relay-Härtung und lokale Runtime-Überwachung in einer professionellen Konsole."
        }
        return "E2E-Verschlüsselung, Relay-Härtung und lokale Runtime-Überwachung in einer professionellen Konsole."
    }

    private var isUsingProductionRelay: Bool {
        SecureChatProductionProfile.isConfiguredProductionRelay(service.securityState.relayConfiguration.baseURLString)
            && service.securityState.transportMode == .relayAllowed
            && service.securityState.relayConfiguration.registrationToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var runtimeTint: Color {
        switch service.runtimeSecuritySnapshot.riskLevel {
        case .normal:
            return Color.green
        case .development:
            return Color.accentColor
        case .elevated:
            return Color.orange
        case .compromised:
            return Color.red
        }
    }

    private var securityAITint: Color {
        switch service.securityAISnapshot.riskLevel {
        case .optimal:
            return Color.green
        case .guarded:
            return Color.accentColor
        case .elevated:
            return Color.orange
        case .critical:
            return Color.red
        }
    }

    private var shortIdentity: String {
        "ID " + String(service.localIdentity.id.prefix(12)) + "…"
    }

    private var relaySubtitle: String {
        switch service.securityState.transportMode {
        case .localOnly:
            return "Nur lokaler Modus aktiv"
        case .relayAllowed:
            let url = service.securityState.relayConfiguration.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            return url.isEmpty ? "Relay-URL fehlt" : url
        }
    }

    private var relayStoredPackets: String {
        service.lastRelayStatsSnapshot.map { "\($0.storedPackets)" } ?? "–"
    }

    private var relayTombstones: String {
        service.lastRelayStatsSnapshot.map { "\($0.acknowledgedPacketTombstones)" } ?? "–"
    }
}


private struct ReadinessRow: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondary)
        }
    }
}
