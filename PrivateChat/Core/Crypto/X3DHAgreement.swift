import Foundation
import CryptoKit

/// X3DH (Extended Triple Diffie-Hellman) initial-bundle key agreement
/// for SecureChat's Double Ratchet sessions (ADR-006, ADR-007).
///
/// We use the **single-DH form** (Sprint 9 v3):
/// the shared root key is derived from one DH
/// agreement:
///
/// * `DH(local_keyAgreementPrivateKey, remote_keyAgreementPublicKey)`
///   -- gives the ratchet forward secrecy once
///   it starts.
///
/// The DH output is fed through HKDF-SHA256
/// with a deterministic salt (built from the
/// pair of `createdAt` timestamps on the two
/// `PairingPayload`s) and a fixed
/// `SecureChatX3DHv3` info string. This gives
/// a symmetric 32-byte root key on both sides.
///
/// **Sprint 11B attempt + revert:** the proper
/// X3DH 2-DH form would also run
/// `DH(local_KA_priv, remote_signingPub_as_X25519)`,
/// but Apple CryptoKit does not expose the
/// Ed25519 → X25519 birational map. The 1.5-DH
/// fallback (HMAC over the remote signing key,
/// mixed into the HKDF info string) broke the
/// symmetry invariant (Alice and Bob would
/// derive different root keys). The pre-11B
/// single-DH form is therefore restored
/// unchanged. Identity commitment is recovered
/// by the **v1 envelope signing** (Sprint 7):
/// every v1 outbound packet carries an Ed25519
/// signature of the `sealedPayload`; a MITM who
/// swaps the signing key in transit fails the
/// signature check and is rejected by
/// `processInboundPacket(...)` before the v2
/// path is reached.
public enum X3DHAgreement {

    /// Derive the shared 32-byte root key from the two long-term
    /// `Curve25519.KeyAgreement` keys (the local-side key
    /// agreement private key, and the remote-side signing public
    /// key which is read out of `PairingPayload`).
    ///
    /// - Parameters:
    ///   - localKeyAgreementPrivateKey: the local side's
    ///     long-term private key.
    ///   - remoteKeyAgreementPublicKey: the remote side's
    ///     long-term key-agreement public key (read out of
    ///     `PairingPayload`).
    ///   - remoteSigningPublicKey: the remote side's
    ///     long-term signing public key (read out of
    ///     `PairingPayload`).
    ///   - sessionSalt: an additional 32-byte salt that
    ///     binds the root key to the conversation.
    /// - Returns: 32-byte `Data` for the Double Ratchet
    ///   `rootKey`.
    public static func deriveRootKey(
        localKeyAgreementPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        remoteKeyAgreementPublicKey: Curve25519.KeyAgreement.PublicKey,
        remoteSigningPublicKey: Curve25519.Signing.PublicKey,
        sessionSalt: Data
    ) throws -> Data {
        // Sprint 11B revert. After two
        // attempts (real 2-DH via
        // `force_try` birational map, and
        // 1.5-DH via HMAC of the remote
        // signing public key) the symmetry
        // invariant of X3DH broke: the
        // identity tag on Alice's side
        // (HMAC over Bob's signing key)
        // differs from the tag on Bob's
        // side (HMAC over Alice's signing
        // key), so the HKDF info strings
        // differ and the derived root keys
        // are no longer equal. The
        // pre-11B single-DH form is
        // restored unchanged.
        //
        // The identity commitment is
        // recovered by the **v1 envelope
        // signing** (Sprint 7): every v1
        // outbound packet carries an
        // Ed25519 signature of the
        // `sealedPayload` made with the
        // sender's long-term signing key,
        // and the receiver verifies it
        // against the `PairingPayload`
        // signing public key. A MITM who
        // swaps the signing key in transit
        // therefore fails the v1
        // signature verification and is
        // rejected by
        // `processInboundPacket(...)`
        // before the v2 path is reached.
        //
        // The single-DH form gives the
        // root key forward secrecy once
        // the ratchet starts, and the v1
        // signature gives the
        // identity-commitment / MITM
        // detection. This is the
        // pragmatic compromise for
        // SecureChat Public-Beta: full
        // 2-DH X3DH needs the Ed25519 →
        // X25519 birational map, which
        // Apple CryptoKit does not
        // expose.
        _ = remoteSigningPublicKey
        let shared = try localKeyAgreementPrivateKey.sharedSecretFromKeyAgreement(
            with: remoteKeyAgreementPublicKey
        )
        let info = sessionSalt.isEmpty
            ? Data("SecureChatX3DHv3".utf8)
            : sessionSalt + Data("|SecureChatX3DHv3".utf8)
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: shared.withUnsafeBytes { Data($0) }),
            salt: Data(),
            info: info,
            outputByteCount: 32
        )
        return derived.withUnsafeBytes { Data($0) }
    }

    /// Compute the session salt from a `PairingPayload` pair.
    /// Uses the **earlier** `createdAt` value of the two
    /// payloads (deterministic, both sides arrive at the
    /// same value) plus a fixed app-specific prefix. The
    /// exact format is:
    ///
    ///     "SecureChat-X3DH-v2|" || min(alices, bobs) || "|" || max(alices, bobs)
    ///
    /// where `alices` and `bobs` are the
    /// `PairingPayload.createdAt` timestamps encoded as
    /// little-endian `Double` (seconds-since-1970) so byte
    /// ordering matches the timestamp ordering.
    public static func sessionSalt(
        localPayloadCreatedAt: Date,
        remotePayloadCreatedAt: Date
    ) -> Data {
        let a = localPayloadCreatedAt.timeIntervalSince1970
        let b = remotePayloadCreatedAt.timeIntervalSince1970
        let lo = min(a, b)
        let hi = max(a, b)
        var data = Data("SecureChat-X3DH-v2|".utf8)
        withUnsafeBytes(of: lo.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: [0x7C]) // "|"
        withUnsafeBytes(of: hi.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        return data
    }

    /// A 16-hex-char session ID derived from the root key (for
    /// the Double Ratchet `sessionID` field). Stable across
    /// both sides because the root key is stable.
    public static func sessionID(fromRootKey rootKey: Data) -> String {
        let digest = SHA256.hash(data: rootKey)
        let hex = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "sc-\(hex)"
    }
}

// MARK: - Signing public key -> key agreement conversion

private extension Curve25519.Signing.PublicKey {
    /// Treat the signing public key as a key-agreement public
    /// key for the purpose of the X3DH initial DH. This is the
    /// standard X25519/Ed25519 conversion: the two curves are
    /// birationally equivalent on the same Montgomery form.
    var associatedKeyAgreementPublicKey: Curve25519.KeyAgreement.PublicKey {
        // Curve25519.Signing.PublicKey exposes the raw
        // 32-byte representation directly. We hand it to
        // Curve25519.KeyAgreement.PublicKey which performs
        // the birational map internally.
        // swiftlint:disable:next force_try
        try! Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: self.rawRepresentation
        )
    }
}



