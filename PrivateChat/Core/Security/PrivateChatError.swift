import Foundation

enum PrivateChatError: LocalizedError, Equatable {
    case biometricUnavailable
    case biometricFailed
    case duplicateMessage
    case invalidInboundPacket
    case invalidKeyMaterial
    case invalidPairingPayload
    case invalidRelayURL
    case invalidSignature
    case keychainReadFailed(status: Int32)
    case keychainWriteFailed(status: Int32)
    case keychainDeleteFailed(status: Int32)
    case peerBlocked
    case peerNotTrusted
    case persistenceFailed(String)
    case relayDisabled
    case relayNotConfigured
    case relayMissingClientToken
    case relayObsoleteLocalConfiguration(String)
    case relayLocalhostUnavailableOnDevice
    /// Sprint 14C: the user configured a plain
    /// `http://` URL for a non-development build.
    /// TestFlight / Release builds must use
    /// `https://`; the request is refused at
    /// the transport boundary before the URL
    /// leaves the device.
    case insecureRelayURL
    case relayHealthCheckFailed(String)
    case relayHTTPError(statusCode: Int, message: String?)
    case relayBackoff(statusCode: Int, retryAfterSeconds: Int, message: String?)
    case relayInvalidResponse
    case relayTimedOut
    case relayNoNetwork
    case relayCannotFindHost(String)
    case relayCannotConnectToHost(String)
    case relayConnectionLost
    case relayATSBlocked
    case relayRequestFailed(String)
    case localTransportUnavailable
    case transportUnavailable
    case runtimeIntegrityBlocked(String)
    case encryptionFailed
    case decryptionFailed
    case attachmentTooLarge(maximumBytes: Int)
    case attachmentUnavailable
    case unsupportedAttachment

