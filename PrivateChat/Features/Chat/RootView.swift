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

// MARK: - Unlock screen (LockScreen)

private struct UnlockView: View {
    @ObservedObject var container: AppContainer

    var body: some View {
        ZStack {
            // Aurora background. Slightly stronger on the lock
            // screen so the first impression has more "wow" than
            // the regular pages.
            LinearGradient(
                stops: [
                    .init(color: SecureChatDesign.brandCyan.opacity(0.30), location: 0.0),
                    .init(color: SecureChatDesign.canvasBase, location: 0.45),
                    .init(color: SecureChatDesign.brandPurple.opacity(0.22), location: 1.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: SecureChatDesign.spaceXL) {
                Spacer(minLength: SecureChatDesign.spaceL)

                brandMark
                brandTitle
                statusPills
                Spacer()
                unlockButton
                errorMessage
                Spacer(minLength: SecureChatDesign.spaceL)
            }
            .padding(.horizontal, SecureChatDesign.spaceXL)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Logo

    private var brandMark: some View {
        ZStack {
            // Outer glow ring (static, gives the mark a halo).
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [SecureChatDesign.brandCyan.opacity(0.5), SecureChatDesign.brandPurple.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .frame(width: 152, height: 152)

            // Inner solid mark: brand gradient circle with a custom
            // "SC" interlock glyph (drawn as a path so the design
            // stays consistent with the App-Icon).
            Circle()
                .fill(SecureChatDesign.brandGradient)
                .frame(width: 116, height: 116)
                .shadow(color: SecureChatDesign.brandCyan.opacity(0.45), radius: 28, x: 0, y: 14)

            SecureChatLogoMark()
                .frame(width: 56, height: 56)
                .foregroundStyle(.white)
        }
        .padding(.bottom, SecureChatDesign.spaceS)
    }

    // MARK: - Title

    private var brandTitle: some View {
        VStack(spacing: SecureChatDesign.spaceS) {
            Text("SecureChat")
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundStyle(SecureChatDesign.textPrimary)
                .tracking(-0.5)
            Text("Privacy-first E2E Messenger")
                .font(.headline.weight(.medium))
                .foregroundStyle(SecureChatDesign.textSecondary)
            Text("Lokale Schlüssel, verifizierte Kontakte, gehärteter Relay.")
                .font(.subheadline)
                .foregroundStyle(SecureChatDesign.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SecureChatDesign.spaceM)
        }
    }

    // MARK: - Status pills

    private var statusPills: some View {
        HStack(spacing: SecureChatDesign.spaceS) {
            SecureChatStatusPill(
                title: "E2E",
                systemImage: "lock.fill",
                tint: SecureChatDesign.success
            )
            SecureChatStatusPill(
                title: "Relay",
                systemImage: "antenna.radiowaves.left.and.right",
                tint: SecureChatDesign.brandCyan
            )
            SecureChatStatusPill(
                title: "Hardening",
                systemImage: "shield.fill",
                tint: SecureChatDesign.brandPurple
            )
        }
    }

    // MARK: - Unlock button

    private var unlockButton: some View {
        Button {
            Task { await container.unlock() }
        } label: {
            HStack(spacing: SecureChatDesign.spaceM) {
                Image(systemName: "faceid")
                    .font(.title3.weight(.bold))
                Text("Mit Face ID entsperren")
                    .font(.headline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(SecureChatDesign.brandGradient, in: Capsule())
            .shadow(color: SecureChatDesign.brandCyan.opacity(0.35), radius: 20, x: 0, y: 10)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var errorMessage: some View {
        if let errorMessage = container.startupErrorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(SecureChatDesign.danger)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SecureChatDesign.spaceM)
        }
    }
}

// MARK: - "SC" interlock logo

/// The brand mark drawn as a single path. S + C interlocked, on a
/// circular gradient background. Used on the lock screen, the
/// App-Icon, and the marketing site.
struct SecureChatLogoMark: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // S
                Path { p in
                    let w = geo.size.width
                    let h = geo.size.height
                    // S curve: top-arc, middle-bar, bottom-arc
                    p.move(to: CGPoint(x: w * 0.78, y: h * 0.22))
                    p.addCurve(
                        to: CGPoint(x: w * 0.22, y: h * 0.34),
                        control1: CGPoint(x: w * 0.60, y: h * 0.10),
                        control2: CGPoint(x: w * 0.20, y: h * 0.18)
                    )
                    p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.50))
                    p.addCurve(
                        to: CGPoint(x: w * 0.22, y: h * 0.66),
                        control1: CGPoint(x: w * 0.80, y: h * 0.66),
                        control2: CGPoint(x: w * 0.20, y: h * 0.50)
                    )
                    p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.78))
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: geo.size.width * 0.10, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - Main tab view

private struct MainTabView: View {
    @ObservedObject var service: ConversationService

    var body: some View {
        TabView {
            DashboardView(service: service)
                .tabItem {
                    Label("Status", systemImage: "gauge.with.dots.needle.67percent")
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
                    Label("Security", systemImage: "shield.lefthalf.filled")
                }
        }
        .tint(SecureChatDesign.brandCyan)
        .task {
            service.refreshRuntimeSecurityAssessment()
            service.startRelayAutoSyncLoop()
        }
        .onDisappear {
            service.stopRelayAutoSyncLoop()
        }
    }
}
