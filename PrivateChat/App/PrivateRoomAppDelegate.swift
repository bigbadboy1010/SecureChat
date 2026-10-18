import UIKit

/// Keep message text out of third-party keyboard extensions in this app.
final class PrivateRoomAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in await PrivateRoomNotifications.shared.registered(deviceToken: deviceToken) }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PrivateRoomNotifications.shared.registrationFailed() }
    }
    func application(_ application: UIApplication, shouldAllowExtensionPointIdentifier identifier: UIApplication.ExtensionPointIdentifier) -> Bool {
        identifier != .keyboard
    }
}
