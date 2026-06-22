import SwiftUI

/// SecureChat onboarding. Three animated pages that walk the new
/// user through the privacy story, the transport model, and the
/// pairing ceremony. The first page features a live encryption
/// pulse that visibly locks as the page settles — investors and
/// beta-testers see "this app is built around crypto" before they
/// read a single label.
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page: Int = 0

    var body: some View {
        ZStack {
            SecureChatDesign.pageGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                pageStack
                footer
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SecureChatDesign.brandCyan)
                Text("SecureChat")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(SecureChatDesign.textPrimary)
            }
            Spacer()
            Button("Überspringen") {
                onFinish()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(SecureChatDesign.textSecondary)
        }
        .padding(.horizontal, SecureChatDesign.spaceXL)
        .padding(.top, SecureChatDesign.spaceL)
        .padding(.bottom, SecureChatDesign.spaceS)
    }

    // MARK: - Pages

    private var pageStack: some View {
        TabView(selection: $page) {
            EncryptionPrimerPage()
                .tag(0)
            TransportModesPage()
                .tag(1)
            PairingCeremonyPage()
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: SecureChatDesign.spaceM) {
            Button {
                withAnimation(.easeInOut(duration: 0.4)) { page = max(0, page - 1) }
            } label: {
                Label("Zurück", systemImage: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SecureChatDesign.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .disabled(page == 0)
            .opacity(page == 0 ? 0.4 : 1.0)

            if page >= 2 {
                SecureChatPrimaryButton(
                    title: "Loslegen",
                    systemImage: "arrow.right.circle.fill"
                ) {
                    onFinish()
                }
            } else {
                SecureChatPrimaryButton(
                    title: "Weiter",
                    systemImage: "chevron.right"
                ) {
                    withAnimation(.easeInOut(duration: 0.4)) { page += 1 }
                }
            }
        }
        .padding(.horizontal, SecureChatDesign.spaceXL)
        .padding(.top, SecureChatDesign.spaceL)
        .padding(.bottom, SecureChatDesign.spaceXL)
    }
}

// MARK: - Page 1: encryption primer (with live pulse)

private struct EncryptionPrimerPage: View {
    @State private var locked: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SecureChatDesign.spaceXL) {
                ZStack {
                    Circle()
                        .fill(SecureChatDesign.brandCyan.opacity(0.18))
                        .frame(width: 132, height: 132)
                    Circle()
                        .stroke(SecureChatDesign.brandCyan.opacity(locked ? 0.5 : 0.0), lineWidth: 2)
                        .frame(width: locked ? 168 : 96, height: locked ? 168 : 96)
                    SecureChatEncryptionPulse(
                        tint: SecureChatDesign.brandCyan
                    )
                    .scaleEffect(locked ? 1.0 : 1.15)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: SecureChatDesign.spaceS) {
                    Text("PRIVACY BY DEFAULT")
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(SecureChatDesign.brandCyan)
                    Text("E2E ohne Klartext am Server")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(SecureChatDesign.textPrimary)
                    Text("Jede Nachricht wird lokal verschlüsselt. Der Relay transportiert nur signierte, verschlüsselte Pakete.")
                        .font(.body)
                        .foregroundStyle(SecureChatDesign.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: SecureChatDesign.spaceM) {
                    BulletRow(
                        icon: "key.fill",
                        text: "Curve25519 für Key Exchange, AES-GCM 256 für Inhalte"
                    )
                    BulletRow(
                        icon: "lock.shield",
                        text: "Schlüssel im iOS-Keychain, niemals auf dem Server"
                    )
                    BulletRow(
                        icon: "checkmark.seal.fill",
                        text: "Safety Number pro Kontakt für Out-of-Band-Verifikation"
                    )
                }
            }
            .padding(SecureChatDesign.spaceXL)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).delay(0.4)) {
                locked = true
            }
        }
    }
}

// MARK: - Page 2: transport modes

