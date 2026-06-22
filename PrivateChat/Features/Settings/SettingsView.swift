import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var service: ConversationService

    @State private var relayURL: String = ""
    @State private var relayToken: String = ""
    @State private var relayPollingLimit: Int = 50
    @State private var relayAutoPollingInterval: Int = 15
    @State private var retryFailedMessagesAutomatically: Bool = true
    @State private var verboseRelayLogging: Bool = false
    @State private var localMessageRetentionDays: Int = 30
    @State private var hideMessagePreviews: Bool = false
    @State private var reduceKeyboardSuggestions: Bool = true
    @State private var warnOnRuntimeRisk: Bool = true
    @State private var restrictRelayOnRuntimeRisk: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section {
                    LabeledContent("Status") {
                        Text("Production Candidate")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }

                    Label("Externer Security-Audit steht noch aus. Nicht für hochsensible Kommunikation in der Beta verwenden.", systemImage: "exclamationmark.shield")
                        .font(.footnote)
                        .foregroundStyle(.orange)

                    Button {
                        UserDefaults.standard.set(false, forKey: "PrivateChat.didOnboard.v1")
                        UserDefaults.standard.set(false, forKey: "PrivateChat.didAcceptBetaDisclaimer.v1")
                    } label: {
                        Label("Onboarding & Beta-Hinweis erneut anzeigen", systemImage: "arrow.counterclockwise")
                    }
                } header: {
                    Text("Beta & TestFlight")
                } footer: {
                    Text("Diese App ist technisch für TestFlight vorbereitet. Die Bezeichnung Production Candidate bedeutet: harte lokale Schutzmaßnahmen sind aktiv, aber externe Audits und Produkt-UX sind noch in Arbeit.")
                }

                SwiftUI.Section {
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label("Datenschutzerklärung", systemImage: "hand.raised")
                    }

                    NavigationLink {
                        SupportFeedbackView(service: service)
                    } label: {
                        Label("Support & Feedback", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                    }

                    NavigationLink {
                        TestFlightSubmissionView()
                    } label: {
                        Label("TestFlight Vorbereitung", systemImage: "testtube.2")
                    }

                    LabeledContent("Version") {
                        Text(appVersionString)
                            .font(.caption.monospaced())
                    }
                } header: {
                    Text("TestFlight & App Store Connect")
                } footer: {
                    Text("Privacy-Policy-URL und Support-URL müssen in App Store Connect als externe HTTPS-URLs hinterlegt werden. Die Inhalte sind hier vorbereitet und in Docs/ dokumentiert.")
                }

                SwiftUI.Section {
                    LabeledContent("Bundle") {
                        Text("org.francois.PrivateChat")
                    }

                    LabeledContent("App") {
                        Text("SecureChat")
                    }

                    LabeledContent("Identity") {
                        Text(shortIdentity)
                            .font(.caption.monospaced())
                    }

                    Toggle("Biometrische Entsperrung", isOn: biometricBinding)

                    Stepper("Lokale Nachrichten-Retention: \(localMessageRetentionDays) Tage", value: $localMessageRetentionDays, in: 1...365)

                    Button {
                        saveLocalRetention()
                        service.purgeExpiredLocalMessages()
                    } label: {
                        if service.isLocalRetentionPurgeRunning {
                            ProgressView()
                        } else {
                            Text("Lokale Retention bereinigen")
                        }
                    }
                    .disabled(service.isLocalRetentionPurgeRunning)

                    if let summary = service.lastLocalRetentionSummary {
                        LabeledContent("Retention-Bereinigung") {
                            Text("\(summary.deletedMessages) Nachrichten, \(summary.deletedConversations) Chats")
                        }
                    }
                } header: {
                    Text("Security Core")
                }

                SwiftUI.Section {
                    Toggle("Nachrichten-Vorschau in Listen verbergen", isOn: $hideMessagePreviews)
                    Toggle("Keyboard-Vorschläge im Composer reduzieren", isOn: $reduceKeyboardSuggestions)

                    Button("Privacy-Einstellungen speichern") {
                        savePrivacySettings()
                    }

                    ShareLink(item: service.appDiagnosticsReport()) {
                        Label("Diagnosebericht teilen", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        UIPasteboard.general.string = service.appDiagnosticsReport()
                    } label: {
                        Label("Diagnosebericht kopieren", systemImage: "doc.on.doc")
                    }
                } header: {
                    Text("Privacy & Diagnose")
                } footer: {
                    Text("Der Vorschau-Schutz blendet Nachrichteninhalte in Listen aus. Der Diagnosebericht enthält technische Metadaten, aber keine Nachrichteninhalte.")
                }

                SwiftUI.Section {
                    NavigationLink {
                        RuntimeSecurityView(service: service)
                    } label: {
                        Label("App Hardening & Runtime Integrity", systemImage: "lock.shield")
                    }

                    LabeledContent("Runtime") {
                        Text(service.runtimeSecuritySnapshot.localizedSummary)
                            .foregroundStyle(runtimeRiskColor)
                    }

                    LabeledContent("Risiko") {
                        Text(service.runtimeSecuritySnapshot.riskLevel.localizedTitle)
                            .foregroundStyle(runtimeRiskColor)
                    }

                    Toggle("Runtime-Warnungen anzeigen", isOn: $warnOnRuntimeRisk)
                    Toggle("Relay bei kritischem Runtime-Risiko blockieren", isOn: $restrictRelayOnRuntimeRisk)

                    HStack {
                        Button("Hardening speichern") {
                            saveRuntimeHardeningSettings()
                        }

                        Spacer()

                        Button {
                            service.refreshRuntimeSecurityAssessment()
                        } label: {
                            Label("Neu prüfen", systemImage: "arrow.clockwise")
                        }
                    }
                } header: {
                    Text("Phase 11 App Hardening")
                } footer: {
                    Text("Warnungen informieren über Debugger-, Jailbreak- und Injection-Indikatoren. Der optionale Relay-Block stoppt Netzwerktransport nur bei kritischen Laufzeitrisiken.")
                }

                SwiftUI.Section {
                    NavigationLink {
                        SecuritySentinelView(service: service)
                    } label: {
                        Label("Lokaler KI-Security-Sentinel", systemImage: "brain.head.profile")
                    }

                    LabeledContent("Sentinel Score") {
                        Text("\(service.securityAISnapshot.score)/100")
                            .foregroundStyle(securityAIColor)
                    }

                    LabeledContent("Sentinel Risiko") {
                        Text(service.securityAISnapshot.riskLevel.localizedTitle)
                            .foregroundStyle(securityAIColor)
                    }

                    Button {
                        service.refreshRuntimeSecurityAssessment()
                        service.refreshSecurityAIAssessment()
                    } label: {
                        Label("Security Sentinel neu bewerten", systemImage: "arrow.clockwise")
                    }
                } header: {
                    Text("Phase 12 Security Sentinel")
                } footer: {
                    Text("Lokale KI-/Heuristik-Bewertung ohne externe Übertragung. Der Sentinel analysiert Konfiguration, Runtime-Risiko, Relay-Zustand und lokale Qualitätsindikatoren, aber keine Nachrichtenklartexte.")
                }

                SwiftUI.Section {
                    Picker("Modus", selection: transportModeBinding) {
                        Text("Nur lokal").tag(TransportMode.localOnly)
                        Text("Relay erlaubt").tag(TransportMode.relayAllowed)
                    }
                    .pickerStyle(.segmented)

                    LabeledContent("Production-Profil") {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(SecureChatProductionProfile.relayBaseURLString)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Text(relayProfileStatusText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(relayProfileStatusColor)
                        }
                    }

                    HStack {
                        Button {
                            applyProductionRelayTemplate()
                        } label: {
                            Label("Production-URL übernehmen", systemImage: "globe")
                        }

                        Spacer()

                        Button {
                            applyProductionRelayTemplate()
                            saveRelayConfiguration()
                            Task { await service.checkRelayHealth() }
                        } label: {
                            Label("Übernehmen & prüfen", systemImage: "bolt.shield")
                        }
                        .disabled(service.isRelayHealthCheckRunning)
                    }

                    HStack {
                        Button {
                            activateProductionRelay()
                        } label: {
                            Label("Production Relay aktivieren", systemImage: "checkmark.shield")
                        }
                        .buttonStyle(.borderedProminent)

                        Spacer()

                        Button(role: .destructive) {
                            clearObsoleteLocalRelayConfiguration()
                        } label: {
                            Label("Lokale Relay-Altlast löschen", systemImage: "trash")
                        }
                        .disabled(SecureChatProductionProfile.isObsoleteLocalRelay(relayURL) == false && SecureChatProductionProfile.isLocalOrPrivateRelay(relayURL) == false)
                    }

                    TextField(SecureChatProductionProfile.relayBaseURLString, text: $relayURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled(true)

                    SecureField("RELAY_AUTH_TOKEN", text: $relayToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    LabeledContent("Token-Status") {
                        Text(relayTokenStatusText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(relayTokenStatusColor)
                    }

                    if SecureChatProductionProfile.isObsoleteLocalRelay(relayURL) {
                        Label("Alte lokale Relay-URL erkannt. Diese wird nicht mehr für Production verwendet.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Stepper("Inbox Limit: \(relayPollingLimit)", value: $relayPollingLimit, in: 1...100)
                    Stepper("Auto-Polling: \(relayAutoPollingInterval)s", value: $relayAutoPollingInterval, in: 5...300, step: 5)

                    Toggle("Fehlgeschlagene Nachrichten automatisch erneut senden", isOn: $retryFailedMessagesAutomatically)
                    Toggle("Relay-Erfolgslogs anzeigen", isOn: $verboseRelayLogging)

                    HStack {
                        Button("Relay speichern") {
                            saveRelayConfiguration()
                        }

                        Spacer()

                        Button {
                            saveRelayConfiguration()
                            Task { await service.checkRelayHealth() }
                        } label: {
                            if service.isRelayHealthCheckRunning {
                                ProgressView()
                            } else {
                                Text("Relay prüfen")
                            }
                        }
                        .disabled(service.isRelayHealthCheckRunning)
                    }

                    HStack {
                        Button {
                            Task { await service.syncRelayInbox() }
                        } label: {
                            if service.isRelaySyncRunning {
                                ProgressView()
                            } else {
                                Text("Inbox abrufen")
                            }
                        }
                        .disabled(service.isRelaySyncRunning || service.securityState.transportMode != .relayAllowed || service.securityState.relayConfiguration.isReadyForNetworkRequests == false)

                        Spacer()

                        Button {
                            Task { await service.retryPendingOutboundMessages() }
                        } label: {
                            if service.isOutboxRetryRunning {
                                ProgressView()
                            } else {
                                Text("Outbox erneut senden")
                            }
                        }
                        .disabled(service.isOutboxRetryRunning || service.pendingOutboxCount() == 0 || service.securityState.relayConfiguration.isReadyForNetworkRequests == false)
                    }

                    HStack {
                        Button {
                            Task { await service.fetchRelayStats() }
                        } label: {
                            if service.isRelayStatsRunning {
                                ProgressView()
                            } else {
                                Text("Relay Stats")
                            }
                        }
                        .disabled(service.isRelayStatsRunning || service.securityState.transportMode != .relayAllowed || service.securityState.relayConfiguration.isReadyForNetworkRequests == false)

                        Spacer()

                        Button(role: .destructive) {
                            Task { await service.purgeRelayInbox() }
                        } label: {
                            if service.isRelayPurgeRunning {
                                ProgressView()
                            } else {
                                Text("Inbox am Relay leeren")
                            }
                        }
                        .disabled(service.isRelayPurgeRunning || service.securityState.transportMode != .relayAllowed || service.securityState.relayConfiguration.isReadyForNetworkRequests == false)
                    }

                    if let stats = service.lastRelayStatsSnapshot {
                        LabeledContent("Relay Pakete") {
                            Text("\(stats.storedPackets)")
                        }
                        LabeledContent("Relay Empfänger") {
                            Text("\(stats.activeRecipients)")
                        }
                        LabeledContent("ACK Tombstones") {
                            Text("\(stats.acknowledgedPacketTombstones)")
                        }
                    }

                    if let purge = service.lastRelayPurgeSummary {
                        LabeledContent("Letzte Relay-Bereinigung") {
                            Text("\(purge.deletedCount) Pakete")
                        }
                    }

                    HStack {
                        Text(transportStatusText)
                            .font(.caption)
                            .foregroundStyle(transportStatusColor)

                        Spacer()

                        if service.isRelayAutoPollingActive {
                            Label("Auto-Polling aktiv", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Label("Auto-Polling bereit", systemImage: "pause.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    LabeledContent("Relay-Verbindung") {
                        HStack(spacing: 6) {
                            Image(systemName: relayConnectivityIcon)
                                .foregroundStyle(relayConnectivityColor)
                            Text(service.relayConnectivityStatus.localizedStateTitle)
                                .foregroundStyle(relayConnectivityColor)
                        }
                    }

                    if service.relayConnectivityStatus.consecutiveFailureCount > 0 {
                        LabeledContent("Fehlerfolge") {
                            Text("\(service.relayConnectivityStatus.consecutiveFailureCount)")
                        }
                    }

                    if service.relayConnectivityStatus.isPaused {
                        LabeledContent("Pause") {
                            Text("noch ca. \(service.relayConnectivityStatus.remainingPauseSeconds)s")
                        }

                        Button {
                            service.resetRelayConnectivityBackoff()
                        } label: {
                            Label("Relay-Backoff zurücksetzen", systemImage: "play.circle")
                        }
                    }

                    LabeledContent("Ausstehende Outbox") {
                        Text("\(service.pendingOutboxCount())")
                    }

                    if let healthMessage = service.lastRelayHealthMessage {
                        Label(healthMessage, systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    }

                    if let diagnosticMessage = service.lastTransportDiagnosticMessage {
                        Label(diagnosticMessage, systemImage: "network")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let summary = service.lastRelaySyncSummary {
                        LabeledContent("Letzter Sync") {
                            Text(summary.receivedAt, style: .time)
                        }
                        LabeledContent("Verarbeitet") {
                            Text("\(summary.processedCount)")
                        }
                        LabeledContent("Duplikate") {
                            Text("\(summary.duplicateCount)")
                        }
                        LabeledContent("Verworfen") {
                            Text("\(summary.rejectedCount)")
                        }
                        LabeledContent("Bestätigt") {
                            Text("\(summary.deletedCount)")
                        }
                        LabeledContent("Receipts") {
                            Text("\(summary.deliveryReceiptSentCount)")
                        }
                        LabeledContent("ACK-Fehler") {
                            Text("\(summary.acknowledgementFailureCount)")
                        }
                        LabeledContent("Receipt-Fehler") {
                            Text("\(summary.deliveryReceiptFailureCount)")
                        }
                    }

                    if let retrySummary = service.lastOutboxRetrySummary {
                        LabeledContent("Letzter Retry") {
                            Text(retrySummary.completedAt, style: .time)
                        }
                        LabeledContent("Retry Ergebnis") {
                            Text("\(retrySummary.sentCount)/\(retrySummary.attemptedCount) gesendet")
                        }
                    }
                } header: {
                    Text("Transport")
                } footer: {
                    Text(transportFooter)
                }

                SwiftUI.Section {
                    LabeledContent("Paket-Ledger") {
                        Text("\(service.relayLedgerEntryCount())")
                    }
                    LabeledContent("Receipt-Ledger") {
                        Text("\(service.deliveryReceiptLedgerCount())")
                    }

                    Button {
                        service.compactRelayLedger()
                    } label: {
                        Label("Lokales Relay-Ledger komprimieren", systemImage: "archivebox")
                    }

                    Button(role: .destructive) {
                        service.clearRelayLedger()
                    } label: {
                        Label("Lokales Relay-Ledger löschen", systemImage: "trash")
                    }
                } header: {
                    Text("Lokale Wartung")
                } footer: {
                    Text("Das Ledger enthält nur Paket-IDs und Receipt-Metadaten. Löschen ist für Tests nützlich, kann aber alte Relay-Pakete erneut als neu erscheinen lassen.")
                }

                SwiftUI.Section {
                    NavigationLink {
                        ProductionReadinessView(service: service)
                    } label: {
                        Label("Production Readiness", systemImage: "checkmark.shield")
                    }

                    Label("Production Relay: https://securechat.team", systemImage: "globe")
                    Label("Docker/HTTPS-Relay-Baseline liegt im RelayServer-Ordner", systemImage: "externaldrive")
                    Label("Persistenter Relay-Store: STORE_TYPE=file", systemImage: "externaldrive")
                    Label("Bearer-Token schützt /v1/relay/*", systemImage: "key.horizontal")
                } header: {
                    Text("Phase 10")
                } footer: {
                    Text("Die Production-Ansicht ist eine Checkliste für den nächsten Schritt: öffentlicher HTTPS-Relay, Token-Härtung und kontrollierte Backup-Policy.")
                }

                SwiftUI.Section {
                    Label("Nachrichtenstore ist lokal AES-GCM-verschlüsselt", systemImage: "checkmark.shield")
                    Label("Store-Key liegt in der Keychain", systemImage: "key")
                    Label("Trust-State liegt nicht in UserDefaults", systemImage: "lock")
                    Label("Relay-Pakete sind signiert und AEAD-geschützt", systemImage: "signature")
                    Label("Relay-ACKs sind idempotent", systemImage: "checkmark.seal")
                    Label("Delivery-Receipts markieren Nachrichten als delivered", systemImage: "paperplane.circle")
                    Label("Relay-Paket-Ledger liegt in der Keychain", systemImage: "tray.full")
                    Label("Relay-Stats und Purge sind nur Metadaten; keine Klartexte", systemImage: "chart.bar")
                    Label("Lokale Retention kann alte Nachrichten löschen", systemImage: "calendar.badge.clock")
                    Label("Markierungen und Stumm-Status werden lokal verschlüsselt gespeichert", systemImage: "star")
                    Label("Chat-Details zeigen nur lokale Metadaten und Safety-Number", systemImage: "info.circle")
                    Label("Relay-Erfolgslogs sind standardmäßig leise und optional aktivierbar", systemImage: "speaker.slash")
                    Label("Chat-Export erzeugt lokalen Klartext nur nach manueller Aktion", systemImage: "square.and.arrow.up")
                    Label("Vorschau-Schutz blendet Nachrichteninhalte in Listen aus", systemImage: "eye.slash")
                    Label("Diagnosebericht enthält keine Chat-Texte", systemImage: "doc.text.magnifyingglass")
                } header: {
                    Text("Persistenz")
                }
            }
            .navigationTitle("Security")
            .privateChatErrorAlert(service: service)
            .onAppear {
                loadRelayConfiguration()
            }
        }
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private var shortIdentity: String {
        let idPrefix = String(service.localIdentity.id.prefix(12))
        return "\(idPrefix)…"
    }

    private var transportStatusText: String {
        switch service.securityState.transportMode {
        case .localOnly:
            return "Nur lokal"
        case .relayAllowed:
            let url = service.securityState.relayConfiguration.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            if url.isEmpty || service.securityState.relayConfiguration.isEnabled == false {
                return "Relay fehlt"
            }
            if service.securityState.relayConfiguration.isReadyForNetworkRequests == false {
                return "Relay nicht bereit"
            }
            return "Relay aktiv"
        }
    }

    private var transportStatusColor: Color {
        switch service.securityState.transportMode {
        case .localOnly:
            return .orange
        case .relayAllowed:
            let url = service.securityState.relayConfiguration.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            if url.isEmpty || service.securityState.relayConfiguration.isEnabled == false { return .red }
            return service.securityState.relayConfiguration.isReadyForNetworkRequests ? .green : .orange
        }
    }

    private var relayConnectivityColor: Color {
        switch service.relayConnectivityStatus.state {
        case .healthy:
            return .green
        case .degraded:
            return .orange
        case .paused:
            return service.relayConnectivityStatus.isPaused ? .orange : .green
        }
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

    private var transportFooter: String {
        "Production: https://securechat.team mit RELAY_AUTH_TOKEN aus /opt/securechat/.env verwenden. Alte LAN-HTTP-URLs werden blockiert. Auto-Polling startet nur, wenn URL und Token gültig sind."
    }

    private var relayProfileStatusText: String {
        let trimmedURL = relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if SecureChatProductionProfile.isConfiguredProductionRelay(trimmedURL) {
            return "Production aktiv"
        }
        if SecureChatProductionProfile.isObsoleteLocalRelay(trimmedURL) {
            return "alte lokale URL"
        }
        if SecureChatProductionProfile.isLocalOrPrivateRelay(trimmedURL) {
            return "lokal blockiert"
        }
        if SecureChatProductionProfile.isHTTPSProductionCandidate(trimmedURL) {
            return "HTTPS extern"
        }
        return trimmedURL.isEmpty ? "nicht gesetzt" : "prüfen"
    }

    private var relayProfileStatusColor: Color {
        let trimmedURL = relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if SecureChatProductionProfile.isConfiguredProductionRelay(trimmedURL) {
            return .green
        }
        if SecureChatProductionProfile.isObsoleteLocalRelay(trimmedURL) || SecureChatProductionProfile.isLocalOrPrivateRelay(trimmedURL) {
            return .orange
        }
        if trimmedURL.isEmpty {
            return .secondary
        }
        if SecureChatProductionProfile.isHTTPSProductionCandidate(trimmedURL) {
            return .accentColor
        }
        return .orange
    }


    private var relayTokenStatusText: String {
        let trimmedToken = relayToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedToken.isEmpty {
            return "fehlt"
        }
        if SecureChatProductionProfile.isUsableClientToken(trimmedToken) {
            return "gesetzt"
        }
        if trimmedToken.contains("RELAY_AUTH_TOKEN=") {
            return "nur Wert einfügen"
        }
        return "prüfen"
    }

    private var relayTokenStatusColor: Color {
        SecureChatProductionProfile.isUsableClientToken(relayToken) ? .green : .orange
    }

    private var biometricBinding: Binding<Bool> {
        Binding<Bool>(
            get: {
                service.securityState.requireBiometricUnlock
            },
            set: { newValue in
                guard newValue != service.securityState.requireBiometricUnlock else {
                    return
                }
                var state = service.securityState
                state.requireBiometricUnlock = newValue
                service.updateSecurityState(state)
            }
        )
    }

    private var transportModeBinding: Binding<TransportMode> {
        Binding<TransportMode>(
            get: {
                service.securityState.transportMode
            },
            set: { newValue in
                guard newValue != service.securityState.transportMode else {
                    return
                }
                var state = service.securityState
                state.transportMode = newValue
                state.relayConfiguration.isEnabled = newValue == .relayAllowed
                service.updateSecurityState(state)
            }
        )
    }

    private func loadRelayConfiguration() {
        relayURL = service.securityState.relayConfiguration.migratedForSecureChatProduction.baseURLString
        relayToken = service.securityState.relayConfiguration.registrationToken ?? ""
        relayPollingLimit = service.securityState.relayConfiguration.inboxPollingLimit
        relayAutoPollingInterval = service.securityState.relayConfiguration.autoPollingIntervalSeconds
        retryFailedMessagesAutomatically = service.securityState.relayConfiguration.retryFailedMessagesAutomatically
        verboseRelayLogging = service.securityState.relayConfiguration.verboseRelayLogging
        localMessageRetentionDays = service.securityState.localMessageRetentionDays
        hideMessagePreviews = service.securityState.hideMessagePreviews
        reduceKeyboardSuggestions = service.securityState.reduceKeyboardSuggestions
        warnOnRuntimeRisk = service.securityState.warnOnRuntimeRisk
        restrictRelayOnRuntimeRisk = service.securityState.restrictRelayOnRuntimeRisk
    }

    private func applyProductionRelayTemplate() {
        relayURL = SecureChatProductionProfile.relayBaseURLString
        relayPollingLimit = 50
        relayAutoPollingInterval = 15
        retryFailedMessagesAutomatically = true
    }

    private func activateProductionRelay() {
        applyProductionRelayTemplate()
        saveRelayConfiguration()
    }

    private func clearObsoleteLocalRelayConfiguration() {
        relayURL = SecureChatProductionProfile.relayBaseURLString
        saveRelayConfiguration()
    }

    private func saveRelayConfiguration() {
        let trimmedURL = relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = relayToken.trimmingCharacters(in: .whitespacesAndNewlines)

        var state = service.securityState
        let normalizedURL = SecureChatProductionProfile.normalizeRelayBaseURL(trimmedURL)
        let normalizedToken = SecureChatProductionProfile.normalizedToken(trimmedToken)
        let candidateConfiguration = RelayConfiguration(
            isEnabled: normalizedURL.isEmpty == false,
            baseURLString: normalizedURL,
            registrationToken: normalizedToken,
            inboxPollingLimit: relayPollingLimit,
            autoPollingIntervalSeconds: relayAutoPollingInterval,
            retryFailedMessagesAutomatically: retryFailedMessagesAutomatically,
            verboseRelayLogging: verboseRelayLogging
        ).migratedForSecureChatProduction

        let shouldEnableRelay = candidateConfiguration.baseURLString.isEmpty == false
        state.transportMode = candidateConfiguration.baseURLString.isEmpty == false ? .relayAllowed : state.transportMode
        state.relayConfiguration = RelayConfiguration(
            isEnabled: shouldEnableRelay && state.transportMode == .relayAllowed,
            baseURLString: candidateConfiguration.baseURLString,
            registrationToken: candidateConfiguration.registrationToken,
            inboxPollingLimit: relayPollingLimit,
            autoPollingIntervalSeconds: relayAutoPollingInterval,
            retryFailedMessagesAutomatically: retryFailedMessagesAutomatically,
            verboseRelayLogging: verboseRelayLogging
        )
        state.localMessageRetentionDays = localMessageRetentionDays
        state.hideMessagePreviews = hideMessagePreviews
        state.reduceKeyboardSuggestions = reduceKeyboardSuggestions
        state.warnOnRuntimeRisk = warnOnRuntimeRisk
        state.restrictRelayOnRuntimeRisk = restrictRelayOnRuntimeRisk

        service.updateSecurityState(state)
    }

    private func saveLocalRetention() {
        var state = service.securityState
        state.localMessageRetentionDays = localMessageRetentionDays
        service.updateSecurityState(state)
    }

    private func savePrivacySettings() {
        var state = service.securityState
        state.hideMessagePreviews = hideMessagePreviews
        state.reduceKeyboardSuggestions = reduceKeyboardSuggestions
        service.updateSecurityState(state)
    }

    private func saveRuntimeHardeningSettings() {
        var state = service.securityState
        state.warnOnRuntimeRisk = warnOnRuntimeRisk
        state.restrictRelayOnRuntimeRisk = restrictRelayOnRuntimeRisk
        service.updateSecurityState(state)
        service.refreshRuntimeSecurityAssessment()
    }

    private var runtimeRiskColor: Color {
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

    private var securityAIColor: Color {
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
