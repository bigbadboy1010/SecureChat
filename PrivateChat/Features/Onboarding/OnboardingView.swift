import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SecureChatDesign.pageGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("PrivateRoom")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(SecureChatDesign.textPrimary)
                    Spacer()
                    Button("Überspringen", action: onFinish)
                        .font(.subheadline)
                        .foregroundStyle(SecureChatDesign.textSecondary)
                        .frame(minHeight: 44)
                }
                .padding(.horizontal, 24)
                TabView(selection: $page) {
                    IntroPage(
                        step: "01 · DEIN PRIVATER RAUM",
                        title: "Gespräche, die\ndir gehören.",
                        message: "Nachrichten und Anhänge werden auf deinem Gerät verschlüsselt. Der Relay vermittelt verschlüsselte Pakete zwischen euren Geräten.",
                        icon: "bubble.left.and.bubble.right",
                        highlights: ["Keine Telefonnummer für deine Identität", "Keine Werbe- oder Analyse-SDKs"],
                        showsMark: true
                    ).tag(0)
                    IntroPage(
                        step: "02 · VERTRAUEN BEWUSST AUFBAUEN",
                        title: "Dein Kontakt.\nDeine Entscheidung.",
                        message: "Tauscht eure QR-Codes aus und vergleicht die Sicherheitsnummer über einen vertrauten zweiten Kanal. Erst nach deiner Bestätigung ist Senden an den Kontakt erlaubt.",
                        icon: "qrcode.viewfinder",
                        highlights: ["Öffentliche Schlüssel per QR oder Code", "Geänderte Schlüssel brauchen neue Prüfung"],
                        showsMark: false
                    ).tag(1)
                    IntroPage(
                        step: "03 · KLARE GRENZEN",
                        title: "Privatsphäre braucht\nklare Erwartungen.",
                        message: "Der Relay verarbeitet Zustellmetadaten. Empfänger können Inhalte weitergeben. Lokale Daten sind vom Backup ausgeschlossen; Geräteverlust kann Datenverlust bedeuten.",
                        icon: "hand.raised",
                        highlights: ["Beta: unabhängiger Sicherheits-Audit offen", "Zustellung wird nur bei echter Bestätigung angezeigt"],
                        showsMark: false
                    ).tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                HStack(spacing: 8) {
                    ForEach(0..<3) { index in
                        Capsule()
                            .fill(index == page ? SecureChatDesign.brandCyan : SecureChatDesign.textTertiary.opacity(0.35))
                            .frame(width: index == page ? 28 : 8, height: 6)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Einführung, Seite \(page + 1) von 3")
                .padding(.bottom, 20)
                HStack(spacing: 14) {
                    if page > 0 {
                        Button {
                            move(to: page - 1)
                        } label: {
                            Image(systemName: "arrow.left")
                                .font(.headline)
                                .frame(width: 52, height: 52)
                                .background(SecureChatDesign.canvasHigh, in: Circle())
                        }
                        .accessibilityLabel("Vorherige Seite")
                    }
                    SecureChatPrimaryButton(
                        title: page == 2 ? "Meinen Raum öffnen" : "Weiter",
                        systemImage: "arrow.right"
                    ) {
                        if page == 2 { onFinish() } else { move(to: page + 1) }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
                .frame(maxWidth: 580)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func move(to destination: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { page = destination }
    }
}

private struct IntroPage: View {
    let step: String
    let title: String
    let message: String
    let icon: String
    let highlights: [String]
    let showsMark: Bool
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 36)
                        .fill(SecureChatDesign.canvasHigh.opacity(0.8))
                        .frame(width: 182, height: 182)
                        .rotationEffect(.degrees(reduceMotion ? 0 : (appeared ? -4 : 4)))
                    RoundedRectangle(cornerRadius: 34)
                        .stroke(SecureChatDesign.brandCyan.opacity(0.24), lineWidth: 1)
                        .frame(width: 178, height: 178)
                        .rotationEffect(.degrees(4))
                    if showsMark {
                        PrivateRoomMark().frame(width: 118, height: 118)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(SecureChatDesign.brandCyan)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .accessibilityHidden(true)
                Text(step)
                    .font(.caption.weight(.bold))
                    .tracking(1.6)
                    .foregroundStyle(SecureChatDesign.brandCyan)
                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .tracking(-0.7)
                    .foregroundStyle(SecureChatDesign.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.body)
                    .foregroundStyle(SecureChatDesign.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(highlights, id: \.self) { highlight in
                        Label(highlight, systemImage: "circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(SecureChatDesign.textPrimary)
                    }
                }
                .secureChatGlassCard(padding: 18, cornerRadius: 22)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
            .frame(maxWidth: 580)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            guard reduceMotion == false else { return }
            withAnimation(.easeOut(duration: 0.65)) { appeared = true }
        }
    }
}

struct BetaDisclaimerView: View {
    let onAccept: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Label("TRANSPARENZ", systemImage: "hand.raised")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(SecureChatDesign.brandCyan)
                    Text("Du sollst wissen,\nwas du testest.")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(SecureChatDesign.textPrimary)
                    Text("PrivateRoom ist in Entwicklung. Ein unabhängiger Sicherheits-Audit ist noch nicht abgeschlossen. Verwende diese Beta noch nicht für hochsensible Kommunikation.")
                        .font(.body)
                        .foregroundStyle(SecureChatDesign.textSecondary)
                    VStack(alignment: .leading, spacing: 18) {
                        Label("Verifizierte Kontakte und verschlüsselte Inhalte sind kein Schutz vor kompromittierten Geräten oder dem Weitergeben durch Empfänger.", systemImage: "person.crop.circle.badge.exclamationmark")
                        Label("Der Relay verarbeitet technische Zustellmetadaten. Vollständige Anonymität wird nicht zugesichert.", systemImage: "network")
                        Label("Lokale Chats und Schlüssel sind vom Cloud-Backup ausgeschlossen. Es gibt noch keinen geprüften Geräteumzug.", systemImage: "externaldrive.badge.exclamationmark")
                    }
                    .font(.subheadline)
                    .foregroundStyle(SecureChatDesign.textPrimary)
                    .secureChatGlassCard(padding: 20)
                    SecureChatPrimaryButton(title: "Verstanden · Beta starten", systemImage: "arrow.right", action: onAccept)
                }
                .padding(26)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(SecureChatDesign.pageGradient.ignoresSafeArea())
            .navigationTitle("Vor dem Start")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}
