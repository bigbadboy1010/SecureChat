import SwiftUI

struct RootView: View {
    @ObservedObject var container: AppContainer
    @AppStorage("PrivateChat.didOnboard.v1") private var didOnboard = false
    @AppStorage("PrivateChat.didAcceptBetaDisclaimer.v1") private var didAcceptBetaDisclaimer = false

    var body: some View {
        Group {
            if container.isUnlocked {
                MainTabView(service: container.conversationService)
                    .fullScreenCover(isPresented: onboardingPresentationBinding) {
                        OnboardingView {
                            didOnboard = true
                        }
                    }
                    .sheet(isPresented: betaDisclaimerPresentationBinding) {
                        BetaDisclaimerView {
                            didAcceptBetaDisclaimer = true
                        }
                    }
            } else {
                UnlockView(container: container)
            }
        }
    }

    private var onboardingPresentationBinding: Binding<Bool> {
        Binding(
            get: { didOnboard == false },
            set: { isPresented in
                if isPresented == false {
                    didOnboard = true
                }
            }
        )
    }

    private var betaDisclaimerPresentationBinding: Binding<Bool> {
        Binding(
            get: { didOnboard && didAcceptBetaDisclaimer == false },
            set: { isPresented in
                if isPresented == false {
                    didAcceptBetaDisclaimer = true
                }
            }
        )
    }
}

private struct UnlockView: View {
    @ObservedObject var container: AppContainer

    var body: some View {
        ZStack {
            PrivateChatDesign.pageGradient
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer(minLength: 18)

                VStack(spacing: 18) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(.regularMaterial)
                            .frame(width: 96, height: 96)
                            .overlay {
                                RoundedRectangle(cornerRadius: 30, style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
                            }
                        Image(systemName: "lock.shield")
                            .font(.system(size: 52, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.accentColor)
                    }

                    VStack(spacing: 7) {
                        Text("PrivateChat")
                            .font(.largeTitle.bold())
                        Text("Professioneller E2E Messenger-Core")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Lokale Schlüssel, verifizierte Kontakte und gehärteter Relay-Betrieb.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .privateChatGlassCard(padding: 24, cornerRadius: 30, highlighted: true)

                HStack(spacing: 8) {
                    PrivateChatStatusPill(title: "E2E", systemImage: "lock.fill", tint: .green)
                    PrivateChatStatusPill(title: "Relay", systemImage: "antenna.radiowaves.left.and.right", tint: .accentColor)
                    PrivateChatStatusPill(title: "Hardening", systemImage: "shield", tint: .orange)
                }

                if let errorMessage = container.startupErrorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    Task { await container.unlock() }
                } label: {
                    Label("PrivateChat entsperren", systemImage: "faceid")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 28)

                Spacer(minLength: 18)
            }
            .padding()
        }
    }
}

private struct MainTabView: View {
    @ObservedObject var service: ConversationService

    var body: some View {
        TabView {
            DashboardView(service: service)
                .tabItem {
                    Label("Status", systemImage: "gauge")
                }

            ConversationListView(service: service)
                .tabItem {
                    Label("Chats", systemImage: "message")
                }
                .badge(service.totalUnreadCount())

            PairingView(service: service)
                .tabItem {
                    Label("Pairing", systemImage: "qrcode")
                }

            SettingsView(service: service)
                .tabItem {
                    Label("Security", systemImage: "shield")
                }
        }
        .task {
            service.refreshRuntimeSecurityAssessment()
            service.startRelayAutoSyncLoop()
        }
        .onDisappear {
            service.stopRelayAutoSyncLoop()
        }
    }
}
