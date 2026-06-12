import Foundation

enum SecureChatProductionProfile {
    static let relayBaseURLString = "https://chatsecure.ddns.net"
    static let relayHost = "chatsecure.ddns.net"
    static let relayTokenLocationHint = "/opt/securechat/.env → RELAY_AUTH_TOKEN"

    static let obsoleteLocalRelayHints: [String] = [
        "http://192.168.178.229:8080",
        "http://localhost:8080",
        "http://127.0.0.1:8080"
    ]

    static func normalizedURLString(_ urlString: String) -> String {
        normalizeRelayBaseURL(urlString).lowercased()
    }

    static func normalizeRelayBaseURL(_ urlString: String) -> String {
        var normalized = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }

    static func normalizedToken(_ token: String?) -> String? {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func isUsableClientToken(_ token: String?) -> Bool {
        guard let token = normalizedToken(token) else {
            return false
        }

        // Production tokens generated with `openssl rand -hex 32` are 64 chars.
        // The lower bound still accepts equivalent high-entropy base64 tokens.
        guard token.count >= 32 else {
            return false
        }
        guard token.contains("=") == false else {
            return false
        }
        guard token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return false
        }
        return true
    }

    static func isConfiguredProductionRelay(_ urlString: String) -> Bool {
        normalizedURLString(urlString) == relayBaseURLString
    }

    static func isHTTPSProductionCandidate(_ urlString: String) -> Bool {
        let normalized = normalizeRelayBaseURL(urlString)
        guard let url = URL(string: normalized), let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
            return false
        }
        return scheme == "https" && isLocalOrPrivateHost(host) == false
    }

    static func isLocalOrPrivateRelay(_ urlString: String) -> Bool {
        let normalized = normalizeRelayBaseURL(urlString)
        guard let url = URL(string: normalized), let host = url.host?.lowercased() else {
            return false
        }
        return isLocalOrPrivateHost(host)
    }

    static func isObsoleteLocalRelay(_ urlString: String) -> Bool {
        let normalized = normalizedURLString(urlString)
        if obsoleteLocalRelayHints.contains(normalized) {
            return true
        }

        guard let url = URL(string: normalized), let host = url.host?.lowercased() else {
            return false
        }
        if host == "192.168.178.229" {
            return true
        }
        if isLocalOrPrivateHost(host), url.port == 8080, url.scheme?.lowercased() == "http" {
            return true
        }
        return false
    }

    static func migratedConfiguration(_ configuration: RelayConfiguration) -> RelayConfiguration {
        let normalizedURL = normalizeRelayBaseURL(configuration.baseURLString)
        let token = normalizedToken(configuration.registrationToken)
        let hasToken = isUsableClientToken(token)

        if isObsoleteLocalRelay(normalizedURL) {
            return RelayConfiguration(
                isEnabled: configuration.isEnabled && hasToken,
                baseURLString: relayBaseURLString,
                registrationToken: token,
                inboxPollingLimit: configuration.inboxPollingLimit,
                autoPollingIntervalSeconds: configuration.autoPollingIntervalSeconds,
                retryFailedMessagesAutomatically: configuration.retryFailedMessagesAutomatically,
                autoPurgeRelayInboxAfterSuccessfulSync: configuration.autoPurgeRelayInboxAfterSuccessfulSync,
                verboseRelayLogging: configuration.verboseRelayLogging
            )
        }

        return RelayConfiguration(
            isEnabled: configuration.isEnabled && (normalizedURL.isEmpty == false),
            baseURLString: normalizedURL,
            registrationToken: token,
            inboxPollingLimit: configuration.inboxPollingLimit,
            autoPollingIntervalSeconds: configuration.autoPollingIntervalSeconds,
            retryFailedMessagesAutomatically: configuration.retryFailedMessagesAutomatically,
            autoPurgeRelayInboxAfterSuccessfulSync: configuration.autoPurgeRelayInboxAfterSuccessfulSync,
            verboseRelayLogging: configuration.verboseRelayLogging
        )
    }

    static func readinessIssue(for configuration: RelayConfiguration) -> String? {
        let url = normalizeRelayBaseURL(configuration.baseURLString)
        if configuration.isEnabled == false {
            return "Relay ist deaktiviert."
        }
        if url.isEmpty {
            return "Relay-URL fehlt. Production: \(relayBaseURLString)."
        }
        if isObsoleteLocalRelay(url) {
            return "Alte lokale Relay-URL erkannt. Production verwendet \(relayBaseURLString)."
        }
        if isConfiguredProductionRelay(url) == false && isLocalOrPrivateRelay(url) {
            return "Lokale/LAN-Relay-URL ist für Production nicht gültig."
        }
        if isHTTPSProductionCandidate(url) == false {
            return "Production-Relay muss HTTPS verwenden."
        }
        if isUsableClientToken(configuration.registrationToken) == false {
            return "RELAY_AUTH_TOKEN fehlt oder ist ungültig kurz. Nur den Wert aus /opt/securechat/.env eintragen."
        }
        return nil
    }

    private static func isLocalOrPrivateHost(_ host: String) -> Bool {
        if host == "localhost" || host == "127.0.0.1" || host == "::1" {
            return true
        }
        if host.hasPrefix("192.168.") || host.hasPrefix("10.") {
            return true
        }
        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            if parts.count > 1, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        return false
    }
}
