import Foundation
import LocalAuthentication

protocol BiometricGating {
    func unlock(reason: String) async throws
}

final class BiometricGate: BiometricGating {
    func unlock(reason: String) async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw PrivateChatError.biometricUnavailable
        }

        let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        guard success else {
            throw PrivateChatError.biometricFailed
        }
    }
}
