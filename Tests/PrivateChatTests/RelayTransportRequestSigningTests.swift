import CryptoKit
import Foundation
import XCTest
@testable import PrivateChat

final class RelayTransportRequestSigningTests: XCTestCase {
    override func tearDown() {
        RelayURLProtocolStub.handler = nil
        super.tearDown()
    }

    func testSendSignsFinalPostMethodAndEncodedBody() async throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let peerID = RequestSigner.sha256Hex(signingKey.publicKey.rawRepresentation)
        let context = FixedPeerBoundSigningContext(peerID: peerID, signingKey: signingKey)
        let packetID = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let packet = OutboundTransportPacket(
            id: packetID,
            senderID: peerID,
            recipientID: String(repeating: "b", count: 64),
            sealedPayloadBase64: "c2VhbGVk",
            signatureBase64: "c2lnbmF0dXJl",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_700_086_400)
        )

        RelayURLProtocolStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/relay/messages")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(Self.token)")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = try XCTUnwrap(request.httpBody)
            let timestamp = try XCTUnwrap(request.value(forHTTPHeaderField: "X-Securechat-Timestamp"))
            let nonce = try XCTUnwrap(request.value(forHTTPHeaderField: "X-Securechat-Nonce"))
            let signatureHex = try XCTUnwrap(request.value(forHTTPHeaderField: "X-Securechat-Signature"))
            let signature = try XCTUnwrap(Data(hexString: signatureHex))
            let canonical = RequestSigner.canonicalString(
                method: "POST",
                path: "/v1/relay/messages",
                queryStringCanonicalized: "",
                body: body,
                timestamp: timestamp,
                nonce: nonce,
                peerID: peerID
            )
            XCTAssertTrue(
                signingKey.publicKey.isValidSignature(signature, for: Data(canonical.utf8)),
                "The signature must cover the final POST method and the exact transmitted body."
            )

            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 202,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let data = Data("{\"accepted\":true,\"packetID\":\"\(packetID.uuidString)\"}".utf8)
            return (response, data)
        }

        let transport = RelayTransport(
            configuration: configuration,
            signingContext: context,
            urlSession: makeStubbedSession()
        )

        try await transport.send(packet)
    }

    func testEnrollmentUsesBearerTokenWithoutPeerSignatureHeaders() async throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let peerID = RequestSigner.sha256Hex(signingKey.publicKey.rawRepresentation)
        let identity = LocalIdentity(
            id: peerID,
            displayName: "Test Device",
            keyAgreementPrivateKey: Curve25519.KeyAgreement.PrivateKey(),
            signingPrivateKey: signingKey
        )
        let context = FixedPeerBoundSigningContext(peerID: peerID, signingKey: signingKey)

        RelayURLProtocolStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/relay/peers")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(Self.token)")
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Securechat-Peer-ID"))
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Securechat-Timestamp"))
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Securechat-Nonce"))
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Securechat-Signature"))

            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let data = Data(
                "{\"peerID\":\"\(peerID)\",\"registeredAt\":1700000000000,\"registrySize\":3}".utf8
            )
            return (response, data)
        }

        let transport = RelayTransport(
            configuration: configuration,
            signingContext: context,
            crypto: CryptoService(),
            clientVersion: "org.francois.PrivateChat/test/1",
            urlSession: makeStubbedSession()
        )

        let response = try await transport.enrollPublicKey(identity)
        XCTAssertEqual(response.peerID, peerID)
        XCTAssertEqual(response.registrySize, 3)
    }

    private static let token = String(repeating: "a", count: 64)

    private var configuration: RelayConfiguration {
        RelayConfiguration(
            isEnabled: true,
            baseURLString: "https://securechat.test",
            registrationToken: Self.token
        )
    }

    private func makeStubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RelayURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}

private final class FixedPeerBoundSigningContext: PeerBoundSigningContext {
    private let peerID: String
    private let signingKey: Curve25519.Signing.PrivateKey

    init(peerID: String, signingKey: Curve25519.Signing.PrivateKey) {
        self.peerID = peerID
        self.signingKey = signingKey
    }

    func currentPeerID() -> String? {
        peerID
    }

    func currentSigningPrivateKey() -> Curve25519.Signing.PrivateKey? {
        signingKey
    }
}

private final class RelayURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else {
            return nil
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex

        while index < hexString.endIndex {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = nextIndex
        }

        self.init(bytes)
    }
}
