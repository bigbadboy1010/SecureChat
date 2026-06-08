import Foundation
import OSLog

final class RelayTransport: RelayMessageTransporting {
    private static let logger = Logger(subsystem: "org.francois.PrivateChat", category: "RelayTransport")

    private let configuration: RelayConfiguration
    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(configuration: RelayConfiguration, urlSession: URLSession? = nil) {
        self.configuration = configuration
        self.urlSession = urlSession ?? RelayTransport.makeDefaultURLSession()
        self.encoder = DateCoding.makeEncoder()
        self.decoder = DateCoding.makeDecoder()
    }

    var isAvailable: Bool {
        configuration.isEnabled && normalizedBaseURL() != nil
    }

    func send(_ packet: OutboundTransportPacket) async throws {
        var request = try makeRequest(path: "/v1/relay/messages")
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(packet)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try await perform(request)
        let sendResponse = try decoder.decode(RelaySendResponse.self, from: data)
        guard sendResponse.accepted, sendResponse.packetID == packet.id else {
            throw PrivateChatError.relayInvalidResponse
        }
    }

    func fetchInbox(recipientID: String, limit: Int) async throws -> [OutboundTransportPacket] {
        let baseURL = try validatedBaseURL()
        guard var components = URLComponents(url: baseURL.appendingPathComponent("v1/relay/messages"), resolvingAgainstBaseURL: false) else {
            throw PrivateChatError.invalidRelayURL
        }

        components.queryItems = [
            URLQueryItem(name: "recipientID", value: recipientID),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 100))))
        ]

        guard let endpointURL = components.url else {
            throw PrivateChatError.invalidRelayURL
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "GET"
        applyDefaultHeaders(to: &request)

        let data = try await perform(request)
        let fetchResponse = try decoder.decode(RelayFetchResponse.self, from: data)
        return fetchResponse.packets
    }

    func delete(packetID: UUID) async throws -> Bool {
        do {
            return try await acknowledge(packetID: packetID)
        } catch let error as PrivateChatError {
            if case .relayHTTPError(let statusCode, _) = error, statusCode == 404 || statusCode == 405 || statusCode == 500 {
                return try await legacyDelete(packetID: packetID)
            }
            throw error
        }
    }

    private func acknowledge(packetID: UUID) async throws -> Bool {
        var request = try makeRequest(path: "/v1/relay/messages/\(packetID.uuidString.lowercased())/ack")
        request.httpMethod = "POST"

        let data = try await perform(request)
        let response = try decoder.decode(RelayDeleteResponse.self, from: data)
        return response.deleted
    }

    private func legacyDelete(packetID: UUID) async throws -> Bool {
        var request = try makeRequest(path: "/v1/relay/messages/\(packetID.uuidString.lowercased())")
        request.httpMethod = "DELETE"

        let data = try await perform(request)
        let response = try decoder.decode(RelayDeleteResponse.self, from: data)
        return response.deleted
    }

    func checkHealth() async throws -> RelayHealthStatus {
        var request = try makeRequest(path: "/health")
        request.httpMethod = "GET"

        let data = try await perform(request)
        let status = try decoder.decode(RelayHealthStatus.self, from: data)
        guard status.isHealthy else {
            throw PrivateChatError.relayHealthCheckFailed("Unerwarteter Health-Status: \(status.status)")
        }
        return status
    }


    func fetchStats() async throws -> RelayStatsResponse {
        var request = try makeRequest(path: "/v1/relay/stats")
        request.httpMethod = "GET"

        let data = try await perform(request)
        return try decoder.decode(RelayStatsResponse.self, from: data)
    }

    func purgeInbox(recipientID: String) async throws -> RelayPurgeResponse {
        var request = try makeRequest(path: "/v1/relay/messages/purge")
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(RelayPurgeRequest(recipientID: recipientID))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try await perform(request)
        return try decoder.decode(RelayPurgeResponse.self, from: data)
    }

    private static func makeDefaultURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    private func makeRequest(path: String) throws -> URLRequest {
        let baseURL = try validatedBaseURL()
        guard let endpointURL = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw PrivateChatError.invalidRelayURL
        }
        var request = URLRequest(url: endpointURL)
        request.timeoutInterval = 8
        applyDefaultHeaders(to: &request)
        return request
    }

    private func applyDefaultHeaders(to request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("PrivateChat-iOS", forHTTPHeaderField: "X-PrivateChat-Client")
        if let registrationToken = configuration.registrationToken, registrationToken.isEmpty == false {
            request.setValue("Bearer \(registrationToken)", forHTTPHeaderField: "Authorization")
        }
    }

    private func validatedBaseURL() throws -> URL {
        guard configuration.isEnabled else {
            throw PrivateChatError.relayDisabled
        }
        guard let baseURL = normalizedBaseURL() else {
            throw PrivateChatError.relayNotConfigured
        }
        guard let scheme = baseURL.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw PrivateChatError.invalidRelayURL
        }
        guard let host = baseURL.host?.lowercased(), host.isEmpty == false else {
            throw PrivateChatError.invalidRelayURL
        }

        #if !targetEnvironment(simulator)
        if host == "localhost" || host == "127.0.0.1" || host == "::1" {
            throw PrivateChatError.relayLocalhostUnavailableOnDevice
        }
        #endif

        return baseURL
    }

    private func normalizedBaseURL() -> URL? {
        let trimmedURL = configuration.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedURL.isEmpty == false else {
            return nil
        }

        let normalized = trimmedURL.hasSuffix("/") ? String(trimmedURL.dropLast()) : trimmedURL
        return URL(string: normalized)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? "<invalid>"
        if configuration.verboseRelayLogging {
            Self.logger.info("Relay request started method=\(method, privacy: .public) path=\(path, privacy: .public)")
        }

        do {
            let (data, response) = try await urlSession.data(for: request)
            try validate(response: response, data: data)
            if configuration.verboseRelayLogging {
                Self.logger.info("Relay request succeeded method=\(method, privacy: .public) path=\(path, privacy: .public)")
            }
            return data
        } catch let error as PrivateChatError {
            Self.logger.error("Relay request failed method=\(method, privacy: .public) path=\(path, privacy: .public) reason=\(error.localizedDescription, privacy: .public)")
            throw error
        } catch let urlError as URLError {
            let mappedError = map(urlError, request: request)
            Self.logger.error("Relay URL error method=\(method, privacy: .public) path=\(path, privacy: .public) code=\(urlError.code.rawValue, privacy: .public) reason=\(mappedError.localizedDescription, privacy: .public)")
            throw mappedError
        } catch {
            let mappedError = PrivateChatError.relayRequestFailed(error.localizedDescription)
            Self.logger.error("Relay unknown error method=\(method, privacy: .public) path=\(path, privacy: .public) reason=\(mappedError.localizedDescription, privacy: .public)")
            throw mappedError
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PrivateChatError.relayInvalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw PrivateChatError.relayHTTPError(statusCode: httpResponse.statusCode, message: relayErrorMessage(from: data))
        }
    }

    private func relayErrorMessage(from data: Data) -> String? {
        guard data.isEmpty == false,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let error = dictionary["error"] as? String else {
            return nil
        }
        return error
    }

    private func map(_ error: URLError, request: URLRequest) -> PrivateChatError {
        let host = request.url?.host ?? configuration.baseURLString
        switch error.code {
        case .timedOut:
            return .relayTimedOut
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            return .relayNoNetwork
        case .cannotFindHost, .dnsLookupFailed:
            return .relayCannotFindHost(host)
        case .cannotConnectToHost:
            return .relayCannotConnectToHost(host)
        case .networkConnectionLost:
            return .relayConnectionLost
        case .appTransportSecurityRequiresSecureConnection:
            return .relayATSBlocked
        default:
            return .relayRequestFailed(error.localizedDescription)
        }
    }
}
