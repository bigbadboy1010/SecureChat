import CryptoKit
import Foundation

final class RelayTransport: RelayMessageTransporting {
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
        clientVersion: String? = nil,
        urlSession: URLSession? = nil
    ) {
        self.configuration = configuration
        self.signingContext = signingContext
        self.crypto = crypto
        let marketingVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "unknown"
        let buildVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "unknown"
        self.clientVersion = clientVersion
            ?? "org.francois.PrivateChat/\(marketingVersion)/\(buildVersion)"
        self.urlSession = urlSession ?? RelayTransport.makeDefaultURLSession()
        self.encoder = RelayWireCoding.makeEncoder()
        self.decoder = DateCoding.makeDecoder()
    }

    var isAvailable: Bool {
        configuration.isEnabled && normalizedBaseURL() != nil
    }

    func send(_ packet: OutboundTransportPacket) async throws {
        let body = try encoder.encode(packet)
        let request = try makeRequest(
            path: "/v1/relay/messages",
            method: "POST",
            body: body
        )

        let data = try await perform(request)
        let sendResponse = try decoder.decode(RelaySendResponse.self, from: data)
        guard sendResponse.accepted, sendResponse.packetID == packet.id else {
            throw PrivateChatError.relayInvalidResponse
        }
    }

    func fetchInbox(recipientID: String, limit: Int) async throws -> [OutboundTransportPacket] {
        let queryItems = [
            URLQueryItem(name: "recipientID", value: recipientID),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, RelayWireCoding.maximumInboxBatch))))
        ]

        // Use the common request builder so inbox reads receive the
        // same bearer token + peer-bound Ed25519 signature as writes,
        // ACKs and deletes. Building the GET manually previously
        // omitted X-Securechat-* signing headers and failed as soon
        // as RELAY_REQUIRE_PEER_AUTH was enabled in production.
        let request = try makeRequest(
            path: "/v1/relay/messages",
            method: "GET",
            queryItems: queryItems
        )

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
        let request = try makeRequest(
            path: "/v1/relay/messages/\(packetID.uuidString.lowercased())/ack",
            method: "POST"
        )

        let data = try await perform(request)
        let response = try decoder.decode(RelayDeleteResponse.self, from: data)
        return response.deleted
    }

    private func legacyDelete(packetID: UUID) async throws -> Bool {
        let request = try makeRequest(
            path: "/v1/relay/messages/\(packetID.uuidString.lowercased())",
            method: "DELETE"
        )

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
        let request = try makeRequest(path: "/healthz")

        let data = try await perform(request)
        let status = try decoder.decode(RelayHealthStatus.self, from: data)
        guard status.isHealthy else {
            throw PrivateChatError.relayHealthCheckFailed("Unerwarteter Health-Status: \(status.status)")
        }
        return status
    }

    /// Prove possession of the identity named in the enrollment body.
    /// The server validates the signature against this submitted key before
    /// it admits an approved beta peer. An operator bearer token is optional
    /// for legacy/custom deployments and never substitutes for this proof.
    func enrollPublicKey(_ identity: LocalIdentity) async throws -> RelayEnrollmentResponse {
        guard let crypto = crypto else {
            throw PrivateChatError.relayHTTPError(statusCode: 500, message: "enroll requires CryptoServicing")
        }
        guard signingContext?.currentPeerID() == identity.id,
              signingContext?.currentSigningPrivateKey()?.publicKey.rawRepresentation == identity.signingPublicKeyData else {
            throw PrivateChatError.invalidKeyMaterial
        }
        let publicKeyPem = crypto.pemEncodedSigningPublicKey(identity.signingPrivateKey.publicKey)
        let body = RelayEnrollmentRequest(
            peerID: identity.id,
            publicKeyPem: publicKeyPem,
            clientVersion: clientVersion
        )

        let request = try makeRequest(
            path: "/v1/relay/peers",
            method: "POST",
            body: try encoder.encode(body),
            includePeerSignature: true
        )

        let data = try await perform(request)
        let response = try decoder.decode(RelayEnrollmentResponse.self, from: data)
        guard response.peerID == identity.id else { throw PrivateChatError.relayInvalidResponse }
        return response
    }


    func fetchStats() async throws -> RelayStatsResponse {
        let request = try makeRequest(path: "/v1/relay/stats")

        let data = try await perform(request)
        return try decoder.decode(RelayStatsResponse.self, from: data)
    }

    func purgeInbox(recipientID: String) async throws -> RelayPurgeResponse {
        let body = try encoder.encode(RelayPurgeRequest(recipientID: recipientID))
        let request = try makeRequest(
            path: "/v1/relay/messages/purge",
            method: "POST",
            body: body
        )

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
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }

    private func makeRequest(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        includePeerSignature: Bool = true
    ) throws -> URLRequest {
        let baseURL = try validatedBaseURL()
        guard (body?.count ?? 0) <= RelayWireCoding.maximumHTTPBodyBytes else { throw PrivateChatError.relayInvalidResponse }
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
        let signedHeaders: RequestSigner.SignedHeaders?
        if includePeerSignature, let context = signingContext {
            guard let peerID = context.currentPeerID(), peerID.isEmpty == false,
                  let signingKey = context.currentSigningPrivateKey() else {
                // The production app always wires an IdentityManager as
                // signingContext. If its keychain identity cannot be read,
                // fail before the request leaves the device. Sending an
                // unsigned request or inventing a temporary key would make
                // authentication failures ambiguous and weaken identity
                // binding.
                throw PrivateChatError.invalidKeyMaterial
            }
            signedHeaders = RequestSigner.sign(
                method: method,
                path: path,
                queryStringCanonicalized: RequestSigner.canonicalQueryString(
                    from: queryItems
                ),
                body: body,
                timestamp: RequestSigner.currentTimestamp(),
                nonce: RequestSigner.makeNonce(),
                peerID: peerID,
                signingKey: signingKey
            )
        } else {
            guard !includePeerSignature || !path.hasPrefix("/v1/") || baseURL.scheme == "http" else {
                throw PrivateChatError.invalidKeyMaterial
            }
            signedHeaders = nil
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
        request.setValue("PrivateRoom-iOS", forHTTPHeaderField: "X-SecureChat-Client")
        let isHostedRelay = request.url?.scheme == "https" && request.url?.host?.lowercased() == SecureChatProductionProfile.relayHost && (request.url?.port == nil || request.url?.port == 443)
        if !isHostedRelay, let registrationToken = configuration.registrationToken, registrationToken.isEmpty == false {
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
        // exact loopback addresses so local development
        // keeps working. In TestFlight / Release
        // the user agent is `PrivateRoom-iOS` and
        // the build is non-debug, so the `http`
        // case throws `insecureRelayURL` and the
        // request never leaves the device.
        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif
        if scheme == "http" {
            let isLocalhost = baseURL.host?.lowercased() == "localhost" ||
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
        guard let host = baseURL.host?.lowercased(), host.isEmpty == false,
              baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil else {
            throw PrivateChatError.invalidRelayURL
        }

        if let token = configuration.registrationToken, !token.isEmpty,
           SecureChatProductionProfile.isUsableClientToken(token) == false {
            throw PrivateChatError.relayMissingClientToken
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
        do {
            let (bytes, response) = try await urlSession.bytes(for: request, delegate: RelayRedirectBlocker())
            defer { bytes.task.cancel() }
            let maximumResponseBytes = 8 * 1_048_576
            guard response.expectedContentLength <= Int64(maximumResponseBytes) else {
                throw PrivateChatError.relayInvalidResponse
            }
            var data = Data()
            for try await byte in bytes {
                guard data.count < maximumResponseBytes else { throw PrivateChatError.relayInvalidResponse }
                data.append(byte)
            }
            try validate(response: response, data: data)
            return data
        } catch let error as PrivateChatError {
            throw error
        } catch let urlError as URLError {
            throw map(urlError, request: request)
        } catch {
            // URLs, peer identifiers, server text and private configuration do
            // not belong in persistent device logs or support diagnostics.
            throw PrivateChatError.relayRequestFailed("Die sichere Verbindung konnte nicht abgeschlossen werden.")
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
              let error = dictionary["error"] as? String,
              error.range(of: "^[a-zA-Z0-9_.-]{1,64}$", options: .regularExpression) != nil else {
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

/// A signed request is valid for its original method/path only. Following any
/// redirect could disclose the encrypted envelope or identity to another URL.
private final class RelayRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
