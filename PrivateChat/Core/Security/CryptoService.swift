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
}
