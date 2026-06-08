// SecureChat/BIT/Crypto/DoubleRatchet.swift
//
// Full Double Ratchet (DH-Ratchet) for private chats.
// Implements:
// - X25519 DH ratchet (Curve25519.KeyAgreement)
// - HKDF-SHA256 for root/chain/message keys
// - Per-message symmetric encryption via AES-256-GCM
// - Skipped message keys window for out-of-order delivery
//
// Packet format (private message v3):
// [0x03]
// [pn: UInt32 BE]  (previous sending chain length)
// [n:  UInt32 BE]  (message number in current sending chain)
// [dhPub: 32]      (sender current DH public key)
// [nonce: 12]
// [ciphertext ...][tag:16]
//
// AAD = [0x03][pn][n][dhPub]  (binds header to ciphertext)
//
// Note: This is a hard-break protocol; both sides must run v3 for private messages.

import Foundation
import CryptoKit

enum DoubleRatchetError: Error {
    case missingPeerKey
    case invalidPacket
    case cannotDecrypt
    case tooFarAhead
}

struct DoubleRatchetSession: Codable {
    // Root key
    private var rootKeyRaw: Data

    // Our DH key pair
    private var dhsPrivateRaw: Data
    private var dhsPublicRaw: Data

    // Their DH public key
    private var dhrPublicRaw: Data?

    // Chain keys
    private var cksRaw: Data?
    private var ckrRaw: Data?

    // Message numbers
    private var ns: UInt32
    private var nr: UInt32
    private var pn: UInt32

    // Skipped message keys: key = "base64(dhPub)|n"
    private var skipped: [String: Data]
    private var skippedOrder: [String]

    static let maxSkip: UInt32 = 64
    static let maxSkipAhead: UInt32 = 50

    init(bootstrapWith peerDHPublic: Curve25519.KeyAgreement.PublicKey) throws {
        let dhs = Curve25519.KeyAgreement.PrivateKey()
        self.dhsPrivateRaw = dhs.rawRepresentation
        self.dhsPublicRaw = dhs.publicKey.rawRepresentation
        self.dhrPublicRaw = peerDHPublic.rawRepresentation

        let rk = try Self.kdfRoot(from: dhs, peerPub: peerDHPublic, currentRoot: nil)
        self.rootKeyRaw = rk.root
        self.cksRaw = rk.cks
        self.ckrRaw = rk.ckr

        self.ns = 0
        self.nr = 0
        self.pn = 0
        self.skipped = [:]
        self.skippedOrder = []
    }

    // MARK: - Public API

    mutating func encrypt(plaintext: Data) throws -> Data {
        guard let cksRaw else { throw DoubleRatchetError.missingPeerKey }
        let dhPub = dhsPublicRaw

        let (msgKeyRaw, nextCK) = Self.kdfChain(chainKeyRaw: cksRaw)
        self.cksRaw = nextCK

        let header = Self.buildHeader(pn: pn, n: ns, dhPub: dhPub)
        let aad = header

        let msgKey = SymmetricKey(data: msgKeyRaw)
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(plaintext, using: msgKey, nonce: nonce, authenticating: aad)

        var out = Data()
        out.append(header)
        out.append(contentsOf: nonce)
        out.append(sealed.ciphertext)
        out.append(sealed.tag)

        ns &+= 1
        return out
    }

