import CryptoKit
import Foundation
import OSLog

final class RelayTransport: RelayMessageTransporting {
    private static let logger = Logger(subsystem: "org.francois.PrivateChat", category: "RelayTransport")

    private let configuration: RelayConfiguration
    private let signingContext: PeerBoundSigningContext?
    private let crypto: CryptoServicing?
    private let clientVersion: String
    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        configuration: RelayConfiguration,
        signingContext: PeerBoundSigningContext? = nil,
        crypto: CryptoServicing? = nil,
        clientVersion: String = "org.francois.PrivateChat/1.4.2/12",
        urlSession: URLSession? = nil
    ) {
        self.configuration = configuration
        self.signingContext = signingContext
        self.crypto = crypto
        self.clientVersion = clientVersion
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

    /// Sprint 14A: `/health` is operator-only on
    /// the new relay. The public healthcheck is
    /// `/healthz` (see CURRENT-ENDPOINTS.md and
    /// ADR-005). Calling `/health` here would
    /// 401 in production with no ops token.
    func checkHealth() async throws -> RelayHealthStatus {
        var request = try makeRequest(path: "/healthz")
        request.httpMethod = "GET"

        let data = try await perform(request)
        let status = try decoder.decode(RelayHealthStatus.self, from: data)
        guard status.isHealthy else {
            throw PrivateChatError.relayHealthCheckFailed("Unerwarteter Health-Status: \(status.status)")
        }
        return status
    }

    /// Sprint 27 (2026-06-24): peer enrollment.
    ///
    /// The relay's peer-bound auth requires the
    /// local iOS app's Ed25519 public key to be
    /// in `peer-registry.json` before any signed
    /// request is accepted (otherwise the relay
    /// returns 401 `unsigned_request_required`
    /// or 401 `peer_not_enrolled`). This method
    /// is the iOS-side counterpart to the
    /// server's `POST /v1/relay/peers` route.
    ///
    /// Wire format (request):
    /// ```
    /// POST /v1/relay/peers
    /// Authorization: Bearer <registrationToken>
    /// Content-Type: application/json
    /// {
    ///   "peerID": "<64 hex of sha256(signingPubRaw)>",
    ///   "publicKeyPem": "<SPKI PEM of Ed25519>",
    ///   "clientVersion": "org.francois.PrivateChat/<version>/<build>"
    /// }
    /// ```
    ///
    /// The relay responds with 200 and a body
    /// containing the registered `peerID`,
    /// `registeredAt` epoch millis, and the
    /// current `registrySize`. 4xx errors are
    /// re-thrown as `relayHTTPError` so the
    /// caller can decide whether to retry.
    ///
    /// **Important:** this request must be
    /// bearer-only, not peer-signed (chicken-and-
    /// egg). The server's `preHandler` enforces
    /// this by checking `request.url.startsWith(
    /// '/v1/relay/peers')` and skipping the
    /// `requirePeerAuth` step. iOS automatically
    /// sends the bearer token because
    /// `applyDefaultHeaders` always sets
    /// `Authorization` when `registrationToken`
    /// is configured.
    func enrollPublicKey(_ identity: LocalIdentity) async throws -> RelayEnrollmentResponse {
        guard let crypto = crypto else {
            throw PrivateChatError.relayHTTPError(statusCode: 500, message: "enroll requires CryptoServicing")
        }
        let publicKeyPem = crypto.pemEncodedSigningPublicKey(identity.signingPrivateKey.publicKey)
        let body = RelayEnrollmentRequest(
            peerID: identity.id,
            publicKeyPem: publicKeyPem,
            clientVersion: clientVersion
        )

        var request = try makeRequest(path: "/v1/relay/peers", method: "POST", body: try encoder.encode(body))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try await perform(request)
        let response = try decoder.decode(RelayEnrollmentResponse.self, from: data)
        Self.logger.info(
            "enrolled peer \(response.peerID.prefix(8))… (registrySize=\(response.registrySize))"
        )
        return response
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

    private func makeRequest(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Data? = nil
    ) throws -> URLRequest {
        let baseURL = try validatedBaseURL()
        let pathWithQuery: String
        if queryItems.isEmpty {
            pathWithQuery = path
        } else {
            // URLComponents is used here to
            // build the wire path + canonical
            // query string in two consistent
            // steps. The URL string is what
            // the server will see; the
            // `percentEncodedQuery` is what the
            // relay's `canonicalQueryString`
            // helper produces.
            var components = URLComponents()
            components.path = path
            components.queryItems = queryItems
            pathWithQuery = components.url?.absoluteString ?? path
        }
        guard let endpointURL = URL(string: pathWithQuery, relativeTo: baseURL)?.absoluteURL else {
            throw PrivateChatError.invalidRelayURL
        }
        var request = URLRequest(url: endpointURL)
        request.httpMethod = method.uppercased()
        request.timeoutInterval = 8
        if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        // Sprint 15B: build the four
        // peer-bound headers from the same
        // `method`, `path`, `query`, `body`
        // that we send on the wire. The
        // canonical query string is the
        // percent-encoded, sorted, name-value
        // pair string that the relay's
        // `canonical-query-string` helper
        // produces. The signature is over
        // the assembled canonical string and
        // is verified server-side.
        let signedHeaders: RequestSigner.SignedHeaders? = self.signingContext.flatMap { context in
            let peerID = context.currentPeerID()
            guard let peerID = peerID, peerID.isEmpty == false else {
                return nil
            }
            return RequestSigner.sign(
                method: method,
                path: path,
                queryStringCanonicalized: RequestSigner.canonicalQueryString(
                    from: queryItems
                ),
                body: body,
                timestamp: RequestSigner.currentTimestamp(),
                nonce: RequestSigner.makeNonce(),
                peerID: peerID,
                signingKey: context.currentSigningPrivateKey()
            )
        }
        applyDefaultHeaders(to: &request, signedHeaders: signedHeaders)
        return request
    }

    private func applyDefaultHeaders(
        to request: inout URLRequest,
        signedHeaders: RequestSigner.SignedHeaders? = nil
    ) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Sprint 14B: the legacy
        // `X-PrivateChat-Client` header is replaced
        // with the canonical
        // `X-SecureChat-Client` so the relay's
        // peer-bound-auth and stats counters can
        // group requests by app version. The value
        // still follows the "<app>-<platform>"
        // shape so existing log parsers do not
        // break.
        request.setValue("SecureChat-iOS", forHTTPHeaderField: "X-SecureChat-Client")
        if let registrationToken = configuration.registrationToken, registrationToken.isEmpty == false {
            request.setValue("Bearer \(registrationToken)", forHTTPHeaderField: "Authorization")
        }
        // Sprint 15B (Phase 2): peer-bound
        // request signing. When the
        // `RelayConfiguration` carries an
        // `IdentityManager` (it does in every
        // public-beta build), every request to
        // the `/v1/relay/*` surface carries
        // the four canonical peer-bound
        // headers. The relay will accept
        // unsigned requests in development
        // (counted in the `unsignedRequests`
        // counter) and refuse them in
        // production once
        // `RELAY_REQUIRE_PEER_AUTH=*** is
        // enabled.
        if let headers = signedHeaders {
            request.setValue(headers.peerID, forHTTPHeaderField: "X-Securechat-Peer-ID")
            request.setValue(headers.timestamp, forHTTPHeaderField: "X-Securechat-Timestamp")
            request.setValue(headers.nonce, forHTTPHeaderField: "X-Securechat-Nonce")
            request.setValue(headers.signature, forHTTPHeaderField: "X-Securechat-Signature")
        }
    }

    private func validatedBaseURL() throws -> URL {
        guard configuration.isEnabled else {
            throw PrivateChatError.relayDisabled
        }
        guard let baseURL = normalizedBaseURL() else {
            throw PrivateChatError.relayNotConfigured
        }
        guard let scheme = baseURL.scheme?.lowercased() else {
            throw PrivateChatError.invalidRelayURL
        }
        // Sprint 14C: plain HTTP is forbidden in
        // any non-development build. Dev builds
        // (Xcode debug or simulator) still allow
        // http://localhost.* so local development
        // keeps working. In TestFlight / Release
        // the user agent is `SecureChat-iOS` and
        // the build is non-debug, so the `http`
        // case throws `insecureRelayURL` and the
        // request never leaves the device.
        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif
        if scheme == "http" {
            let isLocalhost = (baseURL.host?.lowercased() ?? "").contains("localhost") ||
                baseURL.host == "127.0.0.1" ||
                baseURL.host == "::1"
            if isDebug && isLocalhost {
                // local dev only
            } else {
                throw PrivateChatError.insecureRelayURL
            }
        } else if scheme != "https" {
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
