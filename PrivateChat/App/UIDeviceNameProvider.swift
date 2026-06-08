import Foundation
import UIKit

enum UIDeviceNameProvider {
    static var defaultDisplayName: String {
        let model = UIDevice.current.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? "PrivateChat" : "PrivateChat \(model)"
    }
}
