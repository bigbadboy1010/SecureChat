import Foundation
import CryptoKit

/// On-device persistence for Double-Ratchet session state.
///
/// The `DoubleRatchetSession` library keeps all state
/// private (root key, send/recv chain keys, counters,
/// DH ratchet keypair, skipped-message-key window).
/// To persist a session across app launches we need
/// a way to export and re-import that state without
/// breaking the library's AEAD guarantees.
///
/// The persistence model is intentionally simple:
/// each persisted session carries the **full X3DH
/// material** needed to rebuild the session from
/// scratch (the long-term key-agreement private key
/// on the local side, the remote's pre-exchanged
/// long-term public key, the pair of `PairingPayload`
/// timestamps, the local ratchet private key, and the
/// remote ratchet public key). That is enough to
/// rebuild a session that has **never** been used
/// yet.
///
/// For sessions that **have** been used, the library
/// itself has moved past the initial-bundle state
/// (the sender has rotated its DH ratchet keypair,
/// new chain keys are in flight, the skipped-message
/// window has entries). Re-building such a session
/// from initial-bundle material is not possible
/// without also persisting the live ratchet state,
/// which the library does not expose yet.
///
/// For Sprint 9 we therefore persist **only the
/// initial-bundle material**. The v2 envelope
/// continues to use the v1 fallback for any
/// conversation whose session is mid-stream at
/// app-close time. The Relay's v2-stat counter
/// (Sprint 9C) will surface this as a
/// `legacyRequests++` event so we can watch how
/// often the fallback fires before we wire live
/// state into the store in Sprint 10.
///
/// Wire format: a single JSON blob per `peerID`,
/// stored in the on-device keychain via
/// `KeychainStore` (see `DoubleRatchetStore`).
public struct PersistedRatchetSession: Codable, Equatable {
    /// `peerID` from the `LocalIdentity` (the
    /// long-term identity of the conversation
    /// partner). This is also the keychain key.
    public let peerID: String
    /// `sessionID` from the X3DH agreement
    /// (`sc-XXXXXXXX` hex).
    public let sessionID: String
    /// The 32-byte shared root key.
    public let rootKey: Data
    /// Local long-term key-agreement private key
    /// (32-byte X25519 secret), kept for
    /// rebuild-after-relaunch. In a future Sprint
    /// this is replaced by a session-specific
    /// ephemeral ratchet key that is rotated
    /// forward on each `performOutgoingDHRatchet`.
    public let localInitialRatchetPrivateKey: Data
    /// Remote's pre-exchanged long-term public key
    /// (32-byte X25519 public).
    public let remoteInitialRatchetPublicKey: Data
    /// Local `PairingPayload.createdAt`.
    public let localPayloadCreatedAt: Date
    /// Remote `PairingPayload.createdAt`.
    public let remotePayloadCreatedAt: Date
    /// `true` once `liveState` is set (Sprint
    /// 10B). Until then the persisted session is
    /// just the initial-bundle material and a
    /// restored session has not been used for
    /// any encrypt/decrypt call.
    public let isSealed: Bool
    /// Sprint 10B: the live ratchet state
    /// (chain keys, counters, current DH ratchet
    /// keypair, skipped-message window). `nil`
    /// for sessions that have only been
    /// registered and never used; set after
    /// the first `RatchetChannel.send(...)` /
    /// `RatchetChannel.receive(...)` call.
    public let liveState: DoubleRatchetSession.LiveState?

    public init(
        peerID: String,
        sessionID: String,
        rootKey: Data,
        localInitialRatchetPrivateKey: Data,
        remoteInitialRatchetPublicKey: Data,
        localPayloadCreatedAt: Date,
        remotePayloadCreatedAt: Date,
        isSealed: Bool = false,
        liveState: DoubleRatchetSession.LiveState? = nil
    ) {
        self.peerID = peerID
        self.sessionID = sessionID
        self.rootKey = rootKey
        self.localInitialRatchetPrivateKey = localInitialRatchetPrivateKey
        self.remoteInitialRatchetPublicKey = remoteInitialRatchetPublicKey
        self.localPayloadCreatedAt = localPayloadCreatedAt
        self.remotePayloadCreatedAt = remotePayloadCreatedAt
        self.isSealed = isSealed
        self.liveState = liveState
    }
}

