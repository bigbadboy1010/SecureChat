import CryptoKit
import Foundation
import XCTest
@testable import PrivateChat

@MainActor
final class SyntheticOlmPeer {
    let identity: LocalIdentity
    let storage: InMemoryForwardSecretStore
    let crypto: ForwardSecretService
    let batch: OlmPrekeyBatch
    init(_ identity: LocalIdentity) throws {
        self.identity = identity
        let storage = InMemoryForwardSecretStore()
        self.storage = storage
        let crypto = ForwardSecretService(store: storage, local: identity)
        self.crypto = crypto
        try crypto.load()
        batch = try XCTUnwrap(crypto.publicationIfNeeded())
        try crypto.publicationAccepted(batch)
    }
    func trustedPeer(_ other: LocalIdentity) -> TrustedPeer {
        TrustedPeer(id: other.id, displayName: other.displayName,
            keyAgreementPublicKeyBase64: other.keyAgreementPublicKeyData.base64EncodedString(),
            signingPublicKeyBase64: other.signingPublicKeyData.base64EncodedString(),
            safetyNumber: SafetyNumberV3.make(localSigningPublicKeyData: identity.signingPublicKeyData,
                localKeyAgreementPublicKeyData: identity.keyAgreementPublicKeyData,
                remoteSigningPublicKeyData: other.signingPublicKeyData, remoteKeyAgreementPublicKeyData: other.keyAgreementPublicKeyData), trustState: .verified)
    }
    func claim(requester: String, claimID: UUID) -> OlmPrekeyClaim {
        OlmPrekeyClaim(requester: requester, recipientID: identity.id, claimID: claimID, identity: batch.identity,
            identitySignatureBase64: batch.identitySignatureBase64, prekey: batch.keys[0])
    }
    func establish(to other: SyntheticOlmPeer) throws {
        if try crypto.needsSession(peerID: other.identity.id) {
            let id = try crypto.claimID(peerID: other.identity.id)
            try crypto.acceptClaim(other.claim(requester: identity.id, claimID: id), peer: trustedPeer(other.identity))
        }
    }
    func packet(to other: SyntheticOlmPeer, payload: TransportMessagePayload, id: UUID = UUID()) throws -> OutboundTransportPacket {
        try establish(to: other)
        return try crypto.makePacket(payload: payload, recipientID: other.identity.id, packetID: id)
    }
}
