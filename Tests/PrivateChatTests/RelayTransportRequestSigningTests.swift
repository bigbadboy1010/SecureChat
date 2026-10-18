import CryptoKit
import Foundation
import XCTest
@testable import PrivateChat

@MainActor
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
            sealedPayloadBase64: "////",
            signatureBase64: "c2lnbmF0dXJl",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_700_086_400)
        )

        RelayURLProtocolStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/relay/messages")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(Self.token)")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = try Self.transmittedBody(request)
            let timestamp = try XCTUnwrap(request.value(forHTTPHeaderField: "X-Securechat-Timestamp"))
            let nonce = try XCTUnwrap(request.value(forHTTPHeaderField: "X-Securechat-Nonce"))
            let signatureBase64URL = try XCTUnwrap(
                request.value(forHTTPHeaderField: "X-Securechat-Signature")
            )
            let signature = try XCTUnwrap(Data(base64URLEncoded: signatureBase64URL))
            XCTAssertNotNil(ISO8601DateFormatter().date(from: timestamp))
            XCTAssertEqual(try XCTUnwrap(Data(base64URLEncoded: nonce)).count, 16)
            XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("\\/"))
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

    func testEnrollmentProvesPossessionOfSubmittedSigningKey() async throws {
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
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Securechat-Peer-ID"), peerID)
            let body = try Self.transmittedBody(request)
            let timestamp = try XCTUnwrap(request.value(forHTTPHeaderField: "X-Securechat-Timestamp"))
            let nonce = try XCTUnwrap(request.value(forHTTPHeaderField: "X-Securechat-Nonce"))
            let signature = try XCTUnwrap(Data(base64URLEncoded: try XCTUnwrap(request.value(forHTTPHeaderField: "X-Securechat-Signature"))))
            let canonical = RequestSigner.canonicalString(method: "POST", path: "/v1/relay/peers", queryStringCanonicalized: "", body: body, timestamp: timestamp, nonce: nonce, peerID: peerID)
            XCTAssertTrue(signingKey.publicKey.isValidSignature(signature, for: Data(canonical.utf8)))

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

    func testCanonicalEnrollmentWorksWithoutAnOperatorToken() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let peerID = RequestSigner.sha256Hex(key.publicKey.rawRepresentation)
        let identity = LocalIdentity(id: peerID, displayName: "Owned fixture", keyAgreementPrivateKey: .init(), signingPrivateKey: key)
        RelayURLProtocolStub.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Securechat-Peer-ID"), peerID)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Securechat-Client"), "PrivateRoom-iOS")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{\"peerID\":\"\(peerID)\",\"registeredAt\":1700000000000,\"registrySize\":1}".utf8))
        }
        let transport = RelayTransport(configuration: .init(isEnabled: true, baseURLString: "https://securechat.team", registrationToken: Self.token), signingContext: FixedPeerBoundSigningContext(peerID: peerID, signingKey: key), crypto: CryptoService(), urlSession: makeStubbedSession())
        let result = try await transport.enrollPublicKey(identity)
        XCTAssertEqual(result.peerID, peerID)
    }

    func testSlashHeavyFullAttachmentChunkAndMaximumCaptionCanBeSent() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let peerID = RequestSigner.sha256Hex(key.publicKey.rawRepresentation)
        let chunk = Data(repeating: 255, count: 65_536)
        let payload = TransportMessagePayload(version: 3, kind: .attachmentChunk, messageID: UUID(), conversationID: UUID(), senderID: peerID, recipientID: String(repeating: "b", count: 64), body: "x" + String(repeating: "\n", count: 16_382) + "x", createdAt: Date(timeIntervalSince1970: 1_800_000_000), deliveredMessageID: nil, attachment: ChatAttachment(id: UUID(), kind: .document, fileName: "fixture.bin", mimeType: "application/octet-stream", byteCount: chunk.count), attachmentSHA256: RequestSigner.sha256Hex(chunk), chunkIndex: 0, totalChunks: 1, chunkDataBase64: chunk.base64EncodedString())
        let plaintext = try RelayWireCoding.makeEncoder().encode(payload)
        XCTAssertFalse(String(decoding: plaintext, as: UTF8.self).contains("\\/"))
        let sealed = try AES.GCM.seal(plaintext, using: SymmetricKey(size: .bits256)).combined!
        XCTAssertLessThanOrEqual(sealed.count, RelayWireCoding.maximumSealedPayloadBytes)
        let packet = OutboundTransportPacket(id: UUID(), senderID: peerID, recipientID: payload.recipientID, sealedPayloadBase64: sealed.base64EncodedString(), signatureBase64: Data(repeating: 1, count: 64).base64EncodedString(), createdAt: Date(timeIntervalSince1970: 1_800_000_000), expiresAt: Date(timeIntervalSince1970: 1_800_086_400))
        RelayURLProtocolStub.handler = { request in
            let transmitted = try Self.transmittedBody(request)
            XCTAssertGreaterThan(transmitted.count, 65_536, "This catches the old request-cap regression")
            XCTAssertLessThanOrEqual(transmitted.count, 262_144)
            return (HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!, Data("{\"accepted\":true,\"packetID\":\"\(packet.id.uuidString)\"}".utf8))
        }
        let transport = RelayTransport(configuration: configuration, signingContext: FixedPeerBoundSigningContext(peerID: peerID, signingKey: key), urlSession: makeStubbedSession())
        try await transport.send(packet)
    }

    func testDifferentEnrollmentIdentityFailsBeforeNetwork() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let peerID = RequestSigner.sha256Hex(key.publicKey.rawRepresentation)
        let wrongIdentity = LocalIdentity(id: "wrong", displayName: "Fixture", keyAgreementPrivateKey: .init(), signingPrivateKey: .init())
        RelayURLProtocolStub.handler = { _ in XCTFail("Identity mismatch must never leave the device"); throw URLError(.badURL) }
        let transport = RelayTransport(configuration: configuration, signingContext: FixedPeerBoundSigningContext(peerID: peerID, signingKey: key), crypto: CryptoService(), urlSession: makeStubbedSession())
        do { _ = try await transport.enrollPublicKey(wrongIdentity); XCTFail("Expected rejection") } catch {}
    }

    func testUnsignedHTTPSInboxFailsBeforeNetwork() async throws {
        RelayURLProtocolStub.handler = { _ in XCTFail("No unsigned production inbox request"); throw URLError(.badURL) }
        let transport = RelayTransport(configuration: configuration, urlSession: makeStubbedSession())
        do { _ = try await transport.fetchInbox(recipientID: String(repeating: "a", count: 64), limit: 10); XCTFail("Expected rejection") } catch {}
    }

    func testLargeConfiguredInboxBatchesRespectTheBoundedResponseBudget() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let peerID = RequestSigner.sha256Hex(key.publicKey.rawRepresentation)
        RelayURLProtocolStub.handler = { request in
            let parameters = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(parameters?.first(where: { $0.name == "limit" })?.value, "40")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Securechat-Peer-ID"), peerID)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{\"packets\":[]}".utf8))
        }
        let transport = RelayTransport(configuration: configuration, signingContext: FixedPeerBoundSigningContext(peerID: peerID, signingKey: key), urlSession: makeStubbedSession())
        let packets = try await transport.fetchInbox(recipientID: peerID, limit: 100)
        XCTAssertTrue(packets.isEmpty)
    }

    func testHostNamesContainingLocalhostAndCredentialURLsCannotBypassTransportPolicy() async throws {
        RelayURLProtocolStub.handler = { _ in XCTFail("Invalid URL must never receive a request"); throw URLError(.badURL) }
        for value in ["http://localhost.attacker.test", "http://attacker-localhost.test", "http://192.168.178.41", "https://username:password@securechat.test", "https://securechat.test?token=fixture", "https://securechat.test#fixture"] {
            let transport = RelayTransport(configuration: .init(isEnabled: true, baseURLString: value, registrationToken: nil), urlSession: makeStubbedSession())
            do { _ = try await transport.checkHealth(); XCTFail("Expected rejection of \(value)") } catch {}
        }
    }

    func testAdvertisedOversizeResponseFailsBeforeDecoding() async throws {
        RelayURLProtocolStub.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": "9000000"])!, Data("{\"status\":\"ok\"}".utf8))
        }
        let transport = RelayTransport(configuration: configuration, urlSession: makeStubbedSession())
        do { _ = try await transport.checkHealth(); XCTFail("Expected size rejection") } catch {}
    }

    func testServerErrorsDoNotExposeArbitraryResponseText() async throws {
        RelayURLProtocolStub.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!, Data("{\"error\":\"private recipient / internal-path fixture\"}".utf8))
        }
        let transport = RelayTransport(configuration: configuration, urlSession: makeStubbedSession())
        do { _ = try await transport.checkHealth(); XCTFail("Expected error") }
        catch { XCTAssertFalse(error.localizedDescription.contains("internal-path")); XCTAssertFalse(error.localizedDescription.contains("recipient")) }
    }

    func testOlmPublicationAndClaimSignExactTransmittedBodies() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let identity = LocalIdentity(id:RequestSigner.sha256Hex(key.publicKey.rawRepresentation),displayName:"Synthetic wire peer",keyAgreementPrivateKey:.init(),signingPrivateKey:key)
        let owner = try SyntheticOlmPeer(identity)
        let remote = try SyntheticOlmPeer(LocalIdentity(id:String(repeating:"b",count:64),displayName:"Synthetic remote",keyAgreementPrivateKey:.init(),signingPrivateKey:.init()))
        let claimID = UUID()
        RelayURLProtocolStub.handler = { request in
            let body = try Self.transmittedBody(request)
            try Self.assertSigned(request,key:key,peerID:identity.id,body:body)
            XCTAssertFalse(String(decoding:body,as:UTF8.self).contains("\\/"))
            let fields = try XCTUnwrap(JSONSerialization.jsonObject(with:body) as? [String:Any])
            let response: Data
            if request.httpMethod == "PUT" {
                XCTAssertEqual(request.url?.path,"/v1/relay/prekeys")
                XCTAssertEqual(fields["identity"] as? String,owner.batch.identity)
                XCTAssertEqual((fields["keys"] as? [Any])?.count,50)
                XCTAssertNil(fields["peerID"])
                response = Data("{\"saved\":true}".utf8)
            } else {
                XCTAssertEqual(request.url?.path,"/v1/relay/prekeys/claim")
                XCTAssertEqual(fields["recipientID"] as? String,remote.identity.id)
                XCTAssertEqual(fields["claimID"] as? String,claimID.uuidString.lowercased())
                response = try DateCoding.makeEncoder().encode(remote.claim(requester:identity.id,claimID:claimID))
            }
            return (HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,response)
        }
        let transport = RelayTransport(configuration:configuration,signingContext:FixedPeerBoundSigningContext(peerID:identity.id,signingKey:key),urlSession:makeStubbedSession())
        try await transport.publishOlmPrekeys(owner.batch)
        let result = try await transport.claimOlmPrekey(recipientID:remote.identity.id,claimID:claimID)
        XCTAssertEqual(result.prekey,remote.batch.keys[0])
    }
    func testPrekeyAvailabilityUsesSignedOwnerGetWithoutForeignIdentityQuery() async throws {
        let key=Curve25519.Signing.PrivateKey(),id=RequestSigner.sha256Hex(key.publicKey.rawRepresentation)
        RelayURLProtocolStub.handler = { request in
            XCTAssertEqual(request.httpMethod,"GET");XCTAssertEqual(request.url?.path,"/v1/relay/prekeys");XCTAssertNil(request.url?.query)
            try Self.assertSigned(request,key:key,peerID:id,body:Data())
            return (HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,Data("{\"identity\":null,\"sequence\":0,\"available\":0}".utf8))
        }
        let transport=RelayTransport(configuration:configuration,signingContext:FixedPeerBoundSigningContext(peerID:id,signingKey:key),urlSession:makeStubbedSession())
        let status=try await transport.olmPrekeyStatus();XCTAssertEqual(status.available,0);XCTAssertNil(status.identity)
    }
    func testConsentAndNeutralPushUseSignedOwnerRequests() async throws {
        let key = Curve25519.Signing.PrivateKey(),id = RequestSigner.sha256Hex(key.publicKey.rawRepresentation)
        let expiry = ISO8601DateFormatter().string(from:Date().addingTimeInterval(1000))
        let consent = RelayRecipientConsent(recipientID:id,senderIDs:[String(repeating:"b",count:64)],updatedAt:ISO8601DateFormatter().string(from:Date()),expiresAt:expiry)
        RelayURLProtocolStub.handler = { request in
            let body = try Self.transmittedBody(request);try Self.assertSigned(request,key:key,peerID:id,body:body)
            XCTAssertEqual(request.httpMethod,"PUT")
            let fields = try XCTUnwrap(JSONSerialization.jsonObject(with:body) as? [String:Any])
            let response:String
            if request.url?.path == "/v1/relay/contacts" {
                XCTAssertEqual(fields["recipientID"] as? String,id)
                response = "{\"saved\":true,\"expiresAt\":\"\(expiry)\"}"
            } else {
                XCTAssertEqual(request.url?.path,"/v1/relay/push")
                XCTAssertNil(fields["message"]);XCTAssertNil(fields["senderID"])
                if fields["enabled"] as? Bool == false { XCTAssertEqual(fields.count,1);XCTAssertNil(fields["token"]) }
                response = "{\"saved\":true}"
            }
            return (HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,Data(response.utf8))
        }
        let transport = RelayTransport(configuration:configuration,signingContext:FixedPeerBoundSigningContext(peerID:id,signingKey:key),urlSession:makeStubbedSession())
        try await transport.replaceRecipientConsent(consent)
        try await transport.configureNeutralPush(enabled:true,token:String(repeating:"c",count:64),environment:"production")
        try await transport.configureNeutralPush(enabled:false,token:nil,environment:"production")
    }
    func testPaginationSignsCursorAndRejectsNonAdvancingOrMalformedCursor() async throws {
        let key = Curve25519.Signing.PrivateKey(),id = RequestSigner.sha256Hex(key.publicKey.rawRepresentation)
        let after = "00000000-0000-4000-8000-000000000001"
        RelayURLProtocolStub.handler = { request in
            let items = URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!
            XCTAssertEqual(items.first(where:{$0.name=="after"})?.value,after)
            let signature = try XCTUnwrap(Data(base64URLEncoded:request.value(forHTTPHeaderField:"X-Securechat-Signature")!))
            let canonical = RequestSigner.canonicalString(method:"GET",path:"/v1/relay/messages",queryStringCanonicalized:RequestSigner.canonicalQueryString(from: items),body:nil,timestamp:request.value(forHTTPHeaderField:"X-Securechat-Timestamp")!,nonce:request.value(forHTTPHeaderField:"X-Securechat-Nonce")!,peerID:id)
            XCTAssertTrue(key.publicKey.isValidSignature(signature,for:Data(canonical.utf8)))
            return (HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,Data("{\"packets\":[],\"nextCursor\":\"\(after)\"}".utf8))
        }
        let transport = RelayTransport(configuration:configuration,signingContext:FixedPeerBoundSigningContext(peerID:id,signingKey:key),urlSession:makeStubbedSession())
        do { _ = try await transport.fetchInboxPage(recipientID:id,limit:40,after:after);XCTFail("Non-advancing cursor accepted") }
        catch { XCTAssertEqual(error as? PrivateChatError,.relayInvalidResponse) }
        do { _ = try await transport.fetchInboxPage(recipientID:id,limit:40,after:"invalid");XCTFail("Malformed cursor accepted") }
        catch { XCTAssertEqual(error as? PrivateChatError,.relayInvalidResponse) }
    }
    func testRetryAfterSecondsAndHTTPDateAreHonoredByTransport() async throws {
        let key = Curve25519.Signing.PrivateKey(),id = RequestSigner.sha256Hex(key.publicKey.rawRepresentation)
        let formatter = DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.timeZone=TimeZone(secondsFromGMT:0);formatter.dateFormat="EEE, dd MMM yyyy HH:mm:ss z"
        for header in ["120",formatter.string(from:Date().addingTimeInterval(180))] {
            RelayURLProtocolStub.handler = { request in
                (HTTPURLResponse(url:request.url!,statusCode:429,httpVersion:nil,headerFields:["Retry-After":header])!,Data("{\"error\":\"device_rate_limit\"}".utf8))
            }
            let transport = RelayTransport(configuration:configuration,signingContext:FixedPeerBoundSigningContext(peerID:id,signingKey:key),urlSession:makeStubbedSession())
            do { _ = try await transport.fetchInboxPage(recipientID:id,limit:40,after:nil);XCTFail("Expected backoff") }
            catch PrivateChatError.relayBackoff(let status,let seconds,_) { XCTAssertEqual(status,429);XCTAssertGreaterThanOrEqual(seconds,120);XCTAssertLessThanOrEqual(seconds,180) }
        }
    }
    nonisolated private static func assertSigned(_ request:URLRequest,key:Curve25519.Signing.PrivateKey,peerID:String,body:Data) throws {
        let signature = try XCTUnwrap(Data(base64URLEncoded:request.value(forHTTPHeaderField:"X-Securechat-Signature")!))
        let canonical = RequestSigner.canonicalString(method:request.httpMethod!,path:request.url!.path,queryStringCanonicalized:"",body:body,timestamp:request.value(forHTTPHeaderField:"X-Securechat-Timestamp")!,nonce:request.value(forHTTPHeaderField:"X-Securechat-Nonce")!,peerID:peerID)
        XCTAssertTrue(key.publicKey.isValidSignature(signature,for:Data(canonical.utf8)))
    }

    nonisolated private static func transmittedBody(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
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
    init?(base64URLEncoded value: String) {
        let normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = normalized + String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        self.init(base64Encoded: padded)
    }
}
