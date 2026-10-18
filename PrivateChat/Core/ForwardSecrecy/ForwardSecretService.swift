import CryptoKit
import Foundation

/// All mutations are synchronous on the chat's actor. Engine state and the
/// exact retry packet / decrypted inbox journal share one encrypted transaction.
@MainActor
final class ForwardSecretService {
    private struct Connection: Codable { let identity: String; var sessionIDs: [String] }
    private struct Sent: Codable { let packet: OutboundTransportPacket; let digest: String; let messageID: UUID; let kind: TransportPayloadKind }
    private struct Received: Codable { let digest: String; let plaintext: Data; let expiresAt: Date; let senderID: String }
    private struct State: Codable {
        let version: Int
        let owner: String
        let identity: String
        var engine: String
        var peers: [String: Connection] = [:]
        var outbound: [String: Sent] = [:]
        var inbound: [String: Received] = [:]
        var claims: [String: UUID] = [:]
        var pendingBatch: OlmPrekeyBatch?
        var sequence: Int = 0
        var lastPublication = Date.distantPast
        var keyExpiry: [String: Date] = [:]
    }
    private let store: ForwardSecretStoring
    private let local: LocalIdentity
    private var state: State?
    private(set) var blocked = false
    private let encoder = RelayWireCoding.makeEncoder()
    private let decoder = DateCoding.makeDecoder()

