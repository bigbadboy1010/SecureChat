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
            return "Ungültige Relay-Server-URL. Production: https://chatsecure.ddns.net."
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
            return "Relay-Modus ist deaktiviert. Aktiviere in Security > Transport das Production-Relay."
        case .relayNotConfigured:
            return "Relay ist nicht konfiguriert. Verwende Production https://chatsecure.ddns.net mit RELAY_AUTH_TOKEN aus /opt/securechat/.env."
        case .relayMissingClientToken:
            return "RELAY_AUTH_TOKEN fehlt oder ist ungültig. Trage nur den Wert aus /opt/securechat/.env ein, nicht RELAY_ADMIN_TOKEN und nicht den kompletten KEY=VALUE-Text."
        case .relayObsoleteLocalConfiguration(let url):
            return "Alte lokale Relay-Konfiguration blockiert: \(url). Verwende https://chatsecure.ddns.net und RELAY_AUTH_TOKEN."
        case .relayLocalhostUnavailableOnDevice:
            return "localhost/127.0.0.1 ist keine Production-Konfiguration. Verwende https://chatsecure.ddns.net mit RELAY_AUTH_TOKEN."
        case .relayHealthCheckFailed(let message):
            return "Relay-Prüfung fehlgeschlagen: \(message)"
        case .relayHTTPError(let statusCode, let message):
            if statusCode == 401 {
                return "Relay-Server hat HTTP 401 Unauthorized zurückgegeben. Der Server ist erreichbar, aber der RELAY_AUTH_TOKEN fehlt oder passt nicht."
            }
            if let message, message.isEmpty == false {
                return "Relay-Server hat HTTP \(statusCode) zurückgegeben: \(message). Prüfe https://chatsecure.ddns.net, Caddy und den SecureChat-Container."
            }
            return "Relay-Server hat HTTP \(statusCode) zurückgegeben. Prüfe https://chatsecure.ddns.net, Caddy und den SecureChat-Container."
        case .relayInvalidResponse:
            return "Relay hat keine gültige HTTP-Antwort geliefert. Prüfe die Relay-URL und ob wirklich der PrivateChat-Relay auf Port 8080 läuft."
        case .relayTimedOut:
            return "Relay-Zeitüberschreitung. Prüfe https://chatsecure.ddns.net, Caddy, Docker-Container und Netzwerk/VPN."
        case .relayNoNetwork:
            return "Keine Netzwerkverbindung zum Relay. Prüfe WLAN/Mobilnetz, VPN und ob https://chatsecure.ddns.net erreichbar ist."
        case .relayCannotFindHost(let host):
            return "Relay-Host nicht gefunden: \(host). Production muss https://chatsecure.ddns.net verwenden."
        case .relayCannotConnectToHost(let host):
            return "Verbindung zum Relay-Host fehlgeschlagen: \(host). Prüfe DNS, Caddy und den SecureChat-Container hinter https://chatsecure.ddns.net."
        case .relayConnectionLost:
            return "Relay-Verbindung wurde unterbrochen. Prüfe WLAN-Stabilität, Mac-Ruhezustand und Firewall."
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
        }
    }
}
