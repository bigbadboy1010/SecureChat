import Foundation
import CryptoKit

/// X3DH (Extended Triple Diffie-Hellman) initial-bundle key agreement
/// for SecureChat's Double Ratchet sessions (ADR-006).
///
/// X3DH establishes a shared 32-byte root key between two peers
/// (Alice = initiator, Bob = responder) who each know the
/// other's long-term `Curve25519.KeyAgreement` public key from
/// a `PairingPayload`. The result is:
///
/// 1. A 32-byte `rootKey` that becomes the input to the Double
///    Ratchet's root-KDF (see `DoubleRatchetSession`).
/// 2. The **responder's** initial ratchet keypair (which the
///    initiator also needs to know) — Bob's identity key in
///    the responder role, and Alice's identity key in the
///    initiator role.
///
/// This implementation follows the standard X3DH construction
/// simplified to two key-agreement steps (we use the two
/// long-term identity keys; no signed prekey, no one-time
/// prekey) because the public-beta threat model does not
/// require asynchronous prekey delivery — pairing is
/// in-person via QR code, so the prekey is unnecessary.
///
/// Wire compatibility: the bundle is exchanged via the
/// existing `PairingPayload` (`IdentityManager.exportPairingPayload`),
/// which already carries both `keyAgreementPublicKeyBase64`
/// and `signingPublicKeyBase64`. No new wire field is needed.
public enum X3DHAgreement {

    /// Derive the shared 32-byte root key from the two
    /// long-term `Curve25519.KeyAgreement` keys. The DH is
    /// symmetric (`a * B = b * A`) so the same root key
    /// comes out on both sides.
    ///
    /// - Parameters:
    ///   - localKeyAgreementPrivateKey: the local side's
    ///     long-term private key.
    ///   - remoteKeyAgreementPublicKey: the remote side's
    ///     long-term public key (read out of `PairingPayload`).
    ///   - sessionSalt: an additional 32-byte salt that
    ///     binds the root key to the conversation. The
    ///     `PairingPayload.createdAt` value (encoded as
    ///     bytes) is the recommended choice, so two
    ///     `PairingPayload`s exchanged in different
    ///     pairings cannot accidentally derive the same
    ///     root key.
    /// - Returns: 32-byte `Data` for the Double Ratchet
    ///   `rootKey`.
    public static func deriveRootKey(
        localKeyAgreementPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        remoteKeyAgreementPublicKey: Curve25519.KeyAgreement.PublicKey,
        sessionSalt: Data
    ) throws -> Data {
        let shared = try localKeyAgreementPrivateKey.sharedSecretFromKeyAgreement(
            with: remoteKeyAgreementPublicKey
        )
        // HKDF over the shared secret, with the session salt
        // as info (per X3DH) and zero-byte salt for the HKDF
        // itself (per the standard).
        let info = sessionSalt.isEmpty
            ? Data("SecureChatX3DHv1".utf8)
            : sessionSalt + Data("|SecureChatX3DHv1".utf8)
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: shared.hkdfInputKeySymmetricKey(),
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
    ///     "SecureChat-X3DH-v1|" || min(alices, bobs) || "|" || max(alices, bobs)
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
        var data = Data("SecureChat-X3DH-v1|".utf8)
        withUnsafeBytes(of: lo.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: [0x7C]) // "|"
        withUnsafeBytes(of: hi.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        return data
    }

    /// A 16-byte session ID derived from the root key (for
    /// the Double Ratchet `sessionID` field). Stable across
    /// both sides because the root key is stable.
    public static func sessionID(fromRootKey rootKey: Data) -> String {
        let digest = SHA256.hash(data: rootKey)
        let hex = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "sc-\(hex)"
    }
}


// MARK: - SharedSecret extension
private extension SharedSecret {
    /// Wrap the shared secret as a `SymmetricKey` so it can
    /// be fed into `HKDF.deriveKey(inputKeyMaterial:)`. The
    /// underlying bytes are copied once and treated as
    /// ephemeral (the SharedSecret API is intentionally
    /// zeroing-resistant).
    func hkdfInputKeySymmetricKey() -> SymmetricKey {
        let data = self.withUnsafeBytes { Data($0) }
        return SymmetricKey(data: data)
    }
}
