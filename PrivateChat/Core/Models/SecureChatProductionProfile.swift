import Foundation

enum SecureChatProductionProfile {
    static let relayBaseURLString = "https://chatsecure.ddns.net"
    static let relayHost = "chatsecure.ddns.net"
    static let relayTokenLocationHint = "/opt/securechat/.env → RELAY_AUTH_TOKEN"

    static func normalizedURLString(_ urlString: String) -> String {
        urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isConfiguredProductionRelay(_ urlString: String) -> Bool {
        normalizedURLString(urlString).trimmingCharacters(in: CharacterSet(charactersIn: "/")) == relayBaseURLString
    }

    static func isHTTPSProductionCandidate(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)), let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
            return false
        }
        return scheme == "https" && isLocalOrPrivateHost(host) == false
    }

    static func isLocalOrPrivateRelay(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)), let host = url.host?.lowercased() else {
            return false
        }
        return isLocalOrPrivateHost(host)
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
