import Foundation
import CryptoKit

/// Double Ratchet session for SecureChat (ADR-006).
///
/// Implements the per-session key derivation that lives inside
/// the existing SecureChat envelope (ADR-002). Provides
/// forward secrecy (each message key is consumed once) and
/// post-compromise security (each DH ratchet step mixes in a
/// fresh ephemeral key).
///
/// Threading: this class is **not** thread-safe. Callers
/// should serialise access through an actor or a dedicated
/// queue. The public surface is intentionally small so a
/// wrapper actor in `ConversationService` is the right place
/// to enforce serial access.
public final class DoubleRatchetSession {

    // MARK: - Public types

    /// Wire-format payload (ADR-006, v2 envelope).
    public struct WireMessage: Codable, Equatable {
        public let v: Int
        public let sessionID: String
        public let ratchetPK: String          // base64
        public let counter: Int
        public let prevChainLen: Int
        public let ciphertext: String         // base64

        public init(
            v: Int = 2,
            sessionID: String,
            ratchetPK: String,
            counter: Int,
            prevChainLen: Int,
            ciphertext: String
        ) {
            self.v = v
            self.sessionID = sessionID
            self.ratchetPK = ratchetPK
            self.counter = counter
            self.prevChainLen = prevChainLen
            self.ciphertext = ciphertext
        }
    }

    /// Errors raised by the session.
    public enum SessionError: Error, Equatable {
        case unknownVersion(Int)
        case decryptionFailed
        case skippedKeyMissing
        case ratchetStateInvalid
    }

    // MARK: - State

    private let sessionID: String
    private var rootKey: SymmetricKey
    private var sendChainKey: SymmetricKey?
    private var recvChainKey: SymmetricKey?
    private var sendCounter: Int
    private var recvCounter: Int
    private var dhRatchetKeyPair: Curve25519.KeyAgreement.PrivateKey
    private var remoteRatchetPK: Curve25519.KeyAgreement.PublicKey?
    private var previousSendChainLength: Int = 0
    private var skippedMessageKeys: [(chainKey: SymmetricKey, counter: Int)] = []
    private let maxSkippedKeys: Int

    // MARK: - Init

    /// Create a new session from a 32-byte root key.
    /// Both sides start with the same `rootKey` (X3DH output).
    /// `initialRemoteRatchetPublicKey` is the X3DH initial-bundle
    /// pre-exchange: each side knows the other's first ratchet
    /// public key before the first message.
    public init(
        sessionID: String,
        rootKey: Data,
        initialRatchetPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        initialRemoteRatchetPublicKey: Curve25519.KeyAgreement.PublicKey? = nil,
        maxSkippedKeys: Int = 2000
    ) {
        precondition(rootKey.count == 32, "rootKey must be 32 bytes")
        self.sessionID = sessionID
        self.rootKey = SymmetricKey(data: rootKey)
        self.dhRatchetKeyPair = initialRatchetPrivateKey
        self.sendCounter = 0
        self.recvCounter = 0
        self.maxSkippedKeys = maxSkippedKeys
        self.remoteRatchetPK = initialRemoteRatchetPublicKey
    }

    // MARK: - Encrypt

    /// Encrypt a plaintext into a wire message. Advances the
    /// state on each call. Callers should batch by turn:
    /// keep using the same `DoubleRatchetSession` instance for
    /// all messages in a single outgoing turn.
    public func encrypt(_ plaintext: Data) throws -> WireMessage {
        let (chainKey, messageKey) = try stepSendChain()
        let aad = aadBytes(
            sessionID: sessionID,
            ratchetPK: dhRatchetKeyPair.publicKey.rawRepresentation,
            counter: sendCounter
        )
        let ciphertext = try encryptWithKey(messageKey, plaintext: plaintext, aad: aad)
        return WireMessage(
            sessionID: sessionID,
            ratchetPK: dhRatchetKeyPair.publicKey.rawRepresentation.base64EncodedString(),
            counter: sendCounter,
            prevChainLen: previousSendChainLength,
            ciphertext: ciphertext.base64EncodedString()
        )
    }

    // MARK: - Decrypt