    mutating func decrypt(packet: Data) throws -> Data {
        // 1) try skipped
        if let (dhPub, pnVal, nVal, nonce, ciphertext, tag) = Self.parsePacket(packet: packet) {
            let skippedKeyId = Self.skippedKeyId(dhPub: dhPub, n: nVal)
            if let mk = skipped[skippedKeyId] {
                consumeSkipped(id: skippedKeyId)
                let aad = Self.buildHeader(pn: pnVal, n: nVal, dhPub: dhPub)
                return try Self.aesOpen(mkRaw: mk, nonce: nonce, ciphertext: ciphertext, tag: tag, aad: aad)
            }

            // 2) if DH changed => DH ratchet
            if dhrPublicRaw != dhPub {
                try skipMessageKeys(until: pnVal) // skip remaining from old receiving chain
                try dhRatchet(newDhrPubRaw: dhPub)
            }

            // 3) now derive keys up to n
            guard let ckrRaw else { throw DoubleRatchetError.missingPeerKey }

            if nVal > nr + Self.maxSkipAhead {
                throw DoubleRatchetError.tooFarAhead
            }

            var ck = ckrRaw
            while nr < nVal {
                let (mk, nextCK) = Self.kdfChain(chainKeyRaw: ck)
                storeSkipped(dhPub: dhPub, n: nr, mkRaw: mk)
                ck = nextCK
                nr &+= 1
            }

            // derive target
            let (mkRaw, nextCK) = Self.kdfChain(chainKeyRaw: ck)
            self.ckrRaw = nextCK
            nr &+= 1

            let aad = Self.buildHeader(pn: pnVal, n: nVal, dhPub: dhPub)
            return try Self.aesOpen(mkRaw: mkRaw, nonce: nonce, ciphertext: ciphertext, tag: tag, aad: aad)
        }

        throw DoubleRatchetError.invalidPacket
    }

    // MARK: - DH Ratchet

