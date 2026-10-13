import CryptoKit
import Foundation
import OSLog

struct LocalIdentity {
    let id: String
    let displayName: String
    let keyAgreementPrivateKey: Curve25519.KeyAgreement.PrivateKey
    let signingPrivateKey: Curve25519.Signing.PrivateKey

    var keyAgreementPublicKeyData: Data {
        keyAgreementPrivateKey.publicKey.rawRepresentation
    }

    var signingPublicKeyData: Data {
        signingPrivateKey.publicKey.rawRepresentation
    }
}

struct PairingPayload: Codable, Equatable {
    let version: Int
    let displayName: String
    let keyAgreementPublicKeyBase64: String
    let signingPublicKeyBase64: String
    let createdAt: Date
    let signatureBase64: String?

    init(
        version: Int,
        displayName: String,
        keyAgreementPublicKeyBase64: String,
        signingPublicKeyBase64: String,
        createdAt: Date,
        signatureBase64: String? = nil
    ) {
        self.version = version
        self.displayName = displayName
        self.keyAgreementPublicKeyBase64 = keyAgreementPublicKeyBase64
        self.signingPublicKeyBase64 = signingPublicKeyBase64
        self.createdAt = createdAt
        self.signatureBase64 = signatureBase64
    }

    /// A length-delimited, domain-separated commitment to the complete
    /// public identity. JSON serialization and field order are not part
    /// of the signature format. Dates use the wire's whole-second format.
    var authenticatedData: Data {
        let fields = [
            "PrivateRoom/pairing/v3",
            String(version),
            displayName,
            signingPublicKeyBase64,
            keyAgreementPublicKeyBase64,
            DateCoding.string(from: createdAt)
        ]
        var result = Data()
        for field in fields {
            let bytes = Data(field.utf8)
            var length = UInt32(bytes.count).bigEndian
            withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
            result.append(bytes)
        }
        return result
    }
}

protocol IdentityManaging {
    func loadOrCreateLocalIdentity(displayName: String) throws -> LocalIdentity
    func updateDisplayName(_ displayName: String, identity: LocalIdentity) throws -> LocalIdentity
    func exportPairingPayload(identity: LocalIdentity) throws -> String
    func importPairingPayload(_ encodedPayload: String) throws -> TrustedPeer
}

final class IdentityManager: IdentityManaging, PeerBoundSigningContext {
    private static let logger = Logger(subsystem: "org.francois.PrivateChat", category: "IdentityManager")
    private enum Account {
        static let keyAgreementPrivateKey = "identity.keyAgreement.private.v1"
        static let signingPrivateKey = "identity.signing.private.v1"
        static let displayName = "identity.displayName.v1"
    }

    private enum Pairing {
        static let urlPrefix = "privateroom://pairing/"
        static let acceptedPrefixes = [urlPrefix, "privatechat://pairing/", "securechat://pairing/"]
        static let maximumEncodedBytes = 8_192
        static let maximumDecodedBytes = 4_096
    }

    private let keychain: KeychainStoring
    private let crypto: CryptoServicing
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(keychain: KeychainStoring, crypto: CryptoServicing) {
        self.keychain = keychain
        self.crypto = crypto
        self.decoder = DateCoding.makeDecoder()
        self.encoder = DateCoding.makeEncoder()
    }

    func loadOrCreateLocalIdentity(displayName: String) throws -> LocalIdentity {
        let keyAgreementPrivateKey: Curve25519.KeyAgreement.PrivateKey
        if let storedKeyAgreementData = try keychain.readData(account: Account.keyAgreementPrivateKey) {
            keyAgreementPrivateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: storedKeyAgreementData)
        } else {
            keyAgreementPrivateKey = Curve25519.KeyAgreement.PrivateKey()
            try keychain.writeData(keyAgreementPrivateKey.rawRepresentation, account: Account.keyAgreementPrivateKey)
        }