    init(store: ForwardSecretStoring, local: LocalIdentity) { self.store = store; self.local = local }
    func load() throws {
        guard !blocked else { throw ForwardSecretError.persistence }
        if let data = try store.load() {
            let existing = try decoder.decode(State.self, from: data)
            guard existing.version == 1, existing.owner == local.id else { throw ForwardSecretError.persistence }
            state = existing
        } else {
            let result = try OlmBridge.execute("new")
            guard let identity = result.identity else { throw ForwardSecretError.invalidBundle }
            try commit(State(version: 1, owner: local.id, identity: identity, engine: result.state))
        }
    }
    private func snapshot() throws -> State {
        guard !blocked, let state else { throw ForwardSecretError.persistence }; return state
    }
    private func commit(_ next: State) throws {
        let data = try encoder.encode(next)
        guard data.count < 28 * 1_048_576 else { throw ForwardSecretError.unavailable }
        do { try store.save(data); state = next }
        catch { blocked = true; throw ForwardSecretError.persistence }
    }
    private func clean(_ next: inout State) throws {
        let now = Date()
        next.outbound = next.outbound.filter { $0.value.packet.expiresAt > now }
        next.inbound = next.inbound.filter { $0.value.expiresAt > now }
        let expired = next.keyExpiry.filter { $0.value.addingTimeInterval(86_700) < now }.map(\.key)
        if !expired.isEmpty {
            next.engine = try OlmBridge.execute("remove_keys", state: next.engine, parameters: ["remove_keys": expired]).state
            for key in expired { next.keyExpiry.removeValue(forKey: key) }
        }
    }
    func publicationIfNeeded(serverStatus: OlmPrekeyStatus? = nil) throws -> OlmPrekeyBatch? {
        var next = try snapshot()
        if let serverStatus {
            guard serverStatus.sequence <= next.sequence else { throw ForwardSecretError.persistence }
            if let identity = serverStatus.identity, identity != next.identity { throw ForwardSecretError.identityChanged }
        }
        if let pending = next.pendingBatch {
            if pending.keys.allSatisfy({ (ISO8601DateFormatter().date(from: $0.expiresAt) ?? .distantPast) > Date() }) { return pending }
            // A lost publication response may have left keys at the relay.
            // Stop advertising this expired batch, but retain its private keys
            // for one additional packet TTL before pruning them in clean().
            next.engine = try OlmBridge.execute("published", state: next.engine).state
            next.pendingBatch = nil
        }
        let refill = serverStatus.map { $0.available < 25 } ?? false
        guard refill || Date().timeIntervalSince(next.lastPublication) >= 86_400 else { return nil }
        try clean(&next)
        let result = try OlmBridge.execute("keys", state: next.engine, parameters: ["count": 50])
        guard let keys = result.keys else { throw ForwardSecretError.invalidBundle }
        let expiry = Date().addingTimeInterval(6 * 86_400)
        let expiryString = ISO8601DateFormatter().string(from: expiry)
        let signedKeys = try keys.sorted(by: { $0.key < $1.key }).map { entry in
            OlmPrekey(id: entry.key, key: entry.value, expiresAt: expiryString,
                signatureBase64: try local.signingPrivateKey.signature(for: OlmCommitment.data(["PrivateRoom/OlmPrekey/v1", local.id, next.identity, entry.key, entry.value, expiryString])).base64EncodedString())
        }
        next.sequence += 1
        next.engine = result.state
        next.pendingBatch = OlmPrekeyBatch(identity: next.identity,
            identitySignatureBase64: try local.signingPrivateKey.signature(for: OlmCommitment.data(["PrivateRoom/OlmIdentity/v1", local.id, next.identity])).base64EncodedString(),
            sequence: next.sequence, keys: signedKeys)
        for value in keys.values { next.keyExpiry[value] = expiry }
        try commit(next)
        return next.pendingBatch
    }
    func publicationAccepted(_ batch: OlmPrekeyBatch) throws {
        var next = try snapshot()
        guard next.pendingBatch?.sequence == batch.sequence else { throw ForwardSecretError.invalidBundle }
        next.engine = try OlmBridge.execute("published", state: next.engine).state
        next.lastPublication = Date(); next.pendingBatch = nil
        try commit(next)
    }
    func needsSession(peerID: String) throws -> Bool { try snapshot().peers[peerID]?.sessionIDs.isEmpty ?? true }
    func claimID(peerID: String) throws -> UUID {
        var next = try snapshot()
        if let existing = next.claims[peerID] { return existing }
        let id = UUID(); next.claims[peerID] = id; try commit(next); return id
    }
    func acceptClaim(_ claim: OlmPrekeyClaim, peer: TrustedPeer) throws {
        var next = try snapshot()
        guard claim.requester == local.id, claim.recipientID == peer.id, next.claims[peer.id] == claim.claimID,
              let signingData = Data(base64Encoded: peer.signingPublicKeyBase64),
              let signature = Data(base64Encoded: claim.identitySignatureBase64),
              let keySignature = Data(base64Encoded: claim.prekey.signatureBase64),
              let expiry = ISO8601DateFormatter().date(from: claim.prekey.expiresAt), expiry > Date(),
              expiry.timeIntervalSinceNow <= 7 * 86_400 else { throw ForwardSecretError.invalidBundle }
        let signing = try Curve25519.Signing.PublicKey(rawRepresentation: signingData)
        guard signing.isValidSignature(signature, for: OlmCommitment.data(["PrivateRoom/OlmIdentity/v1", peer.id, claim.identity])),
              signing.isValidSignature(keySignature, for: OlmCommitment.data(["PrivateRoom/OlmPrekey/v1", peer.id, claim.identity, claim.prekey.id, claim.prekey.key, claim.prekey.expiresAt])) else { throw ForwardSecretError.invalidBundle }
        if let previous = next.peers[peer.id], previous.identity != claim.identity { throw ForwardSecretError.identityChanged }
        // A crossing inbound pre-key message might already have established a
        // session while this claim was in flight. Keep that session too.
        let result = try OlmBridge.execute("outbound", state: next.engine, parameters: ["peer": peer.id, "identity": claim.identity, "one_time_key": claim.prekey.key])
        guard let id = result.sessionID else { throw ForwardSecretError.invalidBundle }
        var connection = next.peers[peer.id] ?? Connection(identity: claim.identity, sessionIDs: [])
        connection.sessionIDs = Array(Set(connection.sessionIDs + [id])).sorted()
        next.peers[peer.id] = connection; next.engine = result.state; next.claims.removeValue(forKey: peer.id)
        try commit(next)
    }
    func makePacket(payload: TransportMessagePayload, recipientID: String, packetID: UUID) throws -> OutboundTransportPacket {
        var next = try snapshot(); try clean(&next)
        let id = packetID.uuidString.lowercased()
        var payloadData = try encoder.encode(payload)
        if let previous = next.outbound[id] {
            if payload.kind == .deliveryReceipt {
                // Receipt retry timestamps are generated by the UI service.
                // Compare the semantic payload using the committed timestamp.
                var fields = try JSONSerialization.jsonObject(with: payloadData) as! [String: Any]
                fields.removeValue(forKey: "createdAt")
                payloadData = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
            }
            guard previous.packet.recipientID == recipientID, previous.digest == Self.digest(payloadData) else { throw PrivateChatError.invalidInboundPacket }
            return previous.packet
        }
        guard let connection = next.peers[recipientID], let sessionID = connection.sessionIDs.first else { throw ForwardSecretError.unavailable }
        let createdAt = Date(timeIntervalSince1970: floor(payload.createdAt.timeIntervalSince1970))
        let expiresAt = createdAt.addingTimeInterval(86_400)
        guard expiresAt > Date() else { throw PrivateChatError.relayHTTPError(statusCode: 410, message: "packet_expired") }
        guard next.outbound.count < 512 else { throw ForwardSecretError.unavailable }
        guard payloadData.count < 100_000 else { throw PrivateChatError.attachmentTooLarge(maximumBytes: ConversationService.maximumAttachmentBytes) }
        let digestData: Data
        if payload.kind == .deliveryReceipt {
            var fields = try JSONSerialization.jsonObject(with: payloadData) as! [String: Any]; fields.removeValue(forKey: "createdAt")
            digestData = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        } else { digestData = payloadData }
        let result = try OlmBridge.execute("encrypt", state: next.engine, parameters: ["peer": recipientID, "identity": connection.identity, "session_id": sessionID, "plaintext": String(decoding: payloadData, as: UTF8.self)])
        guard let message = result.message else { throw ForwardSecretError.invalidBundle }
        let sealed = try encoder.encode(OlmWireEnvelope(version: 1, identity: next.identity, sessionID: sessionID, message: message)).base64EncodedString()
        let unsigned = OutboundTransportPacket(protocolVersion: 4, id: packetID, senderID: local.id, recipientID: recipientID,
            sealedPayloadBase64: sealed, signatureBase64: "pending", createdAt: createdAt, expiresAt: expiresAt)
        let packet = OutboundTransportPacket(protocolVersion: 4, id: packetID, senderID: local.id, recipientID: recipientID,
            sealedPayloadBase64: sealed, signatureBase64: try local.signingPrivateKey.signature(for: unsigned.authenticatedData).base64EncodedString(), createdAt: createdAt, expiresAt: expiresAt)
        next.engine = result.state; next.outbound[id] = Sent(packet: packet, digest: Self.digest(digestData), messageID: payload.messageID, kind: payload.kind); try commit(next)
        return packet
    }
    /// Authentication is mandatory at this boundary, even for journal retries.
    /// The journal permits crash recovery without retaining consumed message keys.
    func receive(_ packet: OutboundTransportPacket, peer: TrustedPeer) throws -> Data {
        guard packet.protocolVersion == 4, packet.recipientID == local.id,
              packet.senderID == peer.id, peer.trustState == .verified,
              let publicData = Data(base64Encoded: peer.signingPublicKeyBase64),
              RequestSigner.sha256Hex(publicData) == peer.id,
              let agreement = Data(base64Encoded: peer.keyAgreementPublicKeyBase64),
              let signature = Data(base64Encoded: packet.signatureBase64),
              peer.safetyNumber == SafetyNumberV3.make(localSigningPublicKeyData: local.signingPublicKeyData,
                localKeyAgreementPublicKeyData: local.keyAgreementPublicKeyData, remoteSigningPublicKeyData: publicData,
                remoteKeyAgreementPublicKeyData: agreement),
              try Curve25519.Signing.PublicKey(rawRepresentation: publicData).isValidSignature(signature, for: packet.authenticatedData)
        else { throw PrivateChatError.invalidSignature }

        var next = try snapshot(); try clean(&next)
        let id = packet.id.uuidString.lowercased(), digest = Self.digest(packet.authenticatedData)
        if let previous = next.inbound[id] {
            guard previous.digest == digest else { throw PrivateChatError.invalidInboundPacket }
            return previous.plaintext
        }
        guard packet.protocolVersion == 4, next.inbound.count < 512,
              let data = Data(base64Encoded: packet.sealedPayloadBase64), data.count <= RelayWireCoding.maximumSealedPayloadBytes else { throw PrivateChatError.invalidInboundPacket }
        let wire = try decoder.decode(OlmWireEnvelope.self, from: data)
        guard wire.version == 1, [0,1].contains(wire.message.type) else { throw PrivateChatError.invalidInboundPacket }
        if let previous = next.peers[packet.senderID], previous.identity != wire.identity { throw ForwardSecretError.identityChanged }
        let result = try OlmBridge.execute("decrypt", state: next.engine, parameters: ["peer": packet.senderID, "identity": wire.identity, "session_id": wire.sessionID, "message": ["type": wire.message.type, "body": wire.message.body]])
        guard let plaintext = result.plaintext else { throw PrivateChatError.invalidInboundPacket }
        let bytes = Data(plaintext.utf8)
        let payload = try decoder.decode(TransportMessagePayload.self, from: bytes)
        guard payload.version == 3, payload.senderID == packet.senderID, payload.recipientID == local.id,
              DateCoding.string(from: payload.createdAt) == DateCoding.string(from: packet.createdAt) else { throw PrivateChatError.invalidInboundPacket }
        var connection = next.peers[packet.senderID] ?? Connection(identity: wire.identity, sessionIDs: [])
        connection.sessionIDs = Array(Set(connection.sessionIDs + [wire.sessionID])).sorted()
        next.engine = result.state; next.peers[packet.senderID] = connection
        next.inbound[id] = Received(digest: digest, plaintext: bytes, expiresAt: packet.expiresAt, senderID: packet.senderID)
        try commit(next)
        return bytes
    }
    func acknowledged(packetID: UUID) throws {
        var next = try snapshot()
        if next.inbound.removeValue(forKey: packetID.uuidString.lowercased()) != nil { try commit(next) }
    }
    func discardPendingInbound(peerID: String) throws {
        var next = try snapshot()
        let count = next.inbound.count
        next.inbound = next.inbound.filter { $0.value.senderID != peerID }
        let claim = next.claims.removeValue(forKey: peerID)
        if count != next.inbound.count || claim != nil { try commit(next) }
    }
    func delivered(messageID: UUID, peerID: String) throws {
        var next = try snapshot()
        let previous = next.outbound.count
        next.outbound = next.outbound.filter {
            !($0.value.messageID == messageID && $0.value.packet.recipientID == peerID && $0.value.kind != .deliveryReceipt)
        }
        if next.outbound.count != previous { try commit(next) }
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
