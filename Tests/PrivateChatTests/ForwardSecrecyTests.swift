import CryptoKit
import XCTest
@testable import PrivateChat

@MainActor
final class ForwardSecrecyTests: XCTestCase {
    private func peer(_ name: String) throws -> SyntheticOlmPeer {
        let crypto = CryptoService(), signing = Curve25519.Signing.PrivateKey()
        return try SyntheticOlmPeer(LocalIdentity(id: crypto.peerID(publicKeyData: signing.publicKey.rawRepresentation), displayName: name, keyAgreementPrivateKey: .init(), signingPrivateKey: signing))
    }
    private func payload(_ a: SyntheticOlmPeer, _ b: SyntheticOlmPeer, kind: TransportPayloadKind = .message, body: String = "Synthetic privacy test", id: UUID = UUID(), createdAt: Date = Date()) -> TransportMessagePayload {
        TransportMessagePayload(version: 3, kind: kind, messageID: id, conversationID: UUID(), senderID: a.identity.id, recipientID: b.identity.id, body: body, createdAt: createdAt, deliveredMessageID: kind == .deliveryReceipt ? id : nil)
    }
    private func restarted(_ p: SyntheticOlmPeer) throws -> ForwardSecretService {
        let crypto = ForwardSecretService(store: p.storage, local: p.identity); try crypto.load(); return crypto
    }
    func testRestartReusesEntireCiphertextAndSignatureWithoutAdvancingRatchet() throws {
        let a = try peer("A"), b = try peer("B"), message = payload(a,b)
        let packet = try a.packet(to: b, payload: message)
        let before = a.storage.data
        let afterRestart = try restarted(a).makePacket(payload: message, recipientID: b.identity.id, packetID: packet.id)
        XCTAssertEqual(packet.protocolVersion, 4)
        XCTAssertEqual(packet, afterRestart)
        XCTAssertEqual(before, a.storage.data)
        XCTAssertTrue(a.identity.signingPrivateKey.publicKey.isValidSignature(Data(base64Encoded: packet.signatureBase64)!, for: packet.authenticatedData))
    }
    func testCrashBetweenCryptoCommitAndMessageAppendCanRecoverWithoutConsumedMessageKey() throws {
        let a = try peer("A"), b = try peer("B")
        let packet = try a.packet(to: b, payload: payload(a,b))
        let plaintext = try b.crypto.receive(packet, peer: b.trustedPeer(a.identity))
        let restored = try restarted(b)
        XCTAssertEqual(try restored.receive(packet, peer: b.trustedPeer(a.identity)), plaintext, "Durable inbox journal must survive a failed history write / process death")
        try restored.acknowledged(packetID: packet.id)
        let postAck = try restarted(b)
        XCTAssertThrowsError(try postAck.receive(packet, peer: b.trustedPeer(a.identity)), "After journal cleanup the consumed message key must be gone")
        // Long-term identity + remaining OTKs cannot reconstruct the old session.
        let stored = try XCTUnwrap(b.storage.data)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: stored) as? [String: Any])
        var engine = try XCTUnwrap(JSONSerialization.jsonObject(with: Data((root["engine"] as! String).utf8)) as? [String: Any])
        engine["peers"] = [:]
        let wire = try DateCoding.makeDecoder().decode(OlmWireEnvelope.self, from: Data(base64Encoded: packet.sealedPayloadBase64)!)
        XCTAssertThrowsError(try OlmBridge.execute("decrypt", state: String(decoding: JSONSerialization.data(withJSONObject: engine), as: UTF8.self), parameters: ["peer":a.identity.id,"identity":wire.identity,"session_id":wire.sessionID,"message":["type":wire.message.type,"body":wire.message.body]]))
    }
    func testOfflineReorderingReplayAndRestartAcrossBothDirections() throws {
        let a = try peer("A"), b = try peer("B")
        let first = try a.packet(to: b, payload: payload(a,b,body:"one"))
        let second = try a.packet(to: b, payload: payload(a,b,body:"two"))
        XCTAssertEqual(try DateCoding.makeDecoder().decode(TransportMessagePayload.self, from: b.crypto.receive(second, peer: b.trustedPeer(a.identity))).body,"two")
        let bRestarted = try restarted(b)
        XCTAssertEqual(try DateCoding.makeDecoder().decode(TransportMessagePayload.self, from: bRestarted.receive(first, peer: b.trustedPeer(a.identity))).body,"one")
        try bRestarted.acknowledged(packetID: first.id)
        XCTAssertThrowsError(try bRestarted.receive(first, peer: b.trustedPeer(a.identity)))
        let reply = try bRestarted.makePacket(payload: payload(b,a,body:"reply"), recipientID:a.identity.id, packetID:UUID())
        XCTAssertEqual(try DateCoding.makeDecoder().decode(TransportMessagePayload.self, from: a.crypto.receive(reply, peer: a.trustedPeer(b.identity))).body,"reply")
    }
    func testSimultaneousFirstMessagesConvergeAndKeepBothSessions() throws {
        let a = try peer("A"), b = try peer("B")
        let ab = try a.packet(to:b,payload:payload(a,b)), ba = try b.packet(to:a,payload:payload(b,a))
        _ = try a.crypto.receive(ba, peer: a.trustedPeer(b.identity)); _ = try b.crypto.receive(ab, peer: b.trustedPeer(a.identity))
        for _ in 0..<6 {
            let left = try a.crypto.makePacket(payload:payload(a,b),recipientID:b.identity.id,packetID:UUID())
            _ = try b.crypto.receive(left, peer: b.trustedPeer(a.identity))
            let right = try b.crypto.makePacket(payload:payload(b,a),recipientID:a.identity.id,packetID:UUID())
            _ = try a.crypto.receive(right, peer: a.trustedPeer(b.identity))
        }
    }
    func testInvalidCiphertextOrHeaderCannotAdvanceDurableState() throws {
        let a = try peer("A"), b = try peer("B")
        let packet = try a.packet(to:b,payload:payload(a,b))
        let before = b.storage.data
        var wire = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(base64Encoded:packet.sealedPayloadBase64)!) as? [String:Any])
        var message = wire["message"] as! [String:Any]
        var bytes = Array(Data(base64Encoded: (message["body"] as! String) + String(repeating:"=",count:(4-(message["body"] as! String).count%4)%4))!)
        bytes[bytes.count-1] ^= 1; message["body"] = Data(bytes).base64EncodedString().replacingOccurrences(of:"=",with:""); wire["message"] = message
        let bad = OutboundTransportPacket(protocolVersion:4,id:packet.id,senderID:packet.senderID,recipientID:packet.recipientID,sealedPayloadBase64:try JSONSerialization.data(withJSONObject:wire).base64EncodedString(),signatureBase64:packet.signatureBase64,createdAt:packet.createdAt,expiresAt:packet.expiresAt)
        XCTAssertThrowsError(try b.crypto.receive(bad, peer: b.trustedPeer(a.identity))); XCTAssertEqual(before,b.storage.data)
        _ = try b.crypto.receive(packet, peer: b.trustedPeer(a.identity))
    }
    func testIdentitySubstitutionOrUnsignedPrekeyCannotEstablishSession() throws {
        let a = try peer("A"), b = try peer("B"), eve = try peer("Eve")
        let id = try a.crypto.claimID(peerID:b.identity.id)
        let forged = OlmPrekeyClaim(requester:a.identity.id,recipientID:b.identity.id,claimID:id,identity:eve.batch.identity,identitySignatureBase64:b.batch.identitySignatureBase64,prekey:eve.batch.keys[0])
        XCTAssertThrowsError(try a.crypto.acceptClaim(forged,peer:a.trustedPeer(b.identity)))
        try a.crypto.acceptClaim(b.claim(requester:a.identity.id,claimID:id),peer:a.trustedPeer(b.identity))
        let next = try a.crypto.claimID(peerID:b.identity.id)
        let changed = OlmPrekeyClaim(requester:a.identity.id,recipientID:b.identity.id,claimID:next,identity:eve.batch.identity,identitySignatureBase64:try b.identity.signingPrivateKey.signature(for:OlmCommitment.data(["PrivateRoom/OlmIdentity/v1",b.identity.id,eve.batch.identity])).base64EncodedString(),prekey:OlmPrekey(id:eve.batch.keys[0].id,key:eve.batch.keys[0].key,expiresAt:eve.batch.keys[0].expiresAt,signatureBase64:try b.identity.signingPrivateKey.signature(for:OlmCommitment.data(["PrivateRoom/OlmPrekey/v1",b.identity.id,eve.batch.identity,eve.batch.keys[0].id,eve.batch.keys[0].key,eve.batch.keys[0].expiresAt])).base64EncodedString()))
        XCTAssertThrowsError(try a.crypto.acceptClaim(changed,peer:a.trustedPeer(b.identity)))
    }
    func testMissingOrCorruptedEncryptedStoreCannotRegenerateAccount() throws {
        let directory = try TestDirectoryFactory.make()
        defer { try? FileManager.default.removeItem(at:directory) }
        let keychain = MockKeychainStore(), a = try peer("A")
        let store = try EncryptedForwardSecretStore(keychain:keychain,storageDirectoryURL:directory)
        let service = ForwardSecretService(store:store,local:a.identity);try service.load()
        let file = directory.appendingPathComponent("forward-secrecy.store")
        let encrypted = try Data(contentsOf:file)
        XCTAssertNil(String(data:encrypted,encoding:.utf8),"Secret pickles must never be plaintext files")
        XCTAssertEqual(try file.resourceValues(forKeys:[.isExcludedFromBackupKey]).isExcludedFromBackup,true)
        try Data([1,2,3]).write(to:file)
        XCTAssertThrowsError(try ForwardSecretService(store:store,local:a.identity).load())
        try FileManager.default.removeItem(at:file)
        XCTAssertThrowsError(try ForwardSecretService(store:store,local:a.identity).load())
    }
    func testPersistenceFailureDoesNotReleaseCiphertextAndBlocksFurtherUse() throws {
        let a = try peer("A"), b = try peer("B"), disk = FailingOlmStore()
        disk.data = a.storage.data
        let service = ForwardSecretService(store:disk,local:a.identity);try service.load()
        let id = try service.claimID(peerID:b.identity.id)
        try service.acceptClaim(b.claim(requester:a.identity.id,claimID:id),peer:a.trustedPeer(b.identity))
        let before = disk.data; disk.fail = true
        XCTAssertThrowsError(try service.makePacket(payload:payload(a,b),recipientID:b.identity.id,packetID:UUID()))
        XCTAssertTrue(service.blocked); XCTAssertEqual(disk.data,before)
        disk.fail = false
        XCTAssertThrowsError(try service.publicationIfNeeded(),"A failed crypto transaction requires recovery / restart, not a live fallback")
    }
    func testInvalidSignatureOrUnverifiedTrustCannotReadCachedJournal() throws {
        let a = try peer("A"), b = try peer("B")
        let packet = try a.packet(to: b, payload: payload(a,b))
        _ = try b.crypto.receive(packet, peer: b.trustedPeer(a.identity))
        let before = b.storage.data
        let invalid = OutboundTransportPacket(protocolVersion:4,id:packet.id,senderID:packet.senderID,recipientID:packet.recipientID,
            sealedPayloadBase64:packet.sealedPayloadBase64,signatureBase64:Data(repeating:0,count:64).base64EncodedString(),createdAt:packet.createdAt,expiresAt:packet.expiresAt)
        XCTAssertThrowsError(try b.crypto.receive(invalid, peer: b.trustedPeer(a.identity)))
        var unverified = b.trustedPeer(a.identity); unverified.trustState = .unverified
        XCTAssertThrowsError(try b.crypto.receive(packet, peer: unverified))
        XCTAssertEqual(before,b.storage.data)
    }
    func testRevokedPendingJournalIsDiscardedWithoutRestoringConsumedMessageKey() throws {
        let a = try peer("A"), b = try peer("B")
        let packet = try a.packet(to:b,payload:payload(a,b))
        _ = try b.crypto.receive(packet,peer:b.trustedPeer(a.identity))
        try b.crypto.discardPendingInbound(peerID:a.identity.id)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with:XCTUnwrap(b.storage.data)) as? [String:Any])
        XCTAssertEqual((root["inbound"] as? [String:Any])?.count,0)
        XCTAssertThrowsError(try restarted(b).receive(packet,peer:b.trustedPeer(a.identity)))
    }
    func testEmptyRelayPoolCanRefillWithoutResetAndRollbackOrIdentitySubstitutionFailsClosed() throws {
        let a = try peer("A")
        XCTAssertNil(try a.crypto.publicationIfNeeded())
        let next = try XCTUnwrap(a.crypto.publicationIfNeeded(serverStatus:OlmPrekeyStatus(identity:nil,sequence:0,available:0)))
        XCTAssertEqual(next.identity,a.batch.identity)
        XCTAssertEqual(next.sequence,a.batch.sequence+1)
        XCTAssertTrue(Set(next.keys.map(\.key)).isDisjoint(with:Set(a.batch.keys.map(\.key))))
        try a.crypto.publicationAccepted(next)
        XCTAssertNil(try a.crypto.publicationIfNeeded(serverStatus:OlmPrekeyStatus(identity:next.identity,sequence:next.sequence,available:50)))
        let before = a.storage.data
        XCTAssertThrowsError(try a.crypto.publicationIfNeeded(serverStatus:OlmPrekeyStatus(identity:next.identity,sequence:next.sequence+1,available:0)))
        XCTAssertThrowsError(try a.crypto.publicationIfNeeded(serverStatus:OlmPrekeyStatus(identity:String(repeating:"A",count:43),sequence:next.sequence,available:0)))
        XCTAssertEqual(before,a.storage.data)
    }
    func testMaximumAttachmentChunkFitsRelayWireLimitWithOlmOverhead() throws {
        let a = try peer("A"), b = try peer("B"), bytes = Data(repeating:42,count:65_536),id = UUID(),now=Date()
        let attachment = ChatAttachment(id:UUID(),kind:.document,fileName:"fixture.bin",mimeType:"application/octet-stream",byteCount:65_536)
        let p = TransportMessagePayload(version:3,kind:.attachmentChunk,messageID:id,conversationID:UUID(),senderID:a.identity.id,recipientID:b.identity.id,body:"",createdAt:now,deliveredMessageID:nil,attachment:attachment,attachmentSHA256:RequestSigner.sha256Hex(bytes),chunkIndex:0,totalChunks:1,chunkDataBase64:bytes.base64EncodedString())
        let packet = try a.packet(to:b,payload:p)
        XCTAssertLessThanOrEqual(Data(base64Encoded:packet.sealedPayloadBase64)!.count,RelayWireCoding.maximumSealedPayloadBytes)
        XCTAssertLessThanOrEqual(try RelayWireCoding.makeEncoder().encode(packet).count,RelayWireCoding.maximumHTTPBodyBytes)
        XCTAssertEqual(try DateCoding.makeDecoder().decode(TransportMessagePayload.self,from:b.crypto.receive(packet, peer: b.trustedPeer(a.identity))).chunkDataBase64,bytes.base64EncodedString())
    }
}
private final class FailingOlmStore: ForwardSecretStoring {
    var data: Data?; var fail = false
    func load() throws -> Data? { data }
    func save(_ data:Data) throws { if fail { throw ForwardSecretError.persistence }; self.data=data }
}