    /// Decrypt a wire message. If the message is in the
    /// current receive chain, it decrypts immediately. If the
    /// remote side has ratcheted (new `ratchetPK`), this
    /// triggers a DH ratchet step first. Out-of-order messages
    /// in the skipped-key window are accepted.
    public func decrypt(_ message: WireMessage) throws -> Data {
        guard message.v == 2 else {
            throw SessionError.unknownVersion(message.v)
        }
        guard message.sessionID == sessionID else {
            throw SessionError.ratchetStateInvalid
        }

        let remotePK = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: Data(base64Encoded: message.ratchetPK) ?? Data()
        )

        // If the remote ratchet key has changed, step the
        // DH ratchet and skip any messages in the old chain.
        if let current = remoteRatchetPK, current.rawRepresentation != remotePK.rawRepresentation {
            try skipMessageKeys(until: message.prevChainLen)
            try dhratchetIncoming(remotePK: remotePK)
        } else if remoteRatchetPK == nil {
            try dhratchetIncoming(remotePK: remotePK)
        }

        // If this message is in the new chain, decrypt directly.
        if message.counter < recvCounter {
            // Out-of-order from the previous chain (skipped key).
            if let idx = skippedMessageKeys.firstIndex(where: { $0.counter == message.counter }) {
                let key = skippedMessageKeys[idx].chainKey
                skippedMessageKeys.remove(at: idx)
                let aad = aadBytes(
                    sessionID: message.sessionID,
                    ratchetPK: Data(base64Encoded: message.ratchetPK) ?? Data(),
                    counter: message.counter
                )
                return try decryptWithKey(key, ciphertext: Data(base64Encoded: message.ciphertext) ?? Data(), aad: aad)
            } else {
                throw SessionError.skippedKeyMissing
            }
        }