    private mutating func dhRatchet(newDhrPubRaw: Data) throws {
        // set PN, reset Ns/Nr
        pn = ns
        ns = 0
        nr = 0

        // update DHR
        dhrPublicRaw = newDhrPubRaw

        // derive receiving chain from DH(DHs, DHR)
        let dhs = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: dhsPrivateRaw)
        let dhr = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: newDhrPubRaw)

        let rk1 = try Self.kdfRoot(from: dhs, peerPub: dhr, currentRoot: SymmetricKey(data: rootKeyRaw))
        rootKeyRaw = rk1.root
        ckrRaw = rk1.ckr

        // rotate our DH key and derive sending chain from DH(newDHS, DHR)
        let newDhs = Curve25519.KeyAgreement.PrivateKey()
        dhsPrivateRaw = newDhs.rawRepresentation
        dhsPublicRaw = newDhs.publicKey.rawRepresentation

        let rk2 = try Self.kdfRoot(from: newDhs, peerPub: dhr, currentRoot: SymmetricKey(data: rootKeyRaw))
        rootKeyRaw = rk2.root
        cksRaw = rk2.cks
    }

    private mutating func skipMessageKeys(until pnVal: UInt32) throws {
        // When DH ratchets, skip any remaining receiving keys up to pnVal
        guard let ckrRaw else { return }
        var ck = ckrRaw
        while nr < pnVal {
            let (mk, nextCK) = Self.kdfChain(chainKeyRaw: ck)
            if let dhr = dhrPublicRaw {
                storeSkipped(dhPub: dhr, n: nr, mkRaw: mk)
            }
            ck = nextCK
            nr &+= 1
        }
        self.ckrRaw = ck
    }

    // MARK: - Skipped keys store

    private mutating func storeSkipped(dhPub: Data, n: UInt32, mkRaw: Data) {
        let id = Self.skippedKeyId(dhPub: dhPub, n: n)
        if skipped[id] != nil { return }
        skipped[id] = mkRaw
        skippedOrder.append(id)
        if skippedOrder.count > Int(Self.maxSkip) {
            let oldest = skippedOrder.removeFirst()
            skipped.removeValue(forKey: oldest)
        }
    }

    private mutating func consumeSkipped(id: String) {
        skipped.removeValue(forKey: id)
        skippedOrder.removeAll(where: { $0 == id })
    }

    private static func skippedKeyId(dhPub: Data, n: UInt32) -> String {
        let b64 = dhPub.base64EncodedString()
        return "\(b64)|\(n)"
    }

    // MARK: - KDFs

    private static func kdfRoot(from ourPriv: Curve25519.KeyAgreement.PrivateKey,
                                peerPub: Curve25519.KeyAgreement.PublicKey,
                                currentRoot: SymmetricKey?) throws -> (root: Data, cks: Data, ckr: Data) {
        let shared = try ourPriv.sharedSecretFromKeyAgreement(with: peerPub)
        let dhOut = shared.hkdfDerivedSymmetricKey(using: SHA256.self,
                                                   salt: Data(),
                                                   sharedInfo: Data(),
                                                   outputByteCount: 32)
        let rk = currentRoot ?? SymmetricKey(data: "bit-root-v3".data(using: .utf8)!)

        // Derive new root and two chain keys with HKDF, salt = current root
        let salt = rk.withUnsafeBytes { Data($0) }
        let rootKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: dhOut,
                                             salt: salt,
                                             info: "rk".data(using: .utf8)!,
                                             outputByteCount: 32)
        let cks = HKDF<SHA256>.deriveKey(inputKeyMaterial: dhOut,
                                         salt: salt,
                                         info: "cks".data(using: .utf8)!,
                                         outputByteCount: 32)
        let ckr = HKDF<SHA256>.deriveKey(inputKeyMaterial: dhOut,
                                         salt: salt,
                                         info: "ckr".data(using: .utf8)!,
                                         outputByteCount: 32)
        return (rootKey.withUnsafeBytes { Data($0) },
                cks.withUnsafeBytes { Data($0) },
                ckr.withUnsafeBytes { Data($0) })
    }

    private static func kdfChain(chainKeyRaw: Data) -> (mk: Data, nextCK: Data) {
        let ck = SymmetricKey(data: chainKeyRaw)
        let mk = HKDF<SHA256>.deriveKey(inputKeyMaterial: ck,
                                        salt: Data(),
                                        info: "mk".data(using: .utf8)!,
                                        outputByteCount: 32)
        let next = HKDF<SHA256>.deriveKey(inputKeyMaterial: ck,
                                          salt: Data(),
                                          info: "ck".data(using: .utf8)!,
                                          outputByteCount: 32)
        return (mk.withUnsafeBytes { Data($0) }, next.withUnsafeBytes { Data($0) })
    }

    // MARK: - Packet parsing/building

    private static func buildHeader(pn: UInt32, n: UInt32, dhPub: Data) -> Data {
        var out = Data()
        out.append(0x03)
        out.append(u32be(pn))
        out.append(u32be(n))
        out.append(dhPub)
        return out
    }

    private static func parsePacket(packet: Data) -> (dhPub: Data, pn: UInt32, n: UInt32, nonce: AES.GCM.Nonce, ciphertext: Data, tag: Data)? {
        // 최소 length: 1 + 4 + 4 + 32 + 12 + 16
        if packet.count < 1 + 4 + 4 + 32 + 12 + 16 { return nil }
        if packet[0] != 0x03 { return nil }

        let pn = readU32be(packet, offset: 1)
        let n = readU32be(packet, offset: 1 + 4)
        let dhStart = 1 + 4 + 4
        let dhPub = packet[dhStart..<dhStart+32]
        let nonceStart = dhStart + 32
        let nonceBytes = packet[nonceStart..<nonceStart+12]
        let restStart = nonceStart + 12
        let tagStart = packet.count - 16
        if tagStart <= restStart { return nil }
        let ct = packet[restStart..<tagStart]
        let tag = packet[tagStart..<packet.count]
        guard let nonce = try? AES.GCM.Nonce(data: nonceBytes) else { return nil }
        return (Data(dhPub), pn, n, nonce, Data(ct), Data(tag))
    }

    private static func aesOpen(mkRaw: Data, nonce: AES.GCM.Nonce, ciphertext: Data, tag: Data, aad: Data) throws -> Data {
        let key = SymmetricKey(data: mkRaw)
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(box, using: key, authenticating: aad)
    }

    private static func u32be(_ v: UInt32) -> Data {
        var x = v.bigEndian
        return Data(bytes: &x, count: 4)
    }

    private static func readU32be(_ data: Data, offset: Int) -> UInt32 {
        let sub = data[offset..<offset+4]
        return sub.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }
}
