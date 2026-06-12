import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    var body: some View {
        ZStack {
            PrivateChatDesign.pageGradient
                .ignoresSafeArea()

            VStack(spacing: 18) {
                HStack {
                    Text("PrivateChat einrichten")
                        .font(.headline)
                    Spacer()
                    Button("Überspringen") {
                        onFinish()
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal)
                .padding(.top)

                TabView(selection: $page) {
                    OnboardingPage(
                        systemImage: "lock.shield.fill",
                        eyebrow: "Privat per Design",
                        title: "E2E-Messaging ohne Klartext am Server",
                        message: "Nachrichten werden lokal verschlüsselt gespeichert. Der Relay transportiert nur signierte, verschlüsselte Pakete und benötigt deinen RELAY_AUTH_TOKEN.",
                        bullets: [
                            "AES-GCM mit AAD-Binding",
                            "Keychain-geschützte lokale Schlüssel",
                            "Safety Number für Kontakt-Verifikation"
                        ]
                    )
                    .tag(0)

                    OnboardingPage(
                        systemImage: "antenna.radiowaves.left.and.right",
                        eyebrow: "Transport-Modi",
                        title: "Lokal testen oder Production Relay verwenden",
                        message: "Für den produktiven Relay ist die URL fest auf chatsecure.ddns.net vorbereitet. Alte LAN-URLs werden blockiert, damit keine Debug-Konfiguration versehentlich aktiv bleibt.",
                        bullets: [
                            "Production Relay: https://chatsecure.ddns.net",
                            "Token nur als Wert einfügen, nicht RELAY_AUTH_TOKEN=...",
                            "Auto-Sync startet erst bei gültiger URL und gültigem Token"
                        ]
                    )
                    .tag(1)

                    OnboardingPage(
                        systemImage: "qrcode.viewfinder",
                        eyebrow: "Pairing & Vertrauen",
                        title: "Kontakte bewusst verifizieren",
                        message: "Pairing importiert nur öffentliche Keys. Danach vergleichst du die Safety Number über einen zweiten Kanal und bestätigst jede Gruppe aktiv.",
                        bullets: [
                            "QR-Code oder manueller Pairing-Code",
                            "Safety Number vor dem Vertrauen vergleichen",
                            "Solo-Test-Chat für Tests ohne zweites Gerät"
                        ],
                        primaryActionTitle: "Loslegen",
                        primaryAction: onFinish
                    )
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                HStack {
                    Button {
                        page = max(0, page - 1)
                    } label: {
                        Label("Zurück", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .disabled(page == 0)

                    Spacer()

                    Button {
                        if page >= 2 {
                            onFinish()
                        } else {
                            withAnimation(.easeInOut) { page += 1 }
                        }
                    } label: {
                        Label(page >= 2 ? "Fertig" : "Weiter", systemImage: page >= 2 ? "checkmark" : "chevron.right")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }
}

private struct OnboardingPage: View {
    let systemImage: String
    let eyebrow: String
    let title: String
    let message: String
    let bullets: [String]
    var primaryActionTitle: String? = nil
    var primaryAction: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: 96, height: 96)
                    Image(systemName: systemImage)
                        .font(.system(size: 46, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Text(eyebrow.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                    Text(title)
                        .font(.title.bold())
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(bullets, id: \.self) { bullet in
                        Label(bullet, systemImage: "checkmark.seal")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }

                if let primaryActionTitle, let primaryAction {
                    Button(primaryActionTitle, action: primaryAction)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }
            }
            .privateChatGlassCard(padding: 22, cornerRadius: 28, highlighted: true)
            .padding()
        }
    }
}

struct BetaDisclaimerView: View {
    let onAccept: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PrivateChatHeroCard(
                        eyebrow: "Beta-Hinweis",
                        title: "Production Candidate, nicht extern auditiert",
                        subtitle: "PrivateChat ist für TestFlight und technische Tests vorbereitet. Nutze diese Beta noch nicht für hochsensible Kommunikation, bis ein externer Security-Audit abgeschlossen ist.",
                        systemImage: "exclamationmark.shield",
                        tint: .orange,
                        footer: "Crypto-Tests vorhanden · externer Audit offen"
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Relay und lokale Stores sind gehärtet, aber der Pairing-Workflow kann sich in Beta-Builds noch ändern.", systemImage: "wrench.and.screwdriver")
                        Label("Der Diagnosebericht enthält technische Metadaten, aber keine Nachrichtenklartexte.", systemImage: "doc.text.magnifyingglass")
                        Label("Feedback aus TestFlight ist erwünscht, besonders zu Pairing, Relay-Token und Safety Number.", systemImage: "bubble.left.and.bubble.right")
                    }
                    .font(.subheadline)
                    .privateChatGlassCard(padding: 16)

                    Button {
                        onAccept()
                    } label: {
                        Label("Verstanden und fortfahren", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding()
            }
            .background(PrivateChatDesign.pageGradient.ignoresSafeArea())
            .navigationTitle("Beta")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
