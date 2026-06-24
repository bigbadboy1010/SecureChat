import CryptoKit
import Foundation

protocol CryptoServicing {
    func makeSymmetricKey() throws -> SymmetricKey
    func encrypt(_ plaintext: Data, key: SymmetricKey, aad: Data) throws -> Data
    func decrypt(_ sealedCombinedData: Data, key: SymmetricKey, aad: Data) throws -> Data
    func derivePairwiseKey(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        peerPublicKey: Curve25519.KeyAgreement.PublicKey,
        context: Data
    ) throws -> SymmetricKey
    func peerID(publicKeyData: Data) -> String
    func safetyNumber(peerID: String) -> String
    func sign(_ data: Data, privateKey: Curve25519.Signing.PrivateKey) throws -> Data
    func verify(signature: Data, data: Data, publicKey: Curve25519.Signing.PublicKey) -> Bool
    /// Sprint 27 (2026-06-24): encode an
    /// Ed25519 signing public key as a
    /// PEM-encoded SubjectPublicKeyInfo.
    /// Used by `RelayTransport.enrollPublicKey`
    /// to register the local peer with the
    /// relay before any peer-signed request
    /// is accepted.
    func pemEncodedSigningPublicKey(_ publicKey: Curve25519.Signing.PublicKey) -> String
}

final class CryptoService: CryptoServicing {
    func makeSymmetricKey() throws -> SymmetricKey {
        SymmetricKey(data: try SecureRandom.data(byteCount: 32))
    }

    func encrypt(_ plaintext: Data, key: SymmetricKey, aad: Data) throws -> Data {
        do {
            let nonceData = try SecureRandom.data(byteCount: 12)
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealedBox = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: aad)
            guard let combined = sealedBox.combined else {
                throw PrivateChatError.encryptionFailed
            }
            return combined
        } catch let error as PrivateChatError {
            throw error
        } catch {
            throw PrivateChatError.encryptionFailed
        }
    }

    func decrypt(_ sealedCombinedData: Data, key: SymmetricKey, aad: Data) throws -> Data {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: sealedCombinedData)
            return try AES.GCM.open(sealedBox, using: key, authenticating: aad)
        } catch {
            throw PrivateChatError.decryptionFailed
        }
    }

    func derivePairwiseKey(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        peerPublicKey: Curve25519.KeyAgreement.PublicKey,
        context: Data
    ) throws -> SymmetricKey {
        do {
            let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
            return sharedSecret.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: Data("PrivateChat/X25519/v2".utf8),
                sharedInfo: context,
                outputByteCount: 32
            )
        } catch {
            throw PrivateChatError.invalidKeyMaterial
        }
    }

    func peerID(publicKeyData: Data) -> String {
        SHA256.hash(data: publicKeyData).map { String(format: "%02x", $0) }.joined()
    }

    func safetyNumber(peerID: String) -> String {
        let sanitized = peerID.uppercased()
        let groups = stride(from: 0, to: min(sanitized.count, 64), by: 4).map { offset -> String in
            let startIndex = sanitized.index(sanitized.startIndex, offsetBy: offset)
            let endIndex = sanitized.index(startIndex, offsetBy: min(4, sanitized.distance(from: startIndex, to: sanitized.endIndex)))
            return String(sanitized[startIndex..<endIndex])
        }
        return groups.joined(separator: " ")
    }

    func sign(_ data: Data, privateKey: Curve25519.Signing.PrivateKey) throws -> Data {
        do {
            return try privateKey.signature(for: data)
        } catch {
            throw PrivateChatError.invalidKeyMaterial
        }
    }

    func verify(signature: Data, data: Data, publicKey: Curve25519.Signing.PublicKey) -> Bool {
        publicKey.isValidSignature(signature, for: data)
    }

    /// Sprint 27 (2026-06-24): encode an Ed25519
    /// signing public key as a PEM-encoded
    /// SubjectPublicKeyInfo (SPKI) so the relay
    /// can verify peer-bound signatures.
    ///
    /// CryptoKit exposes `rawRepresentation` (the
    /// 32-byte Ed25519 public key) but not the
    /// ASN.1 wrapper the relay expects. The
    /// standard SPKI for Ed25519 (RFC 8410) is:
    ///
    ///   SEQUENCE {                       -- 0x30 0x2A
    ///     SEQUENCE {                     -- 0x30 0x05
    ///       OID 1.3.101.112 (Ed25519)    -- 0x06 0x03 0x2B 0x65 0x70
    ///     }
    ///     BIT STRING {                   -- 0x03 0x21 0x00
    ///       <32 raw bytes>
    ///     }
    ///   }
    ///
    /// The header is fixed for all Ed25519 SPKIs.
    /// We hardcode it here so we don't pull in
    /// Security/SecKey APIs that ship unstable
    /// PEM semantics across iOS versions.
    ///
    /// **Correction (2026-06-24):** the previous
    /// header included an explicit `NULL` (0x05 0x00)
    /// inside the inner algorithm SEQUENCE, which
    /// matches the X.509 AlgorithmIdentifier for
    /// *some* algorithms (e.g. RSA) but is **wrong**
    /// for Ed25519 (RFC 8410 §3: parameters must be
    /// ABSENT, not NULL). This produced a 12-byte
    /// DER that openssl/Python cryptography rejected
    /// on the first attempt. The corrected header
    /// is 11 bytes and was verified against
    /// `cryptography.hazmat.primitives.asymmetric.ed25519`.
    func pemEncodedSigningPublicKey(_ publicKey: Curve25519.Signing.PublicKey) -> String {
        let rawKey = publicKey.rawRepresentation
        precondition(rawKey.count == 32, "Ed25519 public key must be 32 raw bytes")

        // Fixed Ed25519 SPKI header (11 bytes).
        // Verified against python `cryptography` lib:
        //   cryptography.hazmat.primitives.asymmetric.ed25519.Ed25519PublicKey
        //     .public_bytes(DER, SubjectPublicKeyInfo)
        // produces a 44-byte DER starting with
        // `30 2a 30 05 06 03 2b 65 70 03 21 00`.
        let spkiHeader: [UInt8] = [
            0x30, 0x2A,                   // SEQUENCE (42 bytes)
            0x30, 0x05,                   // SEQUENCE (5 bytes)
            0x06, 0x03, 0x2B, 0x65, 0x70, // OID 1.3.101.112
            0x03, 0x21, 0x00,             // BIT STRING (33 bytes, 0 unused)
        ]

        var spkiBytes = Data(spkiHeader)
        spkiBytes.append(rawKey)

        let base64 = spkiBytes.base64EncodedString()
        // PEM is base64 wrapped in 64-char lines.
        var pem = "-----BEGIN PUBLIC KEY-----\n"
        var index = base64.startIndex
        while index < base64.endIndex {
            let end = base64.index(index, offsetBy: 64, limitedBy: base64.endIndex) ?? base64.endIndex
            pem += base64[index..<end]
            pem += "\n"
            index = end
        }
        pem += "-----END PUBLIC KEY-----\n"
        return pem
    }
}