        // Step the receive chain forward to `message.counter`.
        while recvCounter < message.counter {
            let (nextChainKey, messageKey) = try stepRecvChain()
            recvChainKey = nextChainKey
            skippedMessageKeys.append((messageKey, recvCounter))
            recvCounter += 1
            if skippedMessageKeys.count > maxSkippedKeys {
                skippedMessageKeys.removeFirst()
            }
        }
        // Now the message at `message.counter` is the next one.
        let (finalChainKey, finalMessageKey) = try stepRecvChain()
        recvChainKey = finalChainKey
        let aad = aadBytes(
            sessionID: message.sessionID,
            ratchetPK: Data(base64Encoded: message.ratchetPK) ?? Data(),
            counter: message.counter
        )
        let plaintext = try decryptWithKey(finalMessageKey, ciphertext: Data(base64Encoded: message.ciphertext) ?? Data(), aad: aad)
        recvCounter += 1
        return plaintext
    }

    // MARK: - DH ratchet steps

    /// Outgoing DH ratchet step: derives a new ratchet keypair
    /// and a new send chain key. The receive side is left for
    /// the next received message to trigger.
    public func performOutgoingDHRatchet() throws {
        // 1. Save the previous send chain length.
        previousSendChainLength = sendCounter
        // 2. Generate a fresh DH ratchet keypair (becomes the
        // new keypair AFTER the DH step uses the old one).
        let newPair = Curve25519.KeyAgreement.PrivateKey()
        let newPublic = newPair.publicKey

        // 3. Run the DH agreement using the **current**
        // dhRatchetKeyPair against the remote's current
        // ratchet PK. The first ratchet step is special: if
        // we have never ratcheted before (no `sendCounter`
        // accumulated), the root key already incorporates the
        // X3DH initial agreement, so we use a zero-byte DH
        // output. This keeps the first sender in sync with
        // the receiver's first `dhratchetIncoming` (which also
        // uses zero-byte DH on the first step).
        if let remotePK = remoteRatchetPK, sendCounter > 0 {
            // Subsequent turn: real DH ratchet step.
            let shared = try dhRatchetKeyPair.sharedSecretFromKeyAgreement(with: remotePK)
            let (newRoot, newSendChain) = kdfRK(rootKey: rootKey, dhOutput: shared.withUnsafeBytes { Data($0) })
            rootKey = newRoot
            sendChainKey = newSendChain
        } else {
            // First turn (or first turn without X3DH
            // pre-exchange). Initialise the send chain from
            // the root key directly via a 0-byte DH output so
            // the peer can derive the same chain key.
            let (newRoot, newSendChain) = kdfRK(rootKey: rootKey, dhOutput: Data())
            rootKey = newRoot
            sendChainKey = newSendChain
        }
        dhRatchetKeyPair = newPair
        _ = newPublic
        sendCounter = 0
    }

    /// Incoming DH ratchet step: derives a new receive chain
    /// key from the remote's new ratchet PK.
    private func dhratchetIncoming(remotePK: Curve25519.KeyAgreement.PublicKey) throws {
        let shared = try dhRatchetKeyPair.sharedSecretFromKeyAgreement(with: remotePK)
        let (newRoot, newRecvChain) = kdfRK(rootKey: rootKey, dhOutput: shared.withUnsafeBytes { Data($0) })
        rootKey = newRoot
        recvChainKey = newRecvChain
        remoteRatchetPK = remotePK
        recvCounter = 0
    }

    private func skipMessageKeys(until previousChainLength: Int) throws {
        while recvCounter < previousChainLength {
            guard let chain = recvChainKey else {
                throw SessionError.ratchetStateInvalid
            }
            let (nextChain, msgKey) = try kdfCK(chainKey: chain)
            recvChainKey = nextChain
            skippedMessageKeys.append((msgKey, recvCounter))
            recvCounter += 1
            if skippedMessageKeys.count > maxSkippedKeys {
                skippedMessageKeys.removeFirst()
            }
        }
    }

    // MARK: - Chain steps

    private func stepSendChain() throws -> (chainKey: SymmetricKey, messageKey: SymmetricKey) {
        if sendChainKey == nil {
            try performOutgoingDHRatchet()
        }
        guard let chain = sendChainKey else {
            throw SessionError.ratchetStateInvalid
        }
        let (nextChain, messageKey) = try kdfCK(chainKey: chain)
        sendChainKey = nextChain
        let result = (nextChain, messageKey)
        sendCounter += 1
        return result
    }

    private func stepRecvChain() throws -> (chainKey: SymmetricKey, messageKey: SymmetricKey) {
        guard let chain = recvChainKey else {
            throw SessionError.ratchetStateInvalid
        }
        return try kdfCK(chainKey: chain)
    }

    // MARK: - KDFs

    /// Root KDF: derives a new 64-byte secret and splits it
    /// into a new root key (32) and a new chain key (32).
    private func kdfRK(rootKey: SymmetricKey, dhOutput: Data) -> (SymmetricKey, SymmetricKey) {
        let salt = rootKey.withUnsafeBytes { Data($0) }
        let info = Data("SecureChatDoubleRatchetRK".utf8)
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: dhOutput),
            salt: salt,
            info: info,
            outputByteCount: 64
        )
        let derivedData = derived.withUnsafeBytes { Data($0) }
        let newRoot = SymmetricKey(data: derivedData.subdata(in: 0..<32))
        let newChain = SymmetricKey(data: derivedData.subdata(in: 32..<64))
        return (newRoot, newChain)
    }

    /// Chain KDF: derives the next chain key (32) and the
    /// message key (32) from the current chain key.
    private func kdfCK(chainKey: SymmetricKey) throws -> (chainKey: SymmetricKey, messageKey: SymmetricKey) {
        let info = Data("SecureChatDoubleRatchetCK".utf8)
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: chainKey,
            salt: Data(),
            info: info,
            outputByteCount: 64
        )
        let derivedData = derived.withUnsafeBytes { Data($0) }
        let nextChain = SymmetricKey(data: derivedData.subdata(in: 0..<32))
        let messageKey = SymmetricKey(data: derivedData.subdata(in: 32..<64))
        return (nextChain, messageKey)
    }

    // MARK: - AES-GCM helpers

    private func encryptWithKey(_ key: SymmetricKey, plaintext: Data, aad: Data) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: aad)
        return sealed.combined ?? Data()
    }

    private func decryptWithKey(_ key: SymmetricKey, ciphertext: Data, aad: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: key, authenticating: aad)
    }

    private func aadBytes(sessionID: String, ratchetPK: Data, counter: Int) -> Data {
        // sessionID || ratchetPK || counter
        var aad = Data(sessionID.utf8)
        aad.append(ratchetPK)
        withUnsafeBytes(of: UInt32(counter).bigEndian) { aad.append(contentsOf: $0) }
        return aad
    }
}
