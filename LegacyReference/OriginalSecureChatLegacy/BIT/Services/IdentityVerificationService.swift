//
// IdentityVerificationService.swift
// schat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import CryptoKit

/// Stores and checks peer identity verification state (fingerprint-based).
/// Fingerprints are derived from the peer's persistent identity public key.
final class IdentityVerificationService: @unchecked Sendable {
    static let shared = IdentityVerificationService()

    private let queue = DispatchQueue(label: "chat.bit.identity.verification", qos: .userInitiated)
    private let storeKey = "bit.verifiedPeers" // [peerID: fingerprint]
    private let dateKey = "bit.verifiedPeersDates" // [peerID: timeIntervalSince1970]


// TOFU (Trust On First Use): store the first-seen fingerprint per peer and alert on changes.
private let tofuKey = "bit.peerTOFU" // [peerID: fingerprint]

enum PeerIdentityEvent: Equatable {
    case firstSeen(fingerprint: String)
    case unchanged
    case changed(old: String, new: String)
}

func observeTOFU(peerID: String, currentFingerprint: String) -> PeerIdentityEvent {
    queue.sync {
        var dict = (UserDefaults.standard.dictionary(forKey: tofuKey) as? [String: String]) ?? [:]
        if let old = dict[peerID] {
            if Self.normalize(old) == Self.normalize(currentFingerprint) {
                return .unchanged
            } else {
                dict[peerID] = currentFingerprint
                UserDefaults.standard.set(dict, forKey: tofuKey)
                return .changed(old: old, new: currentFingerprint)
            }
        } else {
            dict[peerID] = currentFingerprint
            UserDefaults.standard.set(dict, forKey: tofuKey)
            return .firstSeen(fingerprint: currentFingerprint)
        }
    }
}

func trustedFingerprint(peerID: String) -> String? {
    queue.sync {
        let dict = (UserDefaults.standard.dictionary(forKey: tofuKey) as? [String: String]) ?? [:]
        return dict[peerID]
    }
}

    private init() {}

    func myIdentityFingerprint(from encryptionService: EncryptionService) -> String {
        return Self.fingerprint(for: encryptionService.identityPublicKey.rawRepresentation)
    }

    func peerIdentityFingerprint(from encryptionService: EncryptionService, peerID: String) -> String? {
        guard let data = encryptionService.getPeerIdentityKey(peerID) else { return nil }
        return Self.fingerprint(for: data)
    }

    func isPeerVerified(_ peerID: String) -> Bool {
        return queue.sync {
            let dict = (UserDefaults.standard.dictionary(forKey: storeKey) as? [String: String]) ?? [:]
            return dict[peerID] != nil
        }
    }

    func verifiedFingerprint(for peerID: String) -> String? {
        return queue.sync {
            let dict = (UserDefaults.standard.dictionary(forKey: storeKey) as? [String: String]) ?? [:]
            return dict[peerID]
        }
    }

    /// Verifies a peer by comparing the expected fingerprint with the currently known peer identity key fingerprint.
    /// Returns true if verified and stored.
    @discardableResult
    func verifyPeer(peerID: String, expectedFingerprint: String, encryptionService: EncryptionService) -> Bool {
        guard let current = peerIdentityFingerprint(from: encryptionService, peerID: peerID) else { return false }
        guard Self.normalize(expectedFingerprint) == Self.normalize(current) else { return false }

        queue.sync {
            var dict = (UserDefaults.standard.dictionary(forKey: storeKey) as? [String: String]) ?? [:]
            dict[peerID] = current
            UserDefaults.standard.set(dict, forKey: storeKey)

            var dates = (UserDefaults.standard.dictionary(forKey: dateKey) as? [String: Double]) ?? [:]
            dates[peerID] = Date().timeIntervalSince1970
            UserDefaults.standard.set(dates, forKey: dateKey)
        }
        return true
    }

    func unverifyPeer(peerID: String) {
        queue.sync {
            var dict = (UserDefaults.standard.dictionary(forKey: storeKey) as? [String: String]) ?? [:]
            dict.removeValue(forKey: peerID)
            UserDefaults.standard.set(dict, forKey: storeKey)

            var dates = (UserDefaults.standard.dictionary(forKey: dateKey) as? [String: Double]) ?? [:]
            dates.removeValue(forKey: peerID)
            UserDefaults.standard.set(dates, forKey: dateKey)
        }
    }

    // MARK: - Fingerprint helpers

    static func fingerprint(for publicKeyData: Data) -> String {
        let digest = SHA256.hash(data: publicKeyData)
        // Short, human-friendly fingerprint: 16 bytes / 32 hex chars grouped.
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let short = String(hex.prefix(32))
        return short.chunked(every: 4).joined(separator: " ")
    }

    static func normalize(_ fingerprint: String) -> String {
        return fingerprint.lowercased().replacingOccurrences(of: " ", with: "")
    }
}

private extension String {
    func chunked(every size: Int) -> [String] {
        guard size > 0 else { return [self] }
        var out: [String] = []
        var idx = startIndex
        while idx < endIndex {
            let next = index(idx, offsetBy: size, limitedBy: endIndex) ?? endIndex
            out.append(String(self[idx..<next]))
            idx = next
        }
        return out
    }
}


extension Notification.Name {
    static let bitPeerIdentityChanged = Notification.Name("bit.peerIdentityChanged")
}
