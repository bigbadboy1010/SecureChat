// SecureChat/BIT/Crypto/ChannelSenderKeyCrypto.swift
//
// Sender-Keys (Signal Group-style baseline) for BIT channels:
// - Base key: channel key (password-derived or random channel key)
// - Sender seed: HKDF(baseKey, "bit-chan-sender|<senderPeerID>")
// - Message keys: deterministic KDF chain per sender
//
// Packet format (channel encrypted content v3):
// [0x53][n:UInt32 BE][ts:UInt32 BE][msgId:UInt64 BE][nonce:12][ciphertext][tag:16]
// AAD = [0x53][n][ts][msgId]
//
// Hard break: replaces legacy AES.GCM(combined) channel payloads.

import Foundation
import CryptoKit

enum ChannelCryptoError: Error {
    case invalidFormat
    case tooLarge
    case decryptFailed
}

struct ChannelSenderKeyCrypto {

    // MARK: - Public API

    static func parseHeader(packet: Data) -> (n: UInt32, ts: UInt32, msgId: UInt64)? {
        guard packet.count >= 1 + 4 + 4 + 8 else { return nil }
        guard packet[0] == 0x53 else { return nil }
        let n = readU32be(packet, offset: 1)
        let ts = readU32be(packet, offset: 1 + 4)
        let msgId = readU64be(packet, offset: 1 + 4 + 4)
        return (n, ts, msgId)
    }

    static func encrypt(
        content: Data,
        channelKey: SymmetricKey,
        senderPeerID: String,
        messageNumber: UInt32,
        timestamp: UInt32,
        messageId: UInt64
    ) throws -> Data {
        let seed = deriveSenderSeed(channelKey: channelKey, senderPeerID: senderPeerID)

        // Walk chain from seed to messageNumber deterministically (bounded)
        var chainKey = seed
        if messageNumber > 5000 { throw ChannelCryptoError.tooLarge }
        if messageNumber > 0 {
            for i in 0..<messageNumber {
                chainKey = deriveNextChainKey(chainKey: chainKey, messageNumber: i)
            }
        }

        let messageKey = deriveMessageKey(chainKey: chainKey, messageNumber: messageNumber)
        let nonce = AES.GCM.Nonce()
        let aad = buildAAD(n: messageNumber, ts: timestamp, msgId: messageId)

        let sealed = try AES.GCM.seal(content, using: messageKey, nonce: nonce, authenticating: aad)

        var out = Data()
        out.append(0x53)
        out.append(u32be(messageNumber))
        out.append(u32be(timestamp))
        out.append(u64be(messageId))
        out.append(contentsOf: nonce)
        out.append(sealed.ciphertext)
        out.append(sealed.tag)
        return out
    }

    static func decrypt(packet: Data, channelKey: SymmetricKey, senderPeerID: String) throws -> Data {
        guard packet.count >= 1 + 4 + 4 + 8 + 12 + 16 else { throw ChannelCryptoError.invalidFormat }
        guard packet[0] == 0x53 else { throw ChannelCryptoError.invalidFormat }

        let n = readU32be(packet, offset: 1)
        if n > 5000 { throw ChannelCryptoError.tooLarge }

        let ts = readU32be(packet, offset: 1 + 4)
        let msgId = readU64be(packet, offset: 1 + 4 + 4)

        let nonceStart = 1 + 4 + 4 + 8
        let nonceBytes = packet[nonceStart..<nonceStart + 12]

        let tagStart = packet.count - 16
        let ctStart = nonceStart + 12
        guard tagStart > ctStart else { throw ChannelCryptoError.invalidFormat }

        let ciphertext = packet[ctStart..<tagStart]
        let tag = packet[tagStart..<packet.count]
        let nonce = try AES.GCM.Nonce(data: nonceBytes)

        // Re-derive same message key
        let seed = deriveSenderSeed(channelKey: channelKey, senderPeerID: senderPeerID)
        var chainKey = seed
        if n > 0 {
            for i in 0..<n {
                chainKey = deriveNextChainKey(chainKey: chainKey, messageNumber: i)
            }
        }
        let messageKey = deriveMessageKey(chainKey: chainKey, messageNumber: n)

        let aad = buildAAD(n: n, ts: ts, msgId: msgId)
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        do {
            return try AES.GCM.open(box, using: messageKey, authenticating: aad)
        } catch {
            throw ChannelCryptoError.decryptFailed
        }
    }

    // MARK: - KDF

    static func deriveSenderSeed(channelKey: SymmetricKey, senderPeerID: String) -> SymmetricKey {
        let info = "bit-chan-sender|\(senderPeerID)".data(using: .utf8) ?? Data()
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: channelKey, salt: Data(), info: info, outputByteCount: 32)
    }

    static func deriveMessageKey(chainKey: SymmetricKey, messageNumber: UInt32) -> SymmetricKey {
        let info = "mk|\(messageNumber)".data(using: .utf8) ?? Data()
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: chainKey, salt: Data(), info: info, outputByteCount: 32)
    }

    static func deriveNextChainKey(chainKey: SymmetricKey, messageNumber: UInt32) -> SymmetricKey {
        let info = "ck|\(messageNumber)".data(using: .utf8) ?? Data()
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: chainKey, salt: Data(), info: info, outputByteCount: 32)
    }

    // MARK: - AAD / Encoding helpers

    private static func buildAAD(n: UInt32, ts: UInt32, msgId: UInt64) -> Data {
        var d = Data()
        d.append(0x53)
        d.append(u32be(n))
        d.append(u32be(ts))
        d.append(u64be(msgId))
        return d
    }

    private static func u32be(_ v: UInt32) -> Data {
        var x = v.bigEndian
        return Data(bytes: &x, count: 4)
    }

    private static func u64be(_ v: UInt64) -> Data {
        var x = v.bigEndian
        return Data(bytes: &x, count: 8)
    }

    private static func readU32be(_ data: Data, offset: Int) -> UInt32 {
        let sub = data[offset..<offset + 4]
        return sub.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }

    private static func readU64be(_ data: Data, offset: Int) -> UInt64 {
        let sub = data[offset..<offset + 8]
        return sub.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
    }
}
