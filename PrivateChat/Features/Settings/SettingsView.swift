import SwiftUI

struct SettingsView: View {
    @ObservedObject var service: ConversationService
    var onLock: (() -> Void)? = nil
    @State private var isConnecting = false
    @State private var showRetentionConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section {
                    HStack(spacing: 16) {
                        PrivateRoomMark().frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("PrivateRoom").font(.title2.weight(.bold))
                            Text("Deine Privatsphäre. Deine Regeln.")
                                .font(.subheadline)
                                .foregroundStyle(PrivateChatDesign.textSecondary)
                        }
                    }
                    .padding(.vertical, 10)
                }
                SwiftUI.Section {
                    Toggle("App mit Gerätesicherheit entsperren", isOn: setting(\.requireBiometricUnlock))
                    Toggle("Nachrichten-Vorschauen verbergen", isOn: setting(\.hideMessagePreviews))
                    Toggle("Tastatur-Vorschläge reduzieren", isOn: setting(\.reduceKeyboardSuggestions))
                    if let onLock {
                        Button(action: onLock) { Label("PrivateRoom jetzt sperren", systemImage: "lock") }
                    }
                } header: { Text("Dein Gerät") }
                footer: {
                    Text("Der Vorschau-Schutz betrifft die Chatliste und ist keine Screenshot-Sperre. PrivateRoom lässt nur die iOS-Systemtastatur zu; Vorschläge und eine bewusst verwendete Diktierfunktion bleiben Funktionen von iOS.")
                }
                SwiftUI.Section {
                    Stepper("Lokale Aufbewahrungsgrenze: \(service.securityState.localMessageRetentionDays) Tage", value: retentionBinding, in: 1...365)
                    Button {
                        showRetentionConfirmation = true
                    } label: {
                        HStack {
                            Label("Abgelaufene lokale Nachrichten bereinigen", systemImage: "calendar.badge.minus")
                            if service.isLocalRetentionPurgeRunning { ProgressView() }
                        }
                    }
                    .disabled(service.isLocalRetentionPurgeRunning)
                    if let summary = service.lastLocalRetentionSummary {
                        Text("Zuletzt: \(summary.deletedMessages) Nachrichten und \(summary.deletedConversations) Chats entfernt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: { Text("Aufbewahrung") }
                footer: {
                    Text("Chats und Schlüssel sind vom Cloud-Backup ausgeschlossen. Es gibt noch keinen geprüften Geräteumzug. Lokales Löschen entfernt keine Kopien bei Kontakten.")
                }
                SwiftUI.Section {
                    LabeledContent("Modus", value: service.securityState.transportMode == .localOnly ? "Nur auf diesem Gerät" : "Online-Relay erlaubt")
                    if let message = service.lastRelayHealthMessage {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                    if service.securityState.transportMode == .localOnly {
                        Button {
                            guard isConnecting == false else { return }
                            isConnecting = true
                            Task {
                                _ = await service.enablePrivateRoomRelay()
                                isConnecting = false
                            }
                        } label: {
                            HStack {
                                Label("PrivateRoom verbinden", systemImage: "network")
                                if isConnecting { ProgressView() }
                            }
                        }
                        .disabled(isConnecting)
                    } else {
                        Button {
                            Task { await service.checkRelayHealth() }
                        } label: {
                            HStack {
                                Label("Verbindung prüfen", systemImage: "arrow.clockwise")
                                if service.isRelayHealthCheckRunning { ProgressView() }
                            }
                        }
                        .disabled(service.isRelayHealthCheckRunning)
                        Button("Verbindung pausieren") {
                            var state = service.securityState
                            state.transportMode = .localOnly
                            state.relayConfiguration.isEnabled = false
                            _ = service.updateSecurityState(state)
                        }
                    }
                    NavigationLink {
                        PrivateRoomConnectionDetailsView(service: service)
                    } label: {
                        Label("Verbindung & Zustellung", systemImage: "tray.and.arrow.down")
                    }
                } header: { Text("Kommunikation") }
                footer: {
                    Text("Die App ruft Nachrichten ab, solange sie geöffnet und entsperrt ist. Ein Paket am Relay ist noch kein Zustell- oder Lesebeleg. Der Relay verarbeitet technische Metadaten.")
                }
                SwiftUI.Section {
                    NavigationLink { PrivacyPolicyView() } label: {
                        Label("Datenschutz verständlich erklärt", systemImage: "hand.raised")
                    }
                    Link(destination: URL(string: "https://securechat.team/support.html")!) {
                        Label("Hilfe & Kontakt", systemImage: "questionmark.circle")
                    }
                    NavigationLink { PrivateRoomDiagnosticsView(service: service) } label: {
                        Label("Geräte- & Supportdiagnose", systemImage: "stethoscope")
                    }
                    NavigationLink { PrivateRoomAdvancedSettingsView(service: service) } label: {
                        Label("Erweiterte Verbindungseinstellungen", systemImage: "slider.horizontal.3")
                    }
                } header: { Text("Hilfe und Kontrolle") }
                SwiftUI.Section {
                    Label("Beta · unabhängiger Sicherheits-Audit offen", systemImage: "info.circle")
                        .font(.footnote)
                    Text("Kein Versprechen vollständiger Anonymität oder Sicherheit. Für hochsensible Kommunikation ist diese Beta noch nicht freigegeben.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        UserDefaults.standard.set(false, forKey: "PrivateChat.didOnboard.v1")
                        UserDefaults.standard.set(false, forKey: "PrivateChat.didAcceptBetaDisclaimer.v1")
                    } label: {
                        Label("Einführung erneut ansehen", systemImage: "arrow.counterclockwise")
                    }
                    LabeledContent("Version", value: Self.appVersionString)
                        .font(.caption)
                } header: { Text("PrivateRoom") }
            }
            .scrollContentBackground(.hidden)
            .background(PrivateChatDesign.pageGradient.ignoresSafeArea())
            .navigationTitle("Privatsphäre")
            .privateChatErrorAlert(service: service)
            .confirmationDialog("Abgelaufene Nachrichten löschen?", isPresented: $showRetentionConfirmation, titleVisibility: .visible) {
                Button("Jetzt lokal bereinigen", role: .destructive) { service.purgeExpiredLocalMessages() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Nachrichten außerhalb der eingestellten Aufbewahrungsgrenze und zugehörige lokale Anhänge werden entfernt. Diese Aktion kann nicht rückgängig gemacht werden.")
            }
        }
    }

    private func setting(_ keyPath: WritableKeyPath<AppSecurityState, Bool>) -> Binding<Bool> {
        Binding(
            get: { service.securityState[keyPath: keyPath] },
            set: { value in
                var state = service.securityState
                state[keyPath: keyPath] = value
                _ = service.updateSecurityState(state)
            }
        )
    }

    private var retentionBinding: Binding<Int> {
        Binding(
            get: { service.securityState.localMessageRetentionDays },
            set: { value in
                var state = service.securityState
                state.localMessageRetentionDays = value
                _ = service.updateSecurityState(state)
            }
        )
    }

    static var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

private struct PrivateRoomConnectionDetailsView: View {
    @ObservedObject var service: ConversationService
    @State private var isEnrolling = false

    var body: some View {
        List {
            SwiftUI.Section {
                LabeledContent("Relay", value: service.securityState.relayConfiguration.baseURLString.isEmpty ? "Nicht eingerichtet" : service.securityState.relayConfiguration.baseURLString)
                    .font(.footnote)
                LabeledContent("Abruf", value: service.isRelayAutoPollingActive ? "Aktiv bei geöffneter App" : "Pausiert")
                LabeledContent("Ausstehende Nachrichten", value: "\(service.pendingOutboxCount())")
                LabeledContent("Fehlgeschlagene Nachrichten", value: "\(service.failedMessageCount())")
                if let message = service.lastRelayHealthMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                Button {
                    guard isEnrolling == false else { return }
                    isEnrolling = true
                    Task {
                        _ = await service.enrollLocalPeerIfNeeded()
                        isEnrolling = false
                    }
                } label: {
                    HStack {
                        Label("Geräteverbindung erneut anmelden", systemImage: "person.crop.circle.badge.checkmark")
                        if isEnrolling { ProgressView() }
                    }
                }
                .disabled(isEnrolling || service.securityState.transportMode != .relayAllowed)
                Button {
                    Task { await service.syncRelayInbox() }
                } label: {
                    HStack {
                        Label("Nachrichten jetzt abrufen", systemImage: "arrow.down.circle")
                        if service.isRelaySyncRunning { ProgressView() }
                    }
                }
                .disabled(service.isRelaySyncRunning || service.securityState.transportMode != .relayAllowed)
                Button {
                    Task { await service.retryPendingOutboundMessages() }
                } label: {
                    HStack {
                        Label("Ausstehende Nachrichten aller Chats erneut senden", systemImage: "arrow.clockwise")
                        if service.isOutboxRetryRunning { ProgressView() }
                    }
                }
                .disabled(service.isOutboxRetryRunning || service.pendingOutboxCount() == 0 || service.securityState.transportMode != .relayAllowed)
                if service.relayConnectivityStatus.isPaused {
                    LabeledContent("Abrufpause", value: "Noch ca. \(service.relayConnectivityStatus.remainingPauseSeconds) Sekunden")
                    Button("Automatische Abrufpause zurücksetzen") { service.resetRelayConnectivityBackoff() }
                }
                if let summary = service.lastRelaySyncSummary {
                    LabeledContent("Zuletzt abgerufen", value: summary.receivedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Verarbeitete Pakete", value: "\(summary.processedCount)")
                }
            } header: { Text("Tatsächlicher Verbindungsstatus") }
            SwiftUI.Section {
                status("Wartet", detail: "Lokal aufgenommen; Übertragung steht noch aus.", icon: "clock")
                status("Sendet", detail: "Die App versucht gerade zu übertragen.", icon: "arrow.up.circle")
                status("Am Relay", detail: "Der Vermittlungsserver hat das Paket angenommen. Das andere Gerät hat den Empfang noch nicht bestätigt.", icon: "tray.and.arrow.up")
                status("Zugestellt", detail: "Das Gerät des Kontakts hat den Empfang bestätigt. Das ist keine Lesebestätigung.", icon: "checkmark.seal")
                status("Fehler", detail: "Die Übertragung ist fehlgeschlagen. Prüfe Verbindung und Kontaktstatus, bevor du erneut sendest.", icon: "exclamationmark.triangle")
            } header: { Text("Was die Zeichen bedeuten") }
            footer: { Text("„Gesendet“ wird auch für lokale Notizen verwendet. Dort gibt es keine externe Gegenstelle.") }
        }
        .navigationTitle("Verbindung")
        .navigationBarTitleDisplayMode(.inline)
        .privateChatErrorAlert(service: service)
    }

    private func status(_ title: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold))
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }
}

private struct PrivateRoomDiagnosticsView: View {
    @ObservedObject var service: ConversationService
    @State private var showReport = false

    var body: some View {
        List {
            SwiftUI.Section {
                Text("Diese lokalen Hinweise sind keine Zertifizierung und kein unabhängiger Sicherheits-Audit. Sie untersuchen technische Zustände, nicht die Vertrauenswürdigkeit eines Kontakts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LabeledContent("Gerätestatus", value: service.runtimeSecuritySnapshot.riskLevel.localizedTitle)
                Button {
                    service.refreshRuntimeSecurityAssessment()
                } label: { Label("Gerätestatus neu prüfen", systemImage: "arrow.clockwise") }
                Toggle("Technische Warnungen anzeigen", isOn: runtimeSetting(\.warnOnRuntimeRisk))
                Toggle("Relay bei kritischen Gerätehinweisen blockieren", isOn: runtimeSetting(\.restrictRelayOnRuntimeRisk))
                ForEach(service.runtimeSecuritySnapshot.findings) { finding in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(finding.title).font(.subheadline.weight(.semibold))
                        Text(finding.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } header: { Text("Lokale Geräteprüfung") }
            SwiftUI.Section {
                Button { showReport = true } label: {
                    Label("Supportbericht vor dem Teilen prüfen", systemImage: "doc.text.magnifyingglass")
                }
            } footer: {
                Text("Der Bericht enthält keine Chat-Texte, Schlüssel oder Tokens. Technische Metadaten können trotzdem deine Konfiguration offenlegen. Prüfe den Inhalt vor dem Teilen.")
            }
        }
        .navigationTitle("Diagnose")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showReport) {
            PrivateRoomSupportReportView(text: service.appDiagnosticsReport())
        }
        .privateChatErrorAlert(service: service)
    }

    private func runtimeSetting(_ keyPath: WritableKeyPath<AppSecurityState, Bool>) -> Binding<Bool> {
        Binding(
            get: { service.securityState[keyPath: keyPath] },
            set: { value in
                var state = service.securityState
                state[keyPath: keyPath] = value
                _ = service.updateSecurityState(state)
            }
        )
    }
}

private struct PrivateRoomSupportReportView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Du entscheidest, was du weitergibst.").font(.headline)
                    Text("Technische Metadaten können Rückschlüsse auf dein Gerät und deine Verbindung erlauben. Der Bericht wird erst durch deine Aktion geteilt.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(text).font(.caption.monospaced()).textSelection(.enabled)
                    ShareLink(item: text) { Label("Geprüften Bericht teilen", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
                    Button {
                        PrivateRoomClipboard.copy(text)
                    } label: { Label("Lokal für 1 Minute kopieren", systemImage: "doc.on.doc") }
                        .buttonStyle(.bordered)
                }
                .padding(24)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Supportbericht")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Schließen") { dismiss() } }
            }
        }
    }
}

