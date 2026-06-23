import Foundation
import CryptoKit

/// High-level envelope for the v2 (Double Ratchet)
/// transport. Owns a `DoubleRatchetSession` for one
/// `peerID` and a `DoubleRatchetStoring` to persist
/// the X3DH initial-bundle material so the channel
/// can be rebuilt after app relaunch.
///
/// **Wire format.** A v2 message is a single
/// JSON object (the `WireMessage` from the
/// `DoubleRatchetSession` library) wrapped in an
/// outer envelope that names the peer and the
/// `WireMessage.sessionID` so the receiver can
/// look up the right channel:
///
/// ```json
/// {
///   "v": 2,
///   "peerID": "alice",
///   "ratchet": {
///     "v": 2,
///     "sessionID": "sc-...",
///     "ratchetPK": "...",
///     "counter": 1,
///     "prevChainLen": 0,
///     "ciphertext": "..."
///   }
/// }
/// ```
///
/// `RatchetChannelEnvelope` is the outer wrapper.
/// It is intentionally different from the v1
/// `OutboundTransportPacket` (which carries a
/// Curve25519-ECDH-encrypted `payloadAAD`) so the
/// relay can route the two envelope families
/// independently and increment the v2-stat counter
/// in `/v1/relay/stats` (Sprint 9C).
public struct RatchetChannelEnvelope: Codable, Equatable {
    public let v: Int
    public let peerID: String
    public let ratchet: DoubleRatchetSession.WireMessage

    public init(
        v: Int = 2,
        peerID: String,
        ratchet: DoubleRatchetSession.WireMessage
    ) {
        self.v = v
        self.peerID = peerID
        self.ratchet = ratchet
    }
}

/// A `RatchetChannel` is one peer-to-peer Double
/// Ratchet session, plus a store for the X3DH
/// initial-bundle material. The class is the only
/// public face of the v2 transport; the
/// `ConversationService` in Sprint 9C/10 will
/// route through it.
final class RatchetChannel {
    let peerID: String
    let sessionID: String
    private let store: DoubleRatchetStoring
    private let session: DoubleRatchetSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        peerID: String,
        persisted: PersistedRatchetSession,
        store: DoubleRatchetStoring
    ) throws {
        self.peerID = peerID
        self.sessionID = persisted.sessionID
        self.store = store
        self.session = try DoubleRatchetSessionFactory.makeSession(from: persisted)
        self.encoder = DoubleRatchetStore.defaultEncoder
        self.decoder = DoubleRatchetStore.defaultDecoder
    }

    /// Encrypt `plaintext` and return the outer
    /// v2 envelope. The envelope's `peerID` is the
    /// **sender's** local-identity peer ID, so the
    /// receiver can route the envelope to the
    /// right inbound channel. The `peerID` property
    /// of the channel is the remote peer's identity
    /// (the key under which the channel is stored),
    /// so to put the sender's identity on the wire
    /// the caller passes a `senderID` (typically
    /// the `LocalIdentity.id` of the local user).
    func send(plaintext: Data, senderID: String) throws -> RatchetChannelEnvelope {
        let wire = try session.encrypt(plaintext)
        return RatchetChannelEnvelope(peerID: senderID, ratchet: wire)
    }

    /// Decrypt a v2 envelope. The envelope's
    /// `peerID` is the **sender's** peer ID; the
    /// channel's `peerID` is also the sender's
    /// identity from the receiver's perspective
    /// (i.e. the receiver knows the sender by the
    /// same string both sides agreed on during
    /// pairing). They must match.
    func receive(_ envelope: RatchetChannelEnvelope) throws -> Data {
        guard envelope.peerID == peerID else {
            throw ChannelError.peerMismatch(
                expected: peerID,
                actual: envelope.peerID
            )
        }
        guard envelope.ratchet.sessionID == sessionID else {
            throw ChannelError.sessionMismatch
        }
        return try session.decrypt(envelope.ratchet)
    }

    /// Build a `RatchetChannel` for a peer, loading
    /// the X3DH initial-bundle material from the
    /// store. Returns `nil` if no material is
    /// stored yet (caller is expected to fall back
    /// to the v1 envelope in that case).
    static func open(
        peerID: String,
        store: DoubleRatchetStoring
    ) throws -> RatchetChannel? {
        guard let persisted = try store.load(peerID: peerID) else {
            return nil
        }
        return try RatchetChannel(
            peerID: peerID,
            persisted: persisted,
            store: store
        )
    }

    /// Persist a fresh X3DH-bundle material so the
    /// channel can be opened on next launch. This
    /// is the function the `ConversationService`
    /// calls after a successful pairing.
    static func register(
        peerID: String,
        localKeyAgreementPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        remoteKeyAgreementPublicKey: Curve25519.KeyAgreement.PublicKey,
        remoteSigningPublicKey: Curve25519.Signing.PublicKey,
        localPayloadCreatedAt: Date,
        remotePayloadCreatedAt: Date,
        store: DoubleRatchetStoring
    ) throws -> RatchetChannel {
        let persisted = try DoubleRatchetSessionFactory.makePersisted(
            peerID: peerID,
            localKeyAgreementPrivateKey: localKeyAgreementPrivateKey,
            remoteKeyAgreementPublicKey: remoteKeyAgreementPublicKey,
            remoteSigningPublicKey: remoteSigningPublicKey,
            localPayloadCreatedAt: localPayloadCreatedAt,
            remotePayloadCreatedAt: remotePayloadCreatedAt
        )
        try store.save(persisted)
        return try RatchetChannel(
            peerID: peerID,
            persisted: persisted,
            store: store
        )
    }

    enum ChannelError: Error, Equatable {
        case peerMismatch(expected: String, actual: String)
        case sessionMismatch
    }
}
