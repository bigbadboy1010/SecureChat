import CryptoKit
import Foundation

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
}

protocol IdentityManaging {
    func loadOrCreateLocalIdentity(displayName: String) throws -> LocalIdentity
    func exportPairingPayload(identity: LocalIdentity) throws -> String
    func importPairingPayload(_ encodedPayload: String) throws -> TrustedPeer
}

final class IdentityManager: IdentityManaging {
    private enum Account {
        static let keyAgreementPrivateKey = "identity.keyAgreement.private.v1"
        static let signingPrivateKey = "identity.signing.private.v1"
    }

    private enum Pairing {
        static let urlPrefix = "privatechat://pairing/"
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

        let identityID = crypto.peerID(publicKeyData: signingPrivateKey.publicKey.rawRepresentation)
        return LocalIdentity(
            id: identityID,
            displayName: Self.normalizedDisplayName(displayName),
            keyAgreementPrivateKey: keyAgreementPrivateKey,
            signingPrivateKey: signingPrivateKey
        )
    }

    func exportPairingPayload(identity: LocalIdentity) throws -> String {
        let payload = PairingPayload(
            version: 2,
            displayName: Self.normalizedDisplayName(identity.displayName),
            keyAgreementPublicKeyBase64: identity.keyAgreementPublicKeyData.base64EncodedString(),
            signingPublicKeyBase64: identity.signingPublicKeyData.base64EncodedString(),
            createdAt: Date()
        )
        let data = try encoder.encode(payload)
        return Pairing.urlPrefix + Base64URL.encode(data)
    }

    func importPairingPayload(_ encodedPayload: String) throws -> TrustedPeer {
        let normalizedPayload = encodedPayload
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: Pairing.urlPrefix, with: "")

        guard let payloadData = Base64URL.decode(normalizedPayload) else {
            throw PrivateChatError.invalidPairingPayload
        }

        let payload = try decoder.decode(PairingPayload.self, from: payloadData)
        guard [1, 2].contains(payload.version),
              let signingPublicKeyData = Data(base64Encoded: payload.signingPublicKeyBase64),
              Data(base64Encoded: payload.keyAgreementPublicKeyBase64) != nil else {
            throw PrivateChatError.invalidPairingPayload
        }

        let peerID = crypto.peerID(publicKeyData: signingPublicKeyData)
        return TrustedPeer(
            id: peerID,
            displayName: Self.normalizedDisplayName(payload.displayName),
            keyAgreementPublicKeyBase64: payload.keyAgreementPublicKeyBase64,
            signingPublicKeyBase64: payload.signingPublicKeyBase64,
            safetyNumber: crypto.safetyNumber(peerID: peerID),
            trustState: .unverified
        )
    }

    private static func normalizedDisplayName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return "PrivateChat Peer"
        }
        return String(trimmed.prefix(80))
    }
}
