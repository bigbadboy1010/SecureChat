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
            return "Ungültige Relay-Server-URL. Production: https://chatsecure.ddns.net. Lokaler Test: http://192.168.178.229:8080"
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
            return "Relay-Modus ist deaktiviert. Aktiviere in Security > Transport den Modus \"Relay erlaubt\"."
        case .relayNotConfigured:
            return "Relay ist nicht konfiguriert. Production: https://chatsecure.ddns.net mit RELAY_AUTH_TOKEN. Lokaler Test: Mac-WLAN-IP statt localhost, z. B. http://192.168.178.229:8080"
        case .relayLocalhostUnavailableOnDevice:
            return "localhost/127.0.0.1 funktioniert auf einem echten iPhone nicht. Verwende Production https://chatsecure.ddns.net oder für LAN-Tests die WLAN-IP deines Macs, z. B. http://192.168.178.229:8080."
        case .relayHealthCheckFailed(let message):
            return "Relay-Prüfung fehlgeschlagen: \(message)"
        case .relayHTTPError(let statusCode, let message):
            if let message, message.isEmpty == false {
                return "Relay-Server hat HTTP \(statusCode) zurückgegeben: \(message). Prüfe Relay-URL, Firewall und ob npm run dev läuft."
            }
            return "Relay-Server hat HTTP \(statusCode) zurückgegeben. Prüfe Relay-URL, Firewall und ob npm run dev läuft."
        case .relayInvalidResponse:
            return "Relay hat keine gültige HTTP-Antwort geliefert. Prüfe die Relay-URL und ob wirklich der PrivateChat-Relay auf Port 8080 läuft."
        case .relayTimedOut:
            return "Relay-Zeitüberschreitung. Prüfe, ob iPhone und Mac im gleichen WLAN sind, ob die Mac-Firewall Node/Terminal erlaubt und ob die IP korrekt ist."
        case .relayNoNetwork:
            return "Keine Netzwerkverbindung zum Relay. Prüfe WLAN, VPN, iOS Local-Network-Freigabe und macOS-Firewall."
        case .relayCannotFindHost(let host):
            return "Relay-Host nicht gefunden: \(host). Production sollte https://chatsecure.ddns.net sein. Für lokale Tests die numerische Mac-WLAN-IP verwenden, z. B. http://192.168.178.229:8080."
        case .relayCannotConnectToHost(let host):
            return "Verbindung zum Relay-Host fehlgeschlagen: \(host). Bei Production https://chatsecure.ddns.net/Caddy/Container prüfen; bei lokalen Tests npm run dev und WLAN-Port 8080 prüfen."
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
