// SecureChat/BIT/Views/RootView.swift

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var viewModel: ChatViewModel

    @AppStorage("bit.showIntroV1") private var showIntro: Bool = true
    @AppStorage("bit.requireBiometricsV1") private var requireBiometrics: Bool = false
    @AppStorage("bit.autoRelockSecondsV1") private var autoRelockSeconds: Double = 30

    @Environment(\.scenePhase) private var scenePhase

    @State private var isUnlocked: Bool = false
    @State private var authError: String? = nil
    @State private var didAttemptAuth: Bool = false
    @State private var authTask: Task<Void, Never>? = nil
    @State private var lastBackgroundAt: Date? = nil

    var body: some View {
        ZStack {
            if showIntro {
                IntroView {
                    showIntro = false
                }
            } else {
                mainOrLock
            }
        }

.overlay(alignment: .top) {
    if let b = banner.current {
        SecurityBannerView(title: b.title, message: b.message)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onTapGesture {
                banner.clear()
            }
    }
}
        .onAppear {
            if !showIntro {
                prepareAuthIfNeeded()
            }
        }
        .onChange(of: showIntro) { _, newValue in
            if newValue == false {
                prepareAuthIfNeeded()
            }
        }
        .onChange(of: requireBiometrics) { _, _ in
            // When user enables/disables, force re-evaluation on next appearance
            didAttemptAuth = false
            isUnlocked = false
            authError = nil
            prepareAuthIfNeeded()
        }

.onChange(of: scenePhase) { _, phase in
    guard requireBiometrics else { return }
    switch phase {
    case .background, .inactive:
        lastBackgroundAt = Date()
    case .active:
        if let last = lastBackgroundAt {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed >= max(0, autoRelockSeconds) {
                isUnlocked = false
                didAttemptAuth = false
                authError = nil
                prepareAuthIfNeeded()
            }
        }
        lastBackgroundAt = nil
    @unknown default:
        break
    }
}

    }

    @ViewBuilder
    private var mainOrLock: some View {
        #if os(iOS)
        if requireBiometrics {
            if isUnlocked {
                ContentView()
            } else {
                LockView(
                    errorText: authError,
                    onUnlock: { Task { await authenticate() } },
                    onContinueWithout: { /* no-op, biometrics enforced */ }
                )
                .onAppear { prepareAuthIfNeeded() }
            }
        } else {
            ContentView()
        }
        #else
        ContentView()
        #endif
    }

    private func prepareAuthIfNeeded() {
    #if os(iOS)
    guard requireBiometrics else {
        isUnlocked = true
        return
    }

    // If biometrics are not available, disable the toggle to avoid an endless locked state.
    if !BiometricAuthService.shared.canEvaluateBiometrics() {
        requireBiometrics = false
        isUnlocked = true
        authError = "Biometrische Authentifizierung ist auf diesem Gerät nicht verfügbar."
        return
    }

    guard !didAttemptAuth else { return }
    didAttemptAuth = true

    authTask?.cancel()
    authTask = Task { await authenticate() }
    #else
    isUnlocked = true
    #endif
}

    @MainActor
private func authenticate() async {
    #if os(iOS)
    authError = nil
    do {
        // Biometrics only (FaceID/TouchID). If you want passcode fallback, switch to authenticateAllowPasscode().
        let ok = try await BiometricAuthService.shared.authenticateBiometrics(reason: "BIT SecureChat entsperren")
        isUnlocked = ok
        if !ok {
            authError = "Authentifizierung abgebrochen."
        }
    } catch {
        isUnlocked = false
        authError = error.localizedDescription
    }
    #else
    isUnlocked = true
    #endif
}
}

#if os(iOS)
private struct LockView: View {
    let errorText: String?
    let onUnlock: () -> Void
    let onContinueWithout: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 14) {
                Text("BIT SecureChat")
                    .font(.system(size: 28, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.green.opacity(0.9))

                Text("Login via Face ID / Touch ID")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.green.opacity(0.7))

                if let errorText, !errorText.isEmpty {
                    Text(errorText)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button(action: onUnlock) {
                    Text("Entsperren")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.green.opacity(0.55), lineWidth: 1)
                        )
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.green.opacity(0.9))
                .padding(.top, 6)
            }
            .padding(.horizontal, 24)
        }
    }

private struct SecurityBannerView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
            Text(message)
                .font(.system(size: 13, design: .monospaced))
                .opacity(0.9)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
        .shadow(radius: 8)
        .padding(.top, 10)
        .padding(.horizontal, 12)
    }
}

}
#endif
