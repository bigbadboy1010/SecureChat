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

    let sessionID: String
    var rootKey: SymmetricKey
    var sendChainKey: SymmetricKey?
    var recvChainKey: SymmetricKey?
    var sendCounter: Int
    var recvCounter: Int
    var dhRatchetKeyPair: Curve25519.KeyAgreement.PrivateKey
    var remoteRatchetPK: Curve25519.KeyAgreement.PublicKey?
    var previousSendChainLength: Int = 0
    var skippedMessageKeys: [(chainKey: SymmetricKey, counter: Int)] = []
    let maxSkippedKeys: Int

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
        // If we already know the remote's initial ratchet PK
        // (X3DH pre-exchange), pre-derive the receive chain key
        // so the first message can be decrypted without a
        // separate dhratchetIncoming step.
        if let remotePK = initialRemoteRatchetPublicKey {
            do {
                let shared = try initialRatchetPrivateKey.sharedSecretFromKeyAgreement(with: remotePK)
                let (_, newRecvChain) = kdfRK(
                    rootKey: self.rootKey,
                    dhOutput: shared.withUnsafeBytes { Data($0) }
                )
                self.recvChainKey = newRecvChain
            } catch {
                // If the DH fails for any reason, the first
                // message will trigger dhratchetIncoming on
                // decrypt (the fallback path).
                self.recvChainKey = nil
            }
        }
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
        // On the very first message we have already
        // pre-derived the receive chain (see
        // `initialiseReceiveChainIfNeeded` below) so the
        // first decrypt succeeds without a fresh
        // dhratchetIncoming.
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

        // Step the receive chain forward to fill in any
        // skipped-message keys for out-of-order delivery.
        // The loop runs only when recvCounter is strictly
        // less than message.counter (i.e. the final step
        // `message.counter` is left for the next block
        // below). This keeps the per-message kdfCK call
        // count on the receiver side equal to the sender
        // side (both call kdfCK exactly once per message).
        while recvCounter < message.counter - 1 {
            let (nextChainKey, messageKey) = try stepRecvChain()
            recvChainKey = nextChainKey
            recvCounter += 1
            skippedMessageKeys.append((messageKey, recvCounter))
            if skippedMessageKeys.count > maxSkippedKeys {
                skippedMessageKeys.removeFirst()
            }
        }
        // Now compute the message key for `message.counter`
        // exactly once, matching what the sender did.
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
        // 2. The first ratchet step is special: we keep the
        // **current** ratchet keypair (the X3DH initial one)
        // and only install a fresh one on the SECOND and later
        // steps. This keeps the first DH step symmetric with
        // the receiver's first `dhratchetIncoming` (which also
        // uses the X3DH initial keys).
        let newPair: Curve25519.KeyAgreement.PrivateKey
        let isFirstStep = previousSendChainLength == 0
        if isFirstStep {
            newPair = dhRatchetKeyPair // no rotation on the first step
        } else {
            newPair = Curve25519.KeyAgreement.PrivateKey()
        }
        let newPublic = newPair.publicKey

        // 3. Run the DH agreement using the **current**
        // dhRatchetKeyPair (which is still the X3DH initial
        // one on the first step) against the remote's
        // initial ratchet PK. On later steps we use the
        // remote's most recent ratchet PK.
        if let remotePK = remoteRatchetPK {
            let shared = try dhRatchetKeyPair.sharedSecretFromKeyAgreement(with: remotePK)
            let (newRoot, newSendChain) = kdfRK(rootKey: rootKey, dhOutput: shared.withUnsafeBytes { Data($0) })
            rootKey = newRoot
            sendChainKey = newSendChain
        } else {
            // No remote ratchet PK (degenerate fallback).
            let (newRoot, newSendChain) = kdfRK(rootKey: rootKey, dhOutput: Data())
            rootKey = newRoot
            sendChainKey = newSendChain
        }
        if !isFirstStep {
            dhRatchetKeyPair = newPair
        }
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

    // MARK: - Live-state export / restore (Sprint 10B)

    /// Codable snapshot of the live ratchet state
    /// (everything except the initial X3DH bundle
    /// material that is already in
    /// `PersistedRatchetSession`). Used by
    /// `RatchetChannel` to persist the in-flight
    /// chain keys, counters, DH ratchet keypair,
    /// and the skipped-message-key window so a
    /// conversation that has progressed past the
    /// initial-bundle phase survives an app
    /// relaunch.
    public struct LiveState: Codable, Equatable {
        /// 32-byte symmetric key.
        public let rootKey: Data
        /// 32-byte symmetric key, optional (nil
        /// before the first outgoing ratchet
        /// step).
        public let sendChainKey: Data?
        /// 32-byte symmetric key, optional (nil
        /// before the first incoming ratchet
        /// step or initial-bundle phase).
        public let recvChainKey: Data?
        /// Counter of the next outgoing message
        /// in the current send chain.
        public let sendCounter: Int
        /// Counter of the next expected incoming
        /// message in the current recv chain.
        public let recvCounter: Int
        /// 32-byte X25519 private key for the
        /// current ratchet keypair. After the
        /// first DH ratchet step this is rotated
        /// from the X3DH initial-bundle key, so
        /// persisting it is required to keep
        /// the chain consistent across
        /// relaunches.
        public let dhRatchetPrivateKey: Data
        /// 32-byte X25519 public key for the
        /// remote's current ratchet keypair, or
        /// nil if no incoming ratchet step has
        /// happened yet.
        public let remoteRatchetPublicKey: Data?
        /// Number of messages sent in the
        /// **previous** send chain. Used by the
        /// receiver to skip the correct number
        /// of message keys after a ratchet
        /// rotation.
        public let previousSendChainLength: Int
        /// (chain key data, counter) pairs that
        /// have been stepped but not yet
        /// delivered. Capped at the session's
        /// `maxSkippedKeys`.
        public let skippedMessageKeys: [SkippedKey]

        public struct SkippedKey: Codable, Equatable {
            public let chainKey: Data
            public let counter: Int
            public init(chainKey: Data, counter: Int) {
                self.chainKey = chainKey
                self.counter = counter
            }
        }
    }

    /// Snapshot the current live state. Callers
    /// (the `RatchetChannel`) should invoke this
    /// after every `encrypt` / `decrypt` and
    /// before the next app-launched-save point.
    public func exportLiveState() -> LiveState {
        LiveState(
            rootKey: rootKey.withUnsafeBytes { Data($0) },
            sendChainKey: sendChainKey.map { $0.withUnsafeBytes { Data($0) } },
            recvChainKey: recvChainKey.map { $0.withUnsafeBytes { Data($0) } },
            sendCounter: sendCounter,
            recvCounter: recvCounter,
            dhRatchetPrivateKey: dhRatchetKeyPair.rawRepresentation,
            remoteRatchetPublicKey: remoteRatchetPK?.rawRepresentation,
            previousSendChainLength: previousSendChainLength,
            skippedMessageKeys: skippedMessageKeys.map {
                .init(
                    chainKey: $0.chainKey.withUnsafeBytes { Data($0) },
                    counter: $0.counter
                )
            }
        )
    }

    /// Restore live state from a previous
    /// `exportLiveState()` snapshot. The session
    /// is left in the same state as it was at
    /// export time; subsequent `encrypt` / `decrypt`
    /// calls continue the chain as if no
    /// relaunch had happened.
    public func restoreLiveState(_ state: LiveState) throws {
        precondition(state.rootKey.count == 32, "rootKey must be 32 bytes")
        rootKey = SymmetricKey(data: state.rootKey)
        sendChainKey = state.sendChainKey.map { SymmetricKey(data: $0) }
        recvChainKey = state.recvChainKey.map { SymmetricKey(data: $0) }
        sendCounter = state.sendCounter
        recvCounter = state.recvCounter
        dhRatchetKeyPair = try Curve25519.KeyAgreement.PrivateKey(
            rawRepresentation: state.dhRatchetPrivateKey
        )
        if let remotePKData = state.remoteRatchetPublicKey {
            remoteRatchetPK = try Curve25519.KeyAgreement.PublicKey(
                rawRepresentation: remotePKData
            )
        } else {
            remoteRatchetPK = nil
        }
        previousSendChainLength = state.previousSendChainLength
        skippedMessageKeys = state.skippedMessageKeys.map {
            (SymmetricKey(data: $0.chainKey), $0.counter)
        }
    }
}
