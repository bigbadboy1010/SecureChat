// SecureChat/BIT/Services/EncryptionService.swift
//
// Protocol v2 (hard break) – Step 2:
// - Full Double Ratchet (DH-ratchet) for private chats (PCS)
// - Signed packets (session signing key)
// - Persistent device identity (Ed25519) in Keychain
// - Session state persisted per peer in Keychain
//
// NOTE: Channel encryption is handled elsewhere. Private messages use packet format v3 defined in DoubleRatchet.swift.

import Foundation
import CryptoKit
import SwiftUI

enum EncryptionError: Error {
    case invalidPublicKey
    case noSharedSecret
    case encryptionFailed
    case decryptionFailed
    case invalidFormat
}

final class EncryptionService {
    // Ephemeral key agreement for discovery (not used as ratchet DHs)
    private var discoveryKeyAgreement: Curve25519.KeyAgreement.PrivateKey
    public let discoveryPublicKey: Curve25519.KeyAgreement.PublicKey

    // Ephemeral signing key (per run)
    private var signingPrivateKey: Curve25519.Signing.PrivateKey
    public let signingPublicKey: Curve25519.Signing.PublicKey

    // Persistent identity key (device-only)
    private let identityKey: Curve25519.Signing.PrivateKey
    public let identityPublicKey: Curve25519.Signing.PublicKey

    // Peer keys
    private var peerDiscoveryKeys: [String: Curve25519.KeyAgreement.PublicKey] = [:]
    private var peerSigningKeys: [String: Curve25519.Signing.PublicKey] = [:]
    private var peerIdentityKeys: [String: Curve25519.Signing.PublicKey] = [:]

    // Double-ratchet sessions per peer
    private var sessions: [String: DoubleRatchetSession] = [:]

    private let cryptoQueue = DispatchQueue(label: "chat.bit.crypto.v2", attributes: .concurrent)

