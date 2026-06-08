import SwiftUI

@main
struct PrivateChatApp: App {
    @StateObject private var container = AppContainer.bootstrap()

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
    }
}
