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
            return "Relay ist nicht konfiguriert. Verwende Production \(SecureChatProductionProfile.relayBaseURLString) mit RELAY_AUTH_TOKEN aus /opt/securechat/.env."
        case .relayMissingClientToken:
            return "RELAY_AUTH_TOKEN fehlt oder ist ungültig. Trage nur den Wert aus /opt/securechat/.env ein, nicht RELAY_ADMIN_TOKEN und nicht den kompletten KEY=VALUE-Text."
        case .relayObsoleteLocalConfiguration(let url):
            return "Veraltete Relay-Konfiguration blockiert: \(url). Verwende \(SecureChatProductionProfile.relayBaseURLString) und RELAY_AUTH_TOKEN."
        case .relayLocalhostUnavailableOnDevice:
            return "localhost/127.0.0.1 ist keine Production-Konfiguration. Verwende \(SecureChatProductionProfile.relayBaseURLString) mit RELAY_AUTH_TOKEN."
        case .insecureRelayURL:
            return "Plain HTTP ist in TestFlight / Release nicht erlaubt. Verwende \(SecureChatProductionProfile.relayBaseURLString)."
        case .relayHealthCheckFailed(let message):
            return "Relay-Prüfung fehlgeschlagen: \(message)"
        case .relayHTTPError(let statusCode, let message):
            if statusCode == 401 {
                if let message, message.isEmpty == false {
                    return "Relay-Server hat HTTP 401 zurückgegeben: \(message). Der Server ist erreichbar; prüfe Bearer-Token, Peer-Registrierung und Request-Signatur."
                }
                return "Relay-Server hat HTTP 401 Unauthorized zurückgegeben. Prüfe Bearer-Token, Peer-Registrierung und Request-Signatur."
            }
            if statusCode == 429 {
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