    init() {
        self.discoveryKeyAgreement = Curve25519.KeyAgreement.PrivateKey()
        self.discoveryPublicKey = discoveryKeyAgreement.publicKey

        self.signingPrivateKey = Curve25519.Signing.PrivateKey()
        self.signingPublicKey = signingPrivateKey.publicKey

        if let raw = KeychainManager.shared.getIdentityKey(forKey: "bit.identityKey"),
           !raw.isEmpty,
           let loaded = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) {
            self.identityKey = loaded
        } else {
            let created = Curve25519.Signing.PrivateKey()
            _ = KeychainManager.shared.saveIdentityKey(created.rawRepresentation, forKey: "bit.identityKey")
            self.identityKey = created
        }
        self.identityPublicKey = identityKey.publicKey
    }

    // Combined key blob:
    // [32] discovery (key agreement) + [32] session signing + [32] persistent identity
    func getCombinedPublicKeyData() -> Data {
        var data = Data()
        data.append(discoveryPublicKey.rawRepresentation)
        data.append(signingPublicKey.rawRepresentation)
        data.append(identityPublicKey.rawRepresentation)
        return data
    }

    func addPeerPublicKey(_ peerID: String, publicKeyData: Data) throws {
        try cryptoQueue.sync(flags: .barrier) {
            let bytes = [UInt8](publicKeyData)
            guard bytes.count == 96 else { throw EncryptionError.invalidPublicKey }

            let ka = Data(bytes[0..<32])
            let sig = Data(bytes[32..<64])
            let id = Data(bytes[64..<96])

            let discoveryPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ka)
            let signingPub = try Curve25519.Signing.PublicKey(rawRepresentation: sig)
            let identityPub = try Curve25519.Signing.PublicKey(rawRepresentation: id)

            peerDiscoveryKeys[peerID] = discoveryPub
            peerSigningKeys[peerID] = signingPub
            peerIdentityKeys[peerID] = identityPub

            // Load or bootstrap double-ratchet session
            if let stored = KeychainManager.shared.getRatchetSession(peerID: peerID),
               let loaded = try? JSONDecoder().decode(DoubleRatchetSession.self, from: stored) {
                sessions[peerID] = loaded
            } else {
                let session = try DoubleRatchetSession(bootstrapWith: discoveryPub)
                sessions[peerID] = session
                if let encoded = try? JSONEncoder().encode(session) {
                    _ = KeychainManager.shared.saveRatchetSession(encoded, peerID: peerID)
                }
            }

            // TOFU check + safety number change event
            let fingerprint = Self.fingerprintString(for: identityPub.rawRepresentation)
            let event = IdentityVerificationService.shared.observeTOFU(peerID: peerID, currentFingerprint: fingerprint)
            if case .changed(let old, let new) = event {
                NotificationCenter.default.post(
                    name: .bitPeerIdentityChanged,
                    object: nil,
                    userInfo: ["peerID": peerID, "old": old, "new": new]
                )
            }
        }
    }

    func getPeerIdentityKey(_ peerID: String) -> Data? {
        cryptoQueue.sync { peerIdentityKeys[peerID]?.rawRepresentation }
    }

    // MARK: - Sign / Verify

    func sign(_ data: Data) throws -> Data {
        try signingPrivateKey.signature(for: data)
    }

    func verify(_ signature: Data, for data: Data, from peerID: String) -> Bool {
        cryptoQueue.sync {
            guard let pub = peerSigningKeys[peerID] else { return false }
            return pub.isValidSignature(signature, for: data)
        }
    }

    // MARK: - Private messaging (Full Double Ratchet)

    func encryptPrivate(_ plaintext: Data, for peerID: String) throws -> Data {
        try cryptoQueue.sync(flags: .barrier) {
            guard var session = sessions[peerID] else { throw EncryptionError.noSharedSecret }
            let packet = try session.encrypt(plaintext: plaintext)
            sessions[peerID] = session
            if let encoded = try? JSONEncoder().encode(session) {
                _ = KeychainManager.shared.saveRatchetSession(encoded, peerID: peerID)
            }
            return packet
        }
    }

    func decryptPrivate(_ packet: Data, from peerID: String) throws -> Data {
        try cryptoQueue.sync(flags: .barrier) {
            guard var session = sessions[peerID] else { throw EncryptionError.noSharedSecret }
            do {
                let plaintext = try session.decrypt(packet: packet)
                sessions[peerID] = session
                if let encoded = try? JSONEncoder().encode(session) {
                    _ = KeychainManager.shared.saveRatchetSession(encoded, peerID: peerID)
                }
                return plaintext
            } catch {
                throw EncryptionError.decryptionFailed
            }
        }
    }

    
// MARK: - Compatibility (existing call sites)

/// Backwards API used by some services. In Protocol v2+ these map to private Double Ratchet packets.
func encrypt(_ data: Data, for peerID: String) throws -> Data {
    try encryptPrivate(data, for: peerID)
}

/// Backwards API used by some services. In Protocol v2+ these map to private Double Ratchet packets.
func decrypt(_ data: Data, from peerID: String) throws -> Data {
    try decryptPrivate(data, from: peerID)
}

/// Clears the persisted identity key from Keychain. App restart will generate a new identity.
func clearPersistentIdentity() {
    _ = KeychainManager.shared.saveIdentityKey(Data(), forKey: "bit.identityKey")
}

// MARK: - Fingerprint

    static func fingerprintString(for publicKeyData: Data) -> String {
        let digest = SHA256.hash(data: publicKeyData)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return hex.chunked(into: 4).joined(separator: " ")
    }
}

private extension String {
    func chunked(into size: Int) -> [String] {
        guard size > 0 else { return [self] }
        var out: [String] = []
        out.reserveCapacity((count + size - 1) / size)
        var i = startIndex
        while i < endIndex {
            let j = index(i, offsetBy: size, limitedBy: endIndex) ?? endIndex
            out.append(String(self[i..<j]))
            i = j
        }
        return out
    }
}
