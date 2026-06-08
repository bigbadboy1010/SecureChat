// SecureChat/BIT/Services/BiometricAuthService.swift

import Foundation

#if os(iOS)
import Combine
import LocalAuthentication

enum BiometricAuthError: Error, LocalizedError {
    case unavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Biometrische Authentifizierung ist auf diesem Gerät nicht verfügbar."
        case .failed(let msg):
            return msg
        }
    }
}

@MainActor
final class BiometricAuthService: ObservableObject {
    static let shared = BiometricAuthService()

    private init() {}

    func canEvaluateBiometrics() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func authenticateBiometrics(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Abbrechen"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw BiometricAuthError.unavailable
        }

        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            return ok
        } catch {
            throw BiometricAuthError.failed(error.localizedDescription)
        }
    }


/// Optional fallback: biometrics OR device passcode. Not used by default.
func authenticateAllowPasscode(reason: String) async throws -> Bool {
    let context = LAContext()
    context.localizedCancelTitle = "Abbrechen"
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
        throw BiometricAuthError.unavailable
    }
    do {
        return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    } catch {
        throw BiometricAuthError.failed(error.localizedDescription)
    }
}
}
#endif
