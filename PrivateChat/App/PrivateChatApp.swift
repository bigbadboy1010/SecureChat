import SwiftUI

@main
struct PrivateChatApp: App {
    @UIApplicationDelegateAdaptor(PrivateRoomAppDelegate.self) private var appDelegate
    @StateObject private var container = AppContainer.bootstrap()

    var body: some Scene {
        WindowGroup {
            PrivateRoomSceneRoot(container: container)
        }
    }
}

/// Scene lifecycle is observed inside the window, not at aggregate App scope.
private struct PrivateRoomSceneRoot: View {
    @ObservedObject var container: AppContainer
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingPairingCode: String?
    @State private var showsPairingConfirmation = false

    var body: some View {
        RootView(container: container)
            .background(PrivacySnapshotCover(isCovered: container.isPrivacyCoverVisible))
            .onChange(of: scenePhase) { phase in
                switch phase {
                case .active: container.becameActive()
                case .inactive: container.becameInactive()
                case .background: container.enteredBackground()
                @unknown default: container.enteredBackground()
                }
            }
            .onOpenURL { url in
                guard ["privateroom", "securechat", "privatechat"].contains(url.scheme?.lowercased() ?? ""),
                      url.host?.lowercased() == "pairing", url.absoluteString.utf8.count <= 8192 else { return }
                pendingPairingCode = url.absoluteString
                showsPairingConfirmation = container.isUnlocked
            }
            .onChange(of: container.isUnlocked) { unlocked in
                showsPairingConfirmation = unlocked && pendingPairingCode != nil
            }
            .alert("Kontakt-Code hinzufügen?", isPresented: $showsPairingConfirmation) {
                Button("Abbrechen", role: .cancel) { pendingPairingCode = nil }
                Button("Kontakt hinzufügen") {
                    guard container.isUnlocked, let code = pendingPairingCode else { return }
                    _ = container.conversationService.importPeer(from: code)
                    pendingPairingCode = nil
                }
            } message: {
                Text("Der Kontakt bleibt unverifiziert. Vergleicht anschließend eure Sicherheitsnummern über einen unabhängigen Kanal.")
            }
    }
}