private struct PrivateRoomAdvancedSettingsView: View {
    @ObservedObject var service: ConversationService
    @State private var relayURL = ""
    @State private var relayToken = ""
    @State private var pollingLimit = 50
    @State private var pollingInterval = 15
    @State private var retryAutomatically = true
    @State private var verboseLogging = false
    @State private var showPurgeConfirmation = false
    @State private var showLedgerConfirmation = false
    @State private var savedMessage: String?

    var body: some View {
        Form {
            SwiftUI.Section {
                Text("Für selbst betriebene oder besonders konfigurierte Relay-Server. Die normale PrivateRoom-Verbindung wird ohne einen Betreiber-Token eingerichtet.")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("HTTPS-Relay-URL", text: $relayURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("Zugangstoken des eigenen Relay · falls nötig", text: $relayToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Konfiguration speichern") { saveConfiguration() }
                if let savedMessage { Text(savedMessage).font(.caption).foregroundStyle(.secondary) }
                if service.securityState.transportMode == .localOnly {
                    Button("Gespeicherte Verbindung bewusst aktivieren") {
                        var state = service.securityState
                        state.transportMode = .relayAllowed
                        state.relayConfiguration.isEnabled = true
                        guard service.updateSecurityState(state) else { return }
                        Task { _ = await service.enrollLocalPeerIfNeeded() }
                    }
                }
            } header: { Text("Eigener Relay") }
            footer: {
                Text("Speichern aktiviert keinen Netzwerktransport. Verwende nur einen Relay, dessen Betreiber du vertraust. HTTPS und Gerätesignaturen bleiben erforderlich.")
            }
            SwiftUI.Section {
                Stepper("Pakete pro Abruf: \(pollingLimit)", value: $pollingLimit, in: 1...100)
                Stepper("Abruf bei geöffneter App: \(pollingInterval) Sekunden", value: $pollingInterval, in: 5...300, step: 5)
                Toggle("Fehlgeschlagene Übertragungen automatisch erneut versuchen", isOn: $retryAutomatically)
                Toggle("Zusätzliche technische Erfolgshinweise", isOn: $verboseLogging)
            } header: { Text("Abruf und technische Hinweise") }
            SwiftUI.Section {
                Button {
                    Task { await service.fetchRelayStats() }
                } label: {
                    HStack {
                        Label("Relay-Metadaten abrufen", systemImage: "chart.bar")
                        if service.isRelayStatsRunning { ProgressView() }
                    }
                }
                .disabled(service.isRelayStatsRunning || service.securityState.transportMode != .relayAllowed)
                if let stats = service.lastRelayStatsSnapshot {
                    LabeledContent("Gespeicherte Pakete", value: "\(stats.storedPackets)")
                    LabeledContent("Aktive Empfänger", value: "\(stats.activeRecipients)")
                }
                Button("Relay-Inbox dieses Geräts leeren", role: .destructive) { showPurgeConfirmation = true }
                    .disabled(service.isRelayPurgeRunning || service.securityState.transportMode != .relayAllowed)
            } header: { Text("Relay-Wartung") }
            SwiftUI.Section {
                LabeledContent("Paket-Referenzen", value: "\(service.relayLedgerEntryCount())")
                LabeledContent("Empfangsbestätigungen", value: "\(service.deliveryReceiptLedgerCount())")
                Button("Referenzen kompakt speichern") { service.compactRelayLedger() }
                Button("Lokale Zustellreferenzen zurücksetzen", role: .destructive) { showLedgerConfirmation = true }
            } header: { Text("Lokale Wartung") }
            footer: {
                Text("Ein Zurücksetzen kann alte Relay-Pakete erneut als neu erscheinen lassen. Nur zur gezielten Fehlerbehebung verwenden.")
            }
        }
        .navigationTitle("Erweitert")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadConfiguration() }
        .privateChatErrorAlert(service: service)
        .confirmationDialog("Relay-Inbox dieses Geräts leeren?", isPresented: $showPurgeConfirmation, titleVisibility: .visible) {
            Button("Pakete am Relay löschen", role: .destructive) {
                Task { await service.purgeRelayInbox() }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { Text("Noch nicht abgerufene Pakete für dieses Gerät können verloren gehen. Lokale Chats und andere Empfänger werden nicht geleert.") }
        .confirmationDialog("Lokale Zustellreferenzen zurücksetzen?", isPresented: $showLedgerConfirmation, titleVisibility: .visible) {
            Button("Referenzen zurücksetzen", role: .destructive) { service.clearRelayLedger() }
            Button("Abbrechen", role: .cancel) {}
        } message: { Text("Die Duplikaterkennung verliert ihre gespeicherten Referenzen. Dies löscht keine Nachrichten beim Kontakt.") }
    }

    private func loadConfiguration() {
        let configuration = service.securityState.relayConfiguration
        relayURL = configuration.baseURLString
        relayToken = configuration.registrationToken ?? ""
        pollingLimit = configuration.inboxPollingLimit
        pollingInterval = configuration.autoPollingIntervalSeconds
        retryAutomatically = configuration.retryFailedMessagesAutomatically
        verboseLogging = configuration.verboseRelayLogging
    }

    private func saveConfiguration() {
        var state = service.securityState
        let previousConfiguration = state.relayConfiguration
        state.relayConfiguration = RelayConfiguration(
            isEnabled: state.transportMode == .relayAllowed && previousConfiguration.isEnabled,
            baseURLString: SecureChatProductionProfile.normalizeRelayBaseURL(relayURL),
            registrationToken: SecureChatProductionProfile.normalizedToken(relayToken),
            inboxPollingLimit: pollingLimit,
            autoPollingIntervalSeconds: pollingInterval,
            retryFailedMessagesAutomatically: retryAutomatically,
            autoPurgeRelayInboxAfterSuccessfulSync: previousConfiguration.autoPurgeRelayInboxAfterSuccessfulSync,
            verboseRelayLogging: verboseLogging
        )
        guard service.updateSecurityState(state) else { savedMessage = nil; return }
        savedMessage = state.transportMode == .localOnly ? "Gespeichert. Die App bleibt nur lokal." : "Gespeichert. Der bereits aktivierte Relay-Modus bleibt bestehen."
    }
}