        let signingPrivateKey: Curve25519.Signing.PrivateKey
        if let storedSigningData = try keychain.readData(account: Account.signingPrivateKey) {
            signingPrivateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: storedSigningData)
        } else {
            signingPrivateKey = Curve25519.Signing.PrivateKey()
            try keychain.writeData(signingPrivateKey.rawRepresentation, account: Account.signingPrivateKey)
        }

        let storedDisplayName = try keychain.readData(account: Account.displayName)
            .flatMap { String(data: $0, encoding: .utf8) }
        let effectiveDisplayName = Self.normalizedDisplayName(storedDisplayName ?? displayName)
        if storedDisplayName == nil {
            try keychain.writeData(Data(effectiveDisplayName.utf8), account: Account.displayName)
        }

        let identityID = crypto.peerID(publicKeyData: signingPrivateKey.publicKey.rawRepresentation)
        return LocalIdentity(
            id: identityID,
            displayName: effectiveDisplayName,
            keyAgreementPrivateKey: keyAgreementPrivateKey,
            signingPrivateKey: signingPrivateKey
        )
    }

    func updateDisplayName(_ displayName: String, identity: LocalIdentity) throws -> LocalIdentity {
        let normalizedName = Self.normalizedDisplayName(displayName)
        try keychain.writeData(Data(normalizedName.utf8), account: Account.displayName)
        return LocalIdentity(
            id: identity.id,
            displayName: normalizedName,
            keyAgreementPrivateKey: identity.keyAgreementPrivateKey,
            signingPrivateKey: identity.signingPrivateKey
        )
    }

    func exportPairingPayload(identity: LocalIdentity) throws -> String {
        let unsignedPayload = PairingPayload(
            version: 3,
            displayName: Self.normalizedDisplayName(identity.displayName),
            keyAgreementPublicKeyBase64: identity.keyAgreementPublicKeyData.base64EncodedString(),
            signingPublicKeyBase64: identity.signingPublicKeyData.base64EncodedString(),
            createdAt: Date()
        )
        let signature = try crypto.sign(unsignedPayload.authenticatedData, privateKey: identity.signingPrivateKey)
        let payload = PairingPayload(
            version: unsignedPayload.version,
            displayName: unsignedPayload.displayName,
            keyAgreementPublicKeyBase64: unsignedPayload.keyAgreementPublicKeyBase64,
            signingPublicKeyBase64: unsignedPayload.signingPublicKeyBase64,
            createdAt: unsignedPayload.createdAt,
            signatureBase64: signature.base64EncodedString()
        )
        let data = try encoder.encode(payload)
        return Pairing.urlPrefix + Base64URL.encode(data)
    }

    func importPairingPayload(_ encodedPayload: String) throws -> TrustedPeer {
        guard encodedPayload.utf8.count <= Pairing.maximumEncodedBytes else {
            throw PrivateChatError.invalidPairingPayload
        }
        var normalizedPayload = encodedPayload.trimmingCharacters(in: .whitespacesAndNewlines)
        if let prefix = Pairing.acceptedPrefixes.first(where: { normalizedPayload.hasPrefix($0) }) {
            normalizedPayload.removeFirst(prefix.count)
        }

        guard normalizedPayload.isEmpty == false,
              normalizedPayload.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil,
              let payloadData = Base64URL.decode(normalizedPayload),
              payloadData.count <= Pairing.maximumDecodedBytes else {
            throw PrivateChatError.invalidPairingPayload
        }

        let payload = try decoder.decode(PairingPayload.self, from: payloadData)
        guard [1, 2, 3].contains(payload.version),
              payload.displayName.utf8.count <= 320,
              payload.createdAt.timeIntervalSince1970.isFinite,
              let signingPublicKeyData = Data(base64Encoded: payload.signingPublicKeyBase64),
              let keyAgreementPublicKeyData = Data(base64Encoded: payload.keyAgreementPublicKeyBase64),
              signingPublicKeyData.count == 32,
              keyAgreementPublicKeyData.count == 32,
              signingPublicKeyData.base64EncodedString() == payload.signingPublicKeyBase64,
              keyAgreementPublicKeyData.base64EncodedString() == payload.keyAgreementPublicKeyBase64,
              let remoteSigningKey = try? Curve25519.Signing.PublicKey(rawRepresentation: signingPublicKeyData),
              let remoteAgreementKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: keyAgreementPublicKeyData) else {
            throw PrivateChatError.invalidPairingPayload
        }
        if payload.version == 3 {
            guard let encodedSignature = payload.signatureBase64,
                  let signature = Data(base64Encoded: encodedSignature),
                  signature.count == 64,
                  encodedSignature == signature.base64EncodedString(),
                  crypto.verify(signature: signature, data: payload.authenticatedData, publicKey: remoteSigningKey) else {
                throw PrivateChatError.invalidPairingPayload
            }
        }

        guard let localSigningPrivateKeyData = try keychain.readData(account: Account.signingPrivateKey) else {
            throw PrivateChatError.invalidKeyMaterial
        }
        let localSigningPrivateKey = try Curve25519.Signing.PrivateKey(
            rawRepresentation: localSigningPrivateKeyData
        )
        guard let localAgreementPrivateKeyData = try keychain.readData(account: Account.keyAgreementPrivateKey) else {
            throw PrivateChatError.invalidKeyMaterial
        }
        let localAgreementPrivateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: localAgreementPrivateKeyData)
        // Reject low-order X25519 inputs (including all-zero keys) before
        // allowing a contact into the trust store.
        do {
            let shared = try localAgreementPrivateKey.sharedSecretFromKeyAgreement(with: remoteAgreementKey)
            guard shared.withUnsafeBytes({ bytes in bytes.contains { $0 != 0 } }) else {
                throw PrivateChatError.invalidPairingPayload
            }
        } catch {
            throw PrivateChatError.invalidPairingPayload
        }

        let peerID = crypto.peerID(publicKeyData: signingPublicKeyData)
        let safetyNumber = SafetyNumberV3.make(
            localSigningPublicKeyData: localSigningPrivateKey.publicKey.rawRepresentation,
            localKeyAgreementPublicKeyData: localAgreementPrivateKey.publicKey.rawRepresentation,
            remoteSigningPublicKeyData: signingPublicKeyData,
            remoteKeyAgreementPublicKeyData: keyAgreementPublicKeyData
        )
        return TrustedPeer(
            id: peerID,
            displayName: Self.normalizedDisplayName(payload.displayName),
            keyAgreementPublicKeyBase64: payload.keyAgreementPublicKeyBase64,
            signingPublicKeyBase64: payload.signingPublicKeyBase64,
            safetyNumber: safetyNumber,
            trustState: .unverified
        )
    }

    private static func normalizedDisplayName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return "PrivateChat Peer"
        }

        let collapsedWhitespace = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let allowedPunctuation = CharacterSet(charactersIn: " .-_'")
        let allowedScalars = CharacterSet.alphanumerics.union(allowedPunctuation)
        let sanitizedScalars = collapsedWhitespace.unicodeScalars.filter { allowedScalars.contains($0) }
        let sanitized = String(String.UnicodeScalarView(sanitizedScalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard sanitized.isEmpty == false else {
            return "PrivateChat Peer"
        }
        return String(sanitized.prefix(80))
    }

    // MARK: - PeerBoundSigningContext

    // Sprint 15B: the relay's peer-bound
    // request signing layer needs the
    // peer's long-form public peer ID and
    // the long-term Ed25519 signing
    // private key. Both come from the
    // existing keychain-resident local
    // identity. The transport calls these
    // helpers once per outgoing request.
    public func currentPeerID() -> String? {
        do {
            let identity = try loadOrCreateLocalIdentity(displayName: "")
            return identity.id
        } catch {
            Self.logger.error("PeerBoundSigningContext.currentPeerID failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func currentSigningPrivateKey() -> Curve25519.Signing.PrivateKey? {
        do {
            return try loadOrCreateLocalIdentity(displayName: "").signingPrivateKey
        } catch {
            Self.logger.error(
                "PeerBoundSigningContext.currentSigningPrivateKey failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }
}