    var errorDescription: String? {
        switch self {
        case .biometricUnavailable:
            return "Biometrische Entsperrung ist auf diesem Gerät nicht verfügbar."
        case .biometricFailed:
            return "Biometrische Entsperrung fehlgeschlagen."
        case .duplicateMessage:
            return "Nachricht wurde bereits verarbeitet."
        case .invalidInboundPacket:
            return "Ungültiges eingehendes Transportpaket."
        case .invalidKeyMaterial:
            return "Ungültiges kryptografisches Schlüsselmaterial."
        case .invalidPairingPayload:
            return "Ungültiger Pairing-Code."
        case .invalidRelayURL:
            return "Ungültige Relay-Server-URL. Production: \(SecureChatProductionProfile.relayBaseURLString)."
        case .invalidSignature:
            return "Paket-Signatur ist ungültig."
        case .keychainReadFailed(let status):
            return "Keychain-Lesevorgang fehlgeschlagen: \(status)."
        case .keychainWriteFailed(let status):
            return "Keychain-Schreibvorgang fehlgeschlagen: \(status)."
        case .keychainDeleteFailed(let status):
            return "Keychain-Löschvorgang fehlgeschlagen: \(status)."
        case .peerBlocked:
            return "Dieser Kontakt ist blockiert."
        case .peerNotTrusted:
            return "Dieser Kontakt ist noch nicht verifiziert."
        case .persistenceFailed(let message):
            return "Persistenzfehler: \(message)."
        case .relayDisabled:
            return "Relay-Modus ist deaktiviert. Aktiviere unter Einstellungen den Production-Relay."
        case .relayNotConfigured:
            return "Relay ist nicht konfiguriert. Verwende Production \(SecureChatProductionProfile.relayBaseURLString) und die Anmeldung mit deiner Geräteidentität."
        case .relayMissingClientToken:
            return "Der Zugangscode für deinen eigenen Server fehlt oder ist ungültig. PrivateRoom benötigt keinen Betreiber-Token."
        case .relayObsoleteLocalConfiguration(let url):
            return "Veraltete Relay-Konfiguration blockiert: \(url). Verwende \(SecureChatProductionProfile.relayBaseURLString) und melde deine Geräteidentität an."
        case .relayLocalhostUnavailableOnDevice:
            return "localhost/127.0.0.1 ist keine Production-Konfiguration. Verwende \(SecureChatProductionProfile.relayBaseURLString) mit deiner Geräteidentität."
        case .insecureRelayURL:
            return "Plain HTTP ist in TestFlight / Release nicht erlaubt. Verwende \(SecureChatProductionProfile.relayBaseURLString)."
        case .relayHealthCheckFailed(let message):
            return "Relay-Prüfung fehlgeschlagen: \(message)"
        case .relayBackoff(_, let seconds, let message):
            let reason = message == "sender_queue_limit" ? "Die Warteschlange für diesen Kontakt ist vorübergehend voll." : "Der Relay bittet um eine Sendepause."
            return "\(reason) Neuer Versuch frühestens in \(seconds) Sekunden. Deine lokale Nachricht bleibt erhalten."
        case .relayHTTPError(let statusCode, let message):
            if statusCode == 410, message == "packet_expired" {
                return "Das Zustellfenster dieser Nachricht ist abgelaufen. Der Verlauf bleibt erhalten. Sende den Inhalt bei Bedarf bewusst als neue Nachricht."
            }
            if statusCode == 403 {
                switch message?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "recipient_consent_required":
                    return "Der Kontakt hat dein Gerät noch nicht für Nachrichten freigegeben. Beide Geräte benötigen die aktuelle Beta: Kontakt-Code importieren, SC3-Sicherheitsnummer vergleichen, Kontakt verifizieren und PrivateRoom online öffnen. Deine Nachricht bleibt für einen erneuten Versuch erhalten."
                case "recipient_not_admitted":
                    return "Das Empfängergerät ist für die Beta noch nicht freigegeben. Gib dem Betreiber den öffentlichen Kontakt-Code dieses Geräts und sende die Nachricht nach der Freigabe erneut."
                case "beta_admission_required":
                    return "Dieses Gerät ist für die Beta noch nicht freigegeben. Teile deinen öffentlichen Kontakt-Code mit dem Betreiber und melde die Geräteverbindung nach der Freigabe erneut an."
                case "device_access_revoked":
                    return "Der Relay-Zugang dieses Geräts wurde gesperrt. Wende dich für eine erneute Freigabe an den Betreiber."
                default: break
                }
            }
            if statusCode == 401 {
                if let message, message.isEmpty == false {
                    return "Relay-Server hat HTTP 401 zurückgegeben: \(message). Der Server ist erreichbar; prüfe Bearer-Token, Peer-Registrierung und Request-Signatur."
                }
                return "Relay-Server hat HTTP 401 Unauthorized zurückgegeben. Prüfe Bearer-Token, Peer-Registrierung und Request-Signatur."
            }
            if statusCode == 429 {
                if let message,
                   message.localizedCaseInsensitiveContains("recipient relay queue limit exceeded") {
                    return "Die Relay-Warteschlange des Empfängers ist voll. Der Empfänger muss SecureChat öffnen und die Relay-Inbox synchronisieren. Versuche danach diese fehlgeschlagene Nachricht erneut."
                }
                if let message, message.isEmpty == false {
                    return "Relay-Limit erreicht: \(message). Der Versand wird begrenzt; warte kurz und versuche die fehlgeschlagene Nachricht erneut."
                }
                return "Relay-Limit erreicht. Der Versand wird begrenzt; warte kurz und versuche die fehlgeschlagene Nachricht erneut."
            }
            if let message, message.isEmpty == false {
                return "Relay-Server hat HTTP \(statusCode) zurückgegeben: \(message). Prüfe \(SecureChatProductionProfile.relayBaseURLString), Caddy und den SecureChat-Container."
            }
            return "Relay-Server hat HTTP \(statusCode) zurückgegeben. Prüfe \(SecureChatProductionProfile.relayBaseURLString), Caddy und den SecureChat-Container."
        case .relayInvalidResponse:
            return "Relay hat keine gültige HTTP-Antwort geliefert. Prüfe die Relay-URL und ob wirklich der SecureChat-Relay läuft."
        case .relayTimedOut:
            return "Relay-Zeitüberschreitung. Prüfe \(SecureChatProductionProfile.relayBaseURLString), Caddy, Docker-Container und Netzwerk/VPN."
        case .relayNoNetwork:
            return "Keine Netzwerkverbindung zum Relay. Prüfe WLAN/Mobilnetz, VPN und ob \(SecureChatProductionProfile.relayBaseURLString) erreichbar ist."
        case .relayCannotFindHost(let host):
            return "Relay-Host nicht gefunden: \(host). Production muss \(SecureChatProductionProfile.relayBaseURLString) verwenden."
        case .relayCannotConnectToHost(let host):
            return "Verbindung zum Relay-Host fehlgeschlagen: \(host). Prüfe DNS, Caddy und den SecureChat-Container hinter \(SecureChatProductionProfile.relayBaseURLString)."
        case .relayConnectionLost:
            return "Relay-Verbindung wurde unterbrochen. Prüfe WLAN-Stabilität, Netzwerk, Reverse Proxy und Firewall."
        case .relayATSBlocked:
            return "iOS hat die unsichere HTTP-Verbindung blockiert. Für lokale Tests ist nur eine lokale IP erlaubt; produktiv muss HTTPS verwendet werden."
        case .relayRequestFailed(let message):
            return "Relay-Anfrage fehlgeschlagen: \(message)"
        case .localTransportUnavailable:
            return "Direkter lokaler Transport ist in dieser Version noch nicht aktiv. Aktiviere Relay und speichere eine erreichbare Relay-URL."
        case .transportUnavailable:
            return "Transport ist nicht verfügbar. Prüfe Relay-Modus, Relay-URL und Netzwerkverbindung."
        case .runtimeIntegrityBlocked(let reason):
            return "Relay-Transport wurde durch App-Hardening blockiert: \(reason)"
        case .encryptionFailed:
            return "Verschlüsselung fehlgeschlagen."
        case .decryptionFailed:
            return "Entschlüsselung fehlgeschlagen."
        case .attachmentTooLarge(let maximumBytes):
            return "Anhang ist zu groß. Maximal erlaubt sind \(maximumBytes / 1_048_576) MB."
        case .attachmentUnavailable:
            return "Anhang konnte nicht sicher geladen oder gespeichert werden."
        case .unsupportedAttachment:
            return "Dieses Anhangsformat wird nicht unterstützt."
        }
    }
}
