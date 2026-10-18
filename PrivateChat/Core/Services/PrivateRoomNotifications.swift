import Combine
import UIKit
import UserNotifications

/// APNs carries only a neutral activity hint. Decryption and inbox access still
/// require the ordinary unlocked, signed session. No background key access.
@MainActor
final class PrivateRoomNotifications: ObservableObject {
    static let shared = PrivateRoomNotifications()
    private static let preference = "PrivateRoom.neutralNotifications.v1"
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: preference)
    @Published private(set) var isUpdating = false
    @Published private(set) var status = "Mitteilungen sind optional."
    weak var service: ConversationService?
    private var token: String?

    func setEnabled(_ value: Bool) async {
        guard !isUpdating, service?.currentUserSessionID != nil else { return }
        isUpdating = true
        defer { isUpdating = false }
        enabled = value
        UserDefaults.standard.set(value, forKey: Self.preference)
        if value {
            do {
                let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
                guard allowed else {
                    enabled = false
                    UserDefaults.standard.set(false, forKey: Self.preference)
                    status = "Mitteilungen sind in iOS nicht erlaubt. Du kannst dies in den Systemeinstellungen ändern."
                    return
                }
                UIApplication.shared.registerForRemoteNotifications()
                status = "Apple-Geräteregistrierung angefordert. Entsperre PrivateRoom gegebenenfalls erneut."
            } catch { status = "Die Mitteilungsberechtigung konnte nicht geprüft werden." }
        } else {
            UIApplication.shared.unregisterForRemoteNotifications()
            token = nil
            await publish()
        }
    }

    func resumeAfterUnlock() async {
        guard service?.currentUserSessionID != nil else { return }
        if enabled {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                UIApplication.shared.registerForRemoteNotifications()
            } else {
                status = "Mitteilungen sind in iOS nicht erlaubt."
                // Remove a previous server registration when permission was
                // disabled in Settings, without re-prompting on every launch.
                await service?.configureNeutralPush(enabled: false, token: nil)
            }
        } else { await publish() }
    }

    func registered(deviceToken: Data) async {
        guard enabled else { return }
        token = deviceToken.map { String(format: "%02x", $0) }.joined()
        await publish()
    }

    func registrationFailed() {
        status = "Apple konnte dieses Gerät noch nicht für Push registrieren. Nachrichten bleiben beim Öffnen abrufbar."
    }

    private func publish() async {
        guard let service, service.currentUserSessionID != nil else {
            status = "Entsperre PrivateRoom, um die Mitteilungseinstellung am Relay zu aktualisieren."
            return
        }
        guard !enabled || token != nil else { return }
        let saved = await service.configureNeutralPush(enabled: enabled, token: token)
        status = saved
            ? (enabled ? "Neutrale Mitteilungen sind am Relay aktiviert." : "Mitteilungen sind am Relay deaktiviert.")
            : "Die Änderung ist am Relay noch nicht bestätigt. Beim nächsten Entsperren wird sie erneut versucht."
    }
}