/// Build / restore `DoubleRatchetSession` instances
/// from a `PersistedRatchetSession`. The
/// `DoubleRatchetSession` library is intentionally
/// state-private, so the only way to bring a session
/// back is to rebuild it from the initial-bundle
/// material with the same `init` the tests use.
public enum DoubleRatchetSessionFactory {

    /// Build a fresh `DoubleRatchetSession` from a
    /// `PersistedRatchetSession`. The returned
    /// session can encrypt and decrypt the first
    /// message of the conversation. After that, the
    /// caller is responsible for the live state
    /// (ratchet rotation, chain-key step, etc.).
    ///
    /// Sprint 10B: if the persisted session carries
    /// a `liveState`, it is restored here so the
    /// caller gets back the exact state the
    /// session had at the last `exportLiveState()`
    /// call. A session that has never been used
    /// (no `liveState`) is built with a clean
    /// initial-bundle state.
    public static func makeSession(
        from persisted: PersistedRatchetSession
    ) throws -> DoubleRatchetSession {
        guard let localPriv = try? Curve25519.KeyAgreement.PrivateKey(
            rawRepresentation: persisted.localInitialRatchetPrivateKey
        ) else {
            throw PersistenceError.invalidKeyMaterial
        }
        guard let remotePub = try? Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: persisted.remoteInitialRatchetPublicKey
        ) else {
            throw PersistenceError.invalidKeyMaterial
        }
        let session = DoubleRatchetSession(
            sessionID: persisted.sessionID,
            rootKey: persisted.rootKey,
            initialRatchetPrivateKey: localPriv,
            initialRemoteRatchetPublicKey: remotePub
        )
        if let live = persisted.liveState {
            try session.restoreLiveState(live)
        }
        return session
    }

    /// Build a `PersistedRatchetSession` from the
    /// X3DH-bundle inputs that a fresh pairing
    /// would produce. The caller has the
    /// `PairingPayload`s from both sides and the
    /// local long-term keys. This helper derives
    /// the symmetric root key with X3DH, computes
    /// the session ID, and packages the result.
    public static func makePersisted(
        peerID: String,
        localKeyAgreementPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        remoteKeyAgreementPublicKey: Curve25519.KeyAgreement.PublicKey,
        remoteSigningPublicKey: Curve25519.Signing.PublicKey,
        localPayloadCreatedAt: Date,
        remotePayloadCreatedAt: Date
    ) throws -> PersistedRatchetSession {
        let salt = X3DHAgreement.sessionSalt(
            localPayloadCreatedAt: localPayloadCreatedAt,
            remotePayloadCreatedAt: remotePayloadCreatedAt
        )
        let rootKey = try X3DHAgreement.deriveRootKey(
            localKeyAgreementPrivateKey: localKeyAgreementPrivateKey,
            remoteKeyAgreementPublicKey: remoteKeyAgreementPublicKey,
            remoteSigningPublicKey: remoteSigningPublicKey,
            sessionSalt: salt
        )
        let sessionID = X3DHAgreement.sessionID(fromRootKey: rootKey)
        return PersistedRatchetSession(
            peerID: peerID,
            sessionID: sessionID,
            rootKey: rootKey,
            localInitialRatchetPrivateKey: localKeyAgreementPrivateKey.rawRepresentation,
            remoteInitialRatchetPublicKey: remoteKeyAgreementPublicKey.rawRepresentation,
            localPayloadCreatedAt: localPayloadCreatedAt,
            remotePayloadCreatedAt: remotePayloadCreatedAt,
            isSealed: false
        )
    }

    public enum PersistenceError: Error, Equatable {
        case invalidKeyMaterial
    }
}
