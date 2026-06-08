import SwiftUI

struct AppInfoView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @ObservedObject private var insights = SecurityInsightsStore.shared
    @ObservedObject private var mitigation = TrafficMitigationService.shared
    @AppStorage("bit.enableInsightsV1") private var enableInsights: Bool = true

    
#if os(iOS)
@AppStorage("bit.requireBiometricsV1") private var requireBiometrics: Bool = false
        @AppStorage("bit.autoRelockSecondsV1") private var autoRelockSeconds: Double = 30
        @AppStorage("bit.showIntroV1") private var showIntro: Bool = false
@State private var biometricStatusText: String? = nil
#endif

@State private var verifyPeerId: String = ""
    @State private var verifyFingerprint: String = ""
    @State private var verifyResult: String? = nil

    #if os(iOS)
    @State private var showInviteSheet: Bool = false
    @State private var inviteChannel: String? = nil
    @State private var didScanQr: Bool = false
    #endif

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color { colorScheme == .dark ? .black : .white }
    private var textColor: Color { colorScheme == .dark ? .green : Color(red: 0, green: 0.5, blue: 0) }
    private var secondaryTextColor: Color { textColor.opacity(0.8) }

    var body: some View {
        #if os(macOS)
        macBody
        #else
        iosBody
        #endif
    }

    // MARK: - macOS

    @ViewBuilder
    private var macBody: some View {
        VStack(spacing: 0) {
            headerBarMac
            ScrollView { macContent }
                .background(backgroundColor)
        }
        .frame(width: 600, height: 700)
    }

    private var headerBarMac: some View {
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .foregroundColor(textColor)
                .padding()
        }
        .background(backgroundColor.opacity(0.95))
    }

    private var macContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            macIntroCard
            macIdentityAndSettingsCard
            macFeatureSections
            macFooter
        }
        .padding()
    }

    private var macIntroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Neu in BIT Chat").font(.headline)
            Text("• QR-Invite: Channel beitreten per Scan")
            Text("• Identity-Fingerprint: Geräte-Verifikation (Anti-Impersonation)")
            Text("• Delivery/Read Receipts: optional per Setting")
            Text("• Bandwidth-Modus (Low/Normal/High) für Akku/Noise/TTL")
            Text("• Retention: lokaler, verschlüsselter Verlauf mit Cleanup")
        }
        .font(.subheadline)
        .foregroundColor(textColor)
        .padding(.bottom, 8)
    }

    private var macIdentityAndSettingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .center, spacing: 6) {
                Text("BIT Chat")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(textColor)
                Text("secure mesh chat")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(secondaryTextColor)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Identity")
                Text("Dein Fingerprint (persistent):")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(secondaryTextColor)
                Text(viewModel.myIdentityFingerprint)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(textColor)
                    .textSelection(.enabled)

                Divider().background(textColor.opacity(0.3))

                SectionHeader("Network & Receipts")
                Picker("Bandwidth", selection: $viewModel.settings.bandwidthMode) {
                    ForEach(BandwidthMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Store-and-Forward", isOn: $viewModel.settings.storeAndForwardEnabled)
                Toggle("Delivery Receipts", isOn: $viewModel.settings.deliveryReceiptsEnabled)
                Toggle("Read Receipts", isOn: $viewModel.settings.readReceiptsEnabled)

                Divider().background(textColor.opacity(0.3))

                SectionHeader("Peer Verification (manual)")
                TextField("Peer-ID (z.B. ab12cd34)", text: $verifyPeerId)
                    .textFieldStyle(.roundedBorder)
                TextField("Fingerprint (z.B. abcd 1234 ...)", text: $verifyFingerprint)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Verify") {
                        let ok = viewModel.verifyPeer(
                            verifyPeerId.trimmingCharacters(in: .whitespacesAndNewlines),
                            expectedFingerprint: verifyFingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        verifyResult = ok ? "✅ Verified" : "❌ Mismatch / nicht verfügbar"
                    }
                    .buttonStyle(.bordered)

                    if let verifyResult {
                        Text(verifyResult)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(textColor)
                    }
                }

                if !viewModel.verifiedPeers.isEmpty {
                    Text("Verifizierte Peers:")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                    ForEach(Array(viewModel.verifiedPeers).sorted(), id: \.self) { peer in
                        HStack {
                            Text(peer)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(textColor)
                            Spacer()
                            Button("Remove") { viewModel.unverifyPeer(peer) }
                                .buttonStyle(.plain)
                                .foregroundColor(secondaryTextColor)
                        }
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private var macFeatureSections: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader("Features")
            FeatureRow(icon: "wifi.slash", title: "Offline Communication",
                       description: "Works without internet using Bluetooth mesh networking")
            FeatureRow(icon: "lock.shield", title: "End-to-End Encryption",
                       description: "All messages encrypted with Curve25519 + AES-GCM")
            FeatureRow(icon: "antenna.radiowaves.left.and.right", title: "Extended Range",
                       description: "Messages relay through peers, reaching 300m+")
            FeatureRow(icon: "star.fill", title: "Favorites System",
                       description: "Store-and-forward messages for favorites indefinitely")
            FeatureRow(icon: "at", title: "Mentions",
                       description: "Use @nickname to notify specific users")
            FeatureRow(icon: "number", title: "Channels",
                       description: "Create #channels for topic-based conversations")
            FeatureRow(icon: "lock.fill", title: "Password Channels",
                       description: "Secure channels with passwords and AES encryption")

            SectionHeader("Privacy")
            FeatureRow(icon: "eye.slash", title: "No Tracking",
                       description: "No servers, accounts, or data collection")
            FeatureRow(icon: "shuffle", title: "Ephemeral Identity",
                       description: "New peer ID generated each session")
            FeatureRow(icon: "hand.raised.fill", title: "Panic Mode",
                       description: "Triple-tap logo to instantly clear all data")

            SectionHeader("How to Use")
            VStack(alignment: .leading, spacing: 8) {
                Text("• Set your nickname in the header")
                Text("• Swipe left or tap channel name for sidebar")
                Text("• Tap a peer to start a private chat")
                Text("• Use @nickname to mention someone")
                Text("• Use #channelname to create/join channels")
                Text("• Triple-tap the logo for panic mode")
            }
            .font(.system(size: 14, design: .monospaced))
            .foregroundColor(textColor)

            SectionHeader("Commands")
            VStack(alignment: .leading, spacing: 8) {
                Text("/j #channel - join or create a channel")
                Text("/m @name - send private message")
                Text("/w - see who's online")
                Text("/channels - show all discovered channels")
                Text("/block @name - block a peer")
                Text("/block - list blocked peers")
                Text("/unblock @name - unblock a peer")
                Text("/clear - clear current chat")
                Text("/hug @name - send someone a hug")
                Text("/slap @name - slap with a trout")
            }
            .font(.system(size: 14, design: .monospaced))
            .foregroundColor(textColor)

SectionHeader("Security Copilot")
VStack(alignment: .leading, spacing: 8) {
    HStack {
        Text("AI-Insights:")
        Toggle("", isOn: $enableInsights)
            .labelsHidden()
    }
    .font(.system(size: 14, design: .monospaced))
    .foregroundColor(textColor)

    Text("Risk Score: \(insights.globalRiskScore)")
        .font(.system(size: 14, design: .monospaced))
        .foregroundColor(insights.globalRiskScore >= 80 ? .red : textColor)

Text("KI-Filter & Mitigation")
    .font(.system(size: 14, design: .monospaced))
    .foregroundColor(textColor)

HStack {
    Text("Mitigation:")
    Toggle("", isOn: Binding(
        get: { mitigation.enableMitigation },
        set: { mitigation.enableMitigation = $0 }
    ))
    .labelsHidden()
}
.font(.system(size: 14, design: .monospaced))
.foregroundColor(textColor)

HStack {
    Text("Spam-Filter:")
    Toggle("", isOn: Binding(
        get: { mitigation.enableSpamFilter },
        set: { mitigation.enableSpamFilter = $0 }
    ))
    .labelsHidden()
}
.font(.system(size: 14, design: .monospaced))
.foregroundColor(textColor)

HStack {
    Text("Auto-Quarantine:")
    Toggle("", isOn: Binding(
        get: { mitigation.enableAutoQuarantine },
        set: { mitigation.enableAutoQuarantine = $0 }
    ))
    .labelsHidden()
}
.font(.system(size: 14, design: .monospaced))
.foregroundColor(textColor)

VStack(alignment: .leading, spacing: 6) {
    Text("Limit pro Peer (pro Minute): \(mitigation.incomingPeerLimitPerMinute)")
        .font(.system(size: 13, design: .monospaced))
        .foregroundColor(secondaryTextColor)
    Slider(value: Binding(
        get: { Double(mitigation.incomingPeerLimitPerMinute) },
        set: { mitigation.incomingPeerLimitPerMinute = Int($0) }
    ), in: 10...240, step: 5)
}

VStack(alignment: .leading, spacing: 6) {
    Text("Burst Limit (10s): \(mitigation.burstLimit10s)")
        .font(.system(size: 13, design: .monospaced))
        .foregroundColor(secondaryTextColor)
    Slider(value: Binding(
        get: { Double(mitigation.burstLimit10s) },
        set: { mitigation.burstLimit10s = Int($0) }
    ), in: 4...60, step: 1)
}

VStack(alignment: .leading, spacing: 6) {
    Text("Quarantine (Sekunden): \(mitigation.quarantineSeconds)")
        .font(.system(size: 13, design: .monospaced))
        .foregroundColor(secondaryTextColor)
    Slider(value: Binding(
        get: { Double(mitigation.quarantineSeconds) },
        set: { mitigation.quarantineSeconds = Int($0) }
    ), in: 30...3600, step: 30)
}


HStack {
    Text("Persist Quarantine:")
    Toggle("", isOn: Binding(
        get: { mitigation.persistQuarantine },
        set: { mitigation.persistQuarantine = $0 }
    ))
    .labelsHidden()
}
.font(.system(size: 14, design: .monospaced))
.foregroundColor(textColor)

VStack(alignment: .leading, spacing: 8) {
    Text("Trusted Peers (CSV)")
        .font(.system(size: 13, design: .monospaced))
        .foregroundColor(secondaryTextColor)

    TextField("peerA, peerB, peerC", text: Binding(
        get: { mitigation.trustedPeersCsv },
        set: { mitigation.trustedPeersCsv = $0 }
    ))
    .textFieldStyle(.roundedBorder)
    .font(.system(size: 14, design: .monospaced))

    Text("Trusted Peers umgehen Rate-Limits und Spam-Filter.")
        .font(.system(size: 12, design: .monospaced))
        .foregroundColor(secondaryTextColor)
}



    Text("QR-Invite: " + SecurityCopilot.explainQRCodeAndInvite())
        .font(.system(size: 13, design: .monospaced))
        .foregroundColor(secondaryTextColor)

    Text("Fingerprint: " + SecurityCopilot.explainFingerprint())
        .font(.system(size: 13, design: .monospaced))
        .foregroundColor(secondaryTextColor)

    if !insights.recentAlerts.isEmpty {
        Text("Alerts:")
            .font(.system(size: 14, design: .monospaced))
            .foregroundColor(textColor)
        ForEach(Array(insights.recentAlerts.prefix(5))) { a in
            Text("• [\(a.severity.rawValue)] \(a.title): \(a.message)")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(secondaryTextColor)
        }
        Button("Clear Alerts") { insights.clearAlerts() }
            .buttonStyle(.plain)
            .foregroundColor(textColor)
    }
}
.padding(.bottom, 6)


            SectionHeader("Technical Details")
            VStack(alignment: .leading, spacing: 8) {
                Text("Protocol: Custom binary over BLE")
                Text("Encryption: X25519 + AES-256-GCM (per-message KDF ratchet)")
                Text("Range: ~100m direct, 300m+ with relay")
                Text("Store & Forward: 12h for all, ∞ for favorites")
                Text("Battery: Adaptive scanning based on level")
                Text("Platform: Universal (iOS, iPadOS, macOS)")
                Text("Channels: Password-protected with key commitments")
                Text("Storage: Keychain (device-only) for Identity/Keys/Sessions + encrypted retention")
            }
            .font(.system(size: 14, design: .monospaced))
            .foregroundColor(textColor)
        }
    }

    private var macFooter: some View {
        HStack {
            Spacer()
            Text("Version 1.0.0")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(secondaryTextColor)
            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - iOS

    @ViewBuilder
    private var iosBody: some View {
        NavigationView {
            ZStack {
                backgroundColor.ignoresSafeArea()
                ScrollView { iosContent }
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                        .foregroundColor(textColor)
                }
            }
            .sheet(isPresented: $showInviteSheet) {
                if let inviteChannel {
                    QRInviteSheet(channel: inviteChannel)
                        .environmentObject(viewModel)
                }
            }


.onAppear {
    insights.enableInsights = enableInsights
}
.onChange(of: enableInsights) { _, newValue in
    insights.enableInsights = newValue
}        }
    }

    private var iosContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            iosNewCard
            iosIdentityCard
            iosQrCard
            iosSettingsCard

iosCommandsCard
iosHowToCard
iosTechCard
            Spacer(minLength: 16)
        }
        .padding()
    }

    private var iosNewCard: some View {
        card {
            Text("Neu in BIT Chat")
                .font(.title3.weight(.semibold))
                .foregroundColor(textColor)
            VStack(alignment: .leading, spacing: 6) {
                Text("• QR-Invite: Channel beitreten per Scan oder QR teilen")
                Text("• Identity-Fingerprint: Geräte-Verifikation (Anti-Impersonation)")
                Text("• Delivery/Read Receipts: optional per Setting")
                Text("• Bandwidth-Modus (Low/Normal/High): Akku/Noise/TTL")
                Text("• Retention: lokaler, verschlüsselter Verlauf mit Cleanup")
            }
            .font(.subheadline)
            .foregroundColor(secondaryTextColor)
        }
    }

    private var iosIdentityCard: some View {
        card {
            Text("Identity Fingerprint")
                .font(.headline)
                .foregroundColor(textColor)

            Text(viewModel.myIdentityFingerprint)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(secondaryTextColor)
                .textSelection(.enabled)

            HStack(spacing: 10) {
                TextField("Peer ID", text: $verifyPeerId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .textFieldStyle(.roundedBorder)

                TextField("Fingerprint", text: $verifyFingerprint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .textFieldStyle(.roundedBorder)
            }

            Button {
                let ok = viewModel.verifyPeer(
                    verifyPeerId.trimmingCharacters(in: .whitespacesAndNewlines),
                    expectedFingerprint: verifyFingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                verifyResult = ok ? "✅ Verifiziert" : "❌ Mismatch"
            } label: {
                Text("Peer verifizieren")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if let verifyResult {
                Text(verifyResult)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(textColor)
            }
        }
    }

    private var iosQrCard: some View {
        card {
            Text("QR Invite")

#if os(iOS)
GroupBox(label: Text("Login (Face ID / Touch ID)").font(.headline)) {
    VStack(alignment: .leading, spacing: 10) {
        Toggle(isOn: Binding(get: {
            requireBiometrics
        }, set: { newValue in
            Task {
                if newValue {
                    do {
                        let ok = try await BiometricAuthService.shared.authenticateBiometrics(reason: "BIT SecureChat Login aktivieren")
                        await MainActor.run {
                            requireBiometrics = ok
                            biometricStatusText = ok ? "Aktiviert." : "Abgebrochen."
                        }
                    } catch {
                        await MainActor.run {
                            requireBiometrics = false
                            biometricStatusText = error.localizedDescription
                        }
                    }
                } else {
                    await MainActor.run {
                        requireBiometrics = false
                        biometricStatusText = "Deaktiviert."
                    }
                }
            }
        })) {
            Text("Biometrischen Login aktivieren")
        }

        

Toggle(isOn: $showIntro) {
    Text("Intro beim Start anzeigen")
}

VStack(alignment: .leading, spacing: 6) {
    Text("Auto-Relock nach Hintergrund (Sekunden)")
    Slider(value: $autoRelockSeconds, in: 0...300, step: 5)
    Text("\(Int(autoRelockSeconds))s")
        .font(.footnote)
        .foregroundStyle(.secondary)
}
Button {
            Task {
                do {
                    let ok = try await BiometricAuthService.shared.authenticateBiometrics(reason: "BIT SecureChat Test")
                    await MainActor.run {
                        biometricStatusText = ok ? "Test OK." : "Test abgebrochen."
                    }
                } catch {
                    await MainActor.run {
                        biometricStatusText = error.localizedDescription
                    }
                }
            }
        } label: {
            Text("Jetzt testen")
        }
        .buttonStyle(.bordered)

        if let biometricStatusText {
            Text(biometricStatusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Text("Hinweis: Wenn aktiviert, wird BIT SecureChat beim Start gesperrt und verlangt Face ID / Touch ID.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
.padding(.vertical, 6)
#endif

            Text("Erzeuge einen Invite-QR für den aktuellen Channel oder scanne einen Invite.")
                .font(.subheadline)
                .foregroundColor(secondaryTextColor)

            HStack(spacing: 10) {
                Button {
                    inviteChannel = viewModel.currentChannel
                    showInviteSheet = inviteChannel != nil
                } label: {
                    Text("QR anzeigen")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.currentChannel == nil)

                NavigationLink {
                    QRScannerView(onResult: { result in
                        switch result {
                        case .success(let payload):
                            viewModel.applyInviteString(payload)
                        case .failure:
                            break
                        }
                    }, didScan: $didScanQr)
                } label: {
                    Text("QR scannen")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if viewModel.currentChannel == nil {
                Text("Kein Channel ausgewählt.")
                    .font(.footnote)
                    .foregroundColor(secondaryTextColor)
            }
        }
    }

    private var iosSettingsCard: some View {
        card {
            Text("Einstellungen")
                .font(.headline)
                .foregroundColor(textColor)

            Picker("Bandwidth", selection: $viewModel.settings.bandwidthMode) {
                Text("Low").tag(BandwidthMode.low)
                Text("Normal").tag(BandwidthMode.normal)
                Text("High").tag(BandwidthMode.high)
            }
            .pickerStyle(.segmented)

            Toggle("Delivery Receipts", isOn: $viewModel.settings.deliveryReceiptsEnabled)
            Toggle("Read Receipts", isOn: $viewModel.settings.readReceiptsEnabled)
            Toggle("Store-and-Forward", isOn: $viewModel.settings.storeAndForwardEnabled)
        }
        .tint(textColor)
        .foregroundColor(secondaryTextColor)
    }

private var iosSecurityCopilotCard: some View {
    card {
        HStack {
            Text("Security Copilot")
                .font(.headline)
                .foregroundColor(textColor)
            Spacer()
            Text("Risk: \(insights.globalRiskScore)")
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(insights.globalRiskScore >= 80 ? .red : secondaryTextColor)
        }

        Toggle(isOn: $enableInsights) {
            Text("AI-Insights aktiv")
                .foregroundColor(secondaryTextColor)
        }
        .tint(textColor)

        VStack(alignment: .leading, spacing: 6) {
            Text("QR-Invite")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(textColor)
            Text(SecurityCopilot.explainQRCodeAndInvite())
                .font(.footnote)
                .foregroundColor(secondaryTextColor)

            Text("Fingerprint / Safety Number")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(textColor)
            Text(SecurityCopilot.explainFingerprint())
                .font(.footnote)
                .foregroundColor(secondaryTextColor)
        }

        if !insights.recentAlerts.isEmpty {
            Divider().overlay(textColor.opacity(0.25))
            Text("Letzte Warnungen")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(textColor)

            ForEach(Array(insights.recentAlerts.prefix(5))) { alert in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(alert.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(textColor)
                        Spacer()
                        Text(alert.severity.rawValue.uppercased())
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(alert.severity == .critical ? .red : secondaryTextColor)
                    }
                    Text(alert.message)
                        .font(.footnote)
                        .foregroundColor(secondaryTextColor)
                }
                .padding(.vertical, 4)
            }

            Button {
                insights.clearAlerts()
            } label: {
                Text("Warnungen leeren")
                    .font(.footnote)
                    .foregroundColor(textColor)
            }
            .buttonStyle(.plain)
        }
    }
}



    private var iosCommandsCard: some View {
    card {
        Text("Commands")
            .font(.headline)
            .foregroundColor(textColor)

        VStack(alignment: .leading, spacing: 6) {
            Text("/j #channel  – join/create channel")
            Text("/m @name     – private message")
            Text("/w           – who’s online")
            Text("/channels    – discovered channels")
            Text("/block @name – block peer")
            Text("/block       – list blocked")
            Text("/unblock @n  – unblock peer")
            Text("/clear       – clear current chat")
            Text("/hug @name   – send a hug")
            Text("/slap @name  – trout slap 🐟")
        }
        .font(.system(.footnote, design: .monospaced))
        .foregroundColor(secondaryTextColor)
    }
}

private var iosHowToCard: some View {
    card {
        Text("How to Use")
            .font(.headline)
            .foregroundColor(textColor)

        VStack(alignment: .leading, spacing: 6) {
            Text("• Nickname oben setzen")
            Text("• #channel tippen um Channel zu erstellen/joinen")
            Text("• @nickname für Mentions")
            Text("• Peer antippen für Private Chat")
            Text("• Info → QR Invite: beitreten via Scan/QR")
            Text("• Fingerprint verifizieren: Peer-ID + Fingerprint abgleichen")
        }
        .font(.system(.footnote, design: .monospaced))
        .foregroundColor(secondaryTextColor)
    }
}

private var iosTechCard: some View {
    card {
        Text("Technical Details")
            .font(.headline)
            .foregroundColor(textColor)

        VStack(alignment: .leading, spacing: 6) {
            Text("Protocol: BIT v2 binary over BLE / local mesh (hard break) – Private: Double Ratchet, Channels: Sender Keys")
            Text("Encryption: X25519 + AES-256-GCM (per-message KDF ratchet)")
            Text("Range: ~100m direct, 300m+ with relay")
            Text("Store & Forward: optional (Setting)")
            Text("Retention: encrypted local storage + cleanup (NSFileProtectionComplete)")
                Text("Identity: TOFU + Safety-Number Alerts on key change")
            Text("Platform: iOS / iPadOS / macOS")
            Text("Channels: optional password-protected")
        }
        .font(.system(.footnote, design: .monospaced))
        .foregroundColor(secondaryTextColor)
    }
}

// MARK: - Small UI helpers

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(backgroundColor.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(secondaryTextColor.opacity(0.25), lineWidth: 1)
                    )
            )
    }
}



struct SectionHeader: View {
    let title: String
    @Environment(\.colorScheme) var colorScheme
    
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    init(_ title: String) {
        self.title = title
    }
    
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 16, weight: .bold, design: .monospaced))
            .foregroundColor(textColor)
            .padding(.top, 8)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    @Environment(\.colorScheme) var colorScheme
    
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.green.opacity(0.8) : Color(red: 0, green: 0.5, blue: 0).opacity(0.8)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(textColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(textColor)
                
                Text(description)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
    }
}

#Preview {
    AppInfoView()
}