private struct TransportModesPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SecureChatDesign.spaceXL) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(SecureChatDesign.brandGradient)
                        .frame(width: 132, height: 132)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .shadow(color: SecureChatDesign.brandCyan.opacity(0.30), radius: 24, x: 0, y: 12)

                VStack(alignment: .leading, spacing: SecureChatDesign.spaceS) {
                    Text("DEIN RELAY")
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(SecureChatDesign.brandCyan)
                    Text("Self-Host oder Production")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(SecureChatDesign.textPrimary)
                    Text("SecureChat braucht nur einen Relay — entweder deinen eigenen oder den öffentlichen Production-Relay unter securechat.team.")
                        .font(.body)
                        .foregroundStyle(SecureChatDesign.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: SecureChatDesign.spaceM) {
                    TransportModeRow(
                        title: "Production Relay",
                        subtitle: "https://securechat.team",
                        systemImage: "globe",
                        tint: SecureChatDesign.brandCyan,
                        badge: "Standard"
                    )
                    TransportModeRow(
                        title: "Self-Host",
                        subtitle: "Eigener VPS, eigene Datenhoheit",
                        systemImage: "server.rack",
                        tint: SecureChatDesign.brandPurple,
                        badge: "Maximal"
                    )
                    TransportModeRow(
                        title: "Local Only",
                        subtitle: "Nachrichten bleiben auf dem Gerät (für Tests)",
                        systemImage: "iphone.gen3",
                        tint: SecureChatDesign.warning,
                        badge: "Dev"
                    )
                }
            }
            .padding(SecureChatDesign.spaceXL)
        }
    }
}

// MARK: - Page 3: pairing ceremony

private struct PairingCeremonyPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SecureChatDesign.spaceXL) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [SecureChatDesign.brandPurple, SecureChatDesign.brandCyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 132, height: 132)
                    Image(systemName: "qrcode")
                        .font(.system(size: 60, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .shadow(color: SecureChatDesign.brandPurple.opacity(0.30), radius: 24, x: 0, y: 12)

                VStack(alignment: .leading, spacing: SecureChatDesign.spaceS) {
                    Text("PAIRING & VERTRAUEN")
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(SecureChatDesign.brandCyan)
                    Text("Kontakte bewusst verifizieren")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(SecureChatDesign.textPrimary)
                    Text("Beim Pairing tauschst du nur öffentliche Schlüssel. Die Safety Number vergleichst du über einen zweiten Kanal — Telefon, persönlich, oder ein anderes Chat-Programm.")
                        .font(.body)
                        .foregroundStyle(SecureChatDesign.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: SecureChatDesign.spaceM) {
                    BulletRow(icon: "qrcode.viewfinder", text: "QR-Code oder manueller Pairing-Code")
                    BulletRow(icon: "person.2.fill", text: "Safety Number vor dem Vertrauen vergleichen")
                    BulletRow(icon: "lock.doc.fill", text: "Solo-Test-Chat für Tests ohne zweites Gerät")
                }
            }
            .padding(SecureChatDesign.spaceXL)
        }
    }
}

// MARK: - Reusable row components

private struct BulletRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: SecureChatDesign.spaceM) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SecureChatDesign.brandCyan)
                .frame(width: 24, height: 24)
                .background(SecureChatDesign.brandCyan.opacity(0.14), in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(SecureChatDesign.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TransportModeRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let badge: String

    var body: some View {
        HStack(spacing: SecureChatDesign.spaceM) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SecureChatDesign.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(SecureChatDesign.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(badge.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint.opacity(0.14), in: Capsule())
        }
        .padding(SecureChatDesign.spaceM)
        .secureChatGlassCard(padding: 0, cornerRadius: 16)
    }
}

// MARK: - Beta disclaimer (used by RootView)

struct BetaDisclaimerView: View {
    let onAccept: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SecureChatDesign.spaceL) {
                    SecureChatHeroCard(
                        eyebrow: "Beta-Hinweis",
                        title: "Public Beta, externer Audit offen",
                        subtitle: "SecureChat ist TestFlight-ready. Nutze die Beta noch nicht für hochsensible Kommunikation, bis ein externer Security-Audit abgeschlossen ist.",
                        systemImage: "exclamationmark.shield",
                        tint: SecureChatDesign.warning,
                        footer: "Crypto-Tests grün · externer Audit offen"
                    )

                    VStack(alignment: .leading, spacing: SecureChatDesign.spaceM) {
                        Label("Relay und lokale Stores sind gehärtet, aber der Pairing-Workflow kann sich in Beta-Builds noch ändern.", systemImage: "wrench.and.screwdriver")
                        Label("Diagnose-Reports enthalten technische Metadaten, aber keine Nachrichtenklartexte.", systemImage: "doc.text.magnifyingglass")
                        Label("Feedback aus TestFlight ist erwünscht — besonders zu Pairing, Relay-Token und Safety Number.", systemImage: "bubble.left.and.bubble.right")
                    }
                    .font(.subheadline)
                    .foregroundStyle(SecureChatDesign.textPrimary)
                    .secureChatGlassCard(padding: SecureChatDesign.spaceL)

                    SecureChatPrimaryButton(
                        title: "Verstanden und fortfahren",
                        systemImage: "checkmark.circle.fill"
                    ) {
                        onAccept()
                    }
                }
                .padding()
            }
            .background(SecureChatDesign.pageGradient.ignoresSafeArea())
            .navigationTitle("Beta")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
