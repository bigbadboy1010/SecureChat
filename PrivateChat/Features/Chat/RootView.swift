import SwiftUI

struct RootView: View {
    @ObservedObject var container: AppContainer
    @AppStorage("PrivateRoom.didOnboard.v1") private var didOnboard = false
    @AppStorage("PrivateRoom.didAcceptBetaDisclaimer.v1") private var didAcceptBetaDisclaimer = false

    var body: some View {
        Group {
            if container.isUnlocked {
                MainTabView(service: container.conversationService, onLock: { container.lock() })
                    .fullScreenCover(isPresented: onboardingPresentationBinding) {
                        OnboardingView { didOnboard = true }
                    }
                    .sheet(isPresented: betaDisclaimerPresentationBinding) {
                        BetaDisclaimerView { didAcceptBetaDisclaimer = true }
                            .interactiveDismissDisabled()
                    }
            } else {
                UnlockView(container: container)
            }
        }
        .preferredColorScheme(.dark)
        .tint(SecureChatDesign.brandCyan)
    }

    private var onboardingPresentationBinding: Binding<Bool> {
        Binding(
            get: { didOnboard == false },
            set: { if $0 == false { didOnboard = true } }
        )
    }

    private var betaDisclaimerPresentationBinding: Binding<Bool> {
        Binding(
            get: { didOnboard && didAcceptBetaDisclaimer == false },
            set: { _ in }
        )
    }
}

private struct UnlockView: View {
    @ObservedObject var container: AppContainer

    var body: some View {
        ZStack {
            SecureChatDesign.pageGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 48)
                    PrivateRoomMark()
                        .frame(width: 136, height: 136)
                        .padding(24)
                        .background(SecureChatDesign.canvasElevated, in: RoundedRectangle(cornerRadius: 44))
                        .overlay {
                            RoundedRectangle(cornerRadius: 44)
                                .stroke(SecureChatDesign.subtleBorder, lineWidth: 1)
                        }
                    VStack(spacing: 10) {
                        Text("PrivateRoom")
                            .font(.largeTitle.weight(.bold))
                            .tracking(-0.8)
                            .foregroundStyle(SecureChatDesign.textPrimary)
                        Text("Dein privater Raum.")
                            .font(.title3)
                            .foregroundStyle(SecureChatDesign.textSecondary)
                    }
                    Label("Chats und Schlüssel bleiben gesperrt.", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(SecureChatDesign.textSecondary)
                        .multilineTextAlignment(.center)
                    Spacer(minLength: 48)
                    SecureChatPrimaryButton(
                        title: container.isUnlocking ? "Entsperrung läuft …" : (container.canUnlock ? "PrivateRoom entsperren" : "Startfehler · App gesperrt"),
                        systemImage: "lock.open"
                    ) {
                        Task { await container.unlock() }
                    }
                    .disabled(container.canUnlock == false || container.isUnlocking)
                    .opacity(container.canUnlock ? 1 : 0.55)
                    if let message = container.startupErrorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(SecureChatDesign.warning)
                            .multilineTextAlignment(.center)
                    }
                    Text("Entsperrung über die Gerätesicherheit. PrivateRoom erhält keine biometrischen Daten.")
                        .font(.caption)
                        .foregroundStyle(SecureChatDesign.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(28)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// Retained for source compatibility; the public mark is shared across the app.
struct SecureChatLogoMark: View {
    var body: some View { PrivateRoomMark() }
}

private struct MainTabView: View {
    @ObservedObject var service: ConversationService
    let onLock: () -> Void
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ConversationListView(service: service, onAddContact: { selectedTab = 1 })
                .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right") }
                .badge(service.totalUnreadCount())
                .tag(0)
            PairingView(service: service)
                .tabItem { Label("Kontakte", systemImage: "person.2") }
                .tag(1)
            SettingsView(service: service, onLock: onLock)
                .tabItem { Label("Privatsphäre", systemImage: "hand.raised") }
                .tag(2)
        }
        .tint(SecureChatDesign.brandCyan)
        .task {
            service.refreshRuntimeSecurityAssessment()
            service.startRelayAutoSyncLoop()
        }
        .onDisappear { service.stopRelayAutoSyncLoop() }
    }
}
