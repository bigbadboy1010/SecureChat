import UIKit

class ShakeDetectorWindow: UIWindow {
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .redModeActivated, object: nil)
        }
    }
}
extension Notification.Name {
    static let redModeActivated = Notification.Name("redModeActivated")
}
