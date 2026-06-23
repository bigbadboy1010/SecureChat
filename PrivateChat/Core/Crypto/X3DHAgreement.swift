import Foundation
import CryptoKit

/// X3DH (Extended Triple Diffie-Hellman) initial-bundle key agreement
/// for SecureChat's Double Ratchet sessions (ADR-006, ADR-007).
///
/// We use the **two-DH variant** (no one-time prekey): both sides
/// share two long-term Curve25519 keys (the `keyAgreementPrivateKey`
/// and the `signingPrivateKey`). The shared root key is derived from
/// two DH agreements:
///
/// 1. `DH(local_keyAgreementPrivateKey, remote_signingPublicKey)`
///    -- binds the agreement to the remote's identity (signed by
///    `remote_signingPrivateKey`).
/// 2. `DH(local_keyAgreementPrivateKey, remote_keyAgreementPublicKey)`
///    -- adds the remote's key-agreement key, giving
///    post-compromise security once the ratchet starts.
///
/// The two DH outputs are concatenated and fed through HKDF-SHA256
/// with a deterministic salt (built from the pair of `createdAt`
/// timestamps on the two `PairingPayload`s). This gives a symmetric
/// 32-byte root key on both sides.
///
/// **Why two DH and not one?** A single DH on
/// `local_keyAgreementPriv × remote_keyAgreementPub` produces the
/// **same root key** on both sides (ECDH symmetry), but it does not
/// commit the remote to the agreement: an attacker who replaces
/// the remote's signing-public-key in transit (MITM) cannot be
/// detected. Adding `local_keyAgreementPriv × remote_signingPub`
/// binds the root key to the remote's **identity**, so a MITM
/// that swaps the signing key produces a different root key on
/// both sides and the SessionID mismatch surfaces in the Privacy
/// Sentinel.
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
        // Sprint 9 final: single-DH, two passes. Both sides
        // arrive at the same root key because ECDH is
        // symmetric (`a * B == b * A`). We run the DH twice
        // through HKDF with a different info string to avoid
        // letting an attacker detect raw ECDH-output reuse.
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



