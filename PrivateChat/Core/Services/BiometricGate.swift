import Foundation
import LocalAuthentication

@MainActor
protocol BiometricGating {
    func unlock(reason: String) async throws
    func cancel()
}

extension BiometricGating {
    func cancel() {}
}

@MainActor
final class BiometricGate: BiometricGating {
    private var activeContext: LAContext?

    func unlock(reason: String) async throws {
        cancel()
        let context = LAContext()
        activeContext = context
        defer {
            if activeContext === context { activeContext = nil }
        }
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw PrivateChatError.biometricUnavailable
        }

        let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        guard success else {
            throw PrivateChatError.biometricFailed
        }
    }

    func cancel() {
        activeContext?.invalidate()
        activeContext = nil
    }
}
