import CryptoKit
import XCTest
@testable import PrivateChat

final class PrivateRoomReviewRegressionTests: XCTestCase {
    func testTwoFreshInstallationsWithSameNameHaveDifferentPublicIdentities() throws {
        let first = IdentityManager(keychain: MockKeychainStore(), crypto: CryptoService())
        let second = IdentityManager(keychain: MockKeychainStore(), crypto: CryptoService())
        let alice = try first.loadOrCreateLocalIdentity(displayName: "PrivateChat iPhone")
        let bob = try second.loadOrCreateLocalIdentity(displayName: "PrivateChat iPhone")
        XCTAssertNotEqual(alice.id, bob.id)
        XCTAssertNotEqual(alice.signingPublicKeyData, bob.signingPublicKeyData)
        XCTAssertNotEqual(alice.keyAgreementPublicKeyData, bob.keyAgreementPublicKeyData)
        let imported = try first.importPairingPayload(second.exportPairingPayload(identity: bob))
        XCTAssertEqual(imported.id, bob.id)
        XCTAssertEqual(imported.trustState, .unverified)
    }

    func testDefaultNamesIncludePublicFingerprintAndStablePacketIDsAreDomainSeparated() throws {
        let first = try IdentityManager(keychain: MockKeychainStore(), crypto: CryptoService()).loadOrCreateLocalIdentity(displayName: "PrivateRoom iPhone")
        let second = try IdentityManager(keychain: MockKeychainStore(), crypto: CryptoService()).loadOrCreateLocalIdentity(displayName: "PrivateRoom iPhone")
        XCTAssertNotEqual(first.displayName, second.displayName)
        XCTAssertTrue(first.displayName.contains(String(first.id.prefix(6))))
        let id = UUID()
        let body = StableRelayPacketIdentifier.make(messageID: id, recipientID: first.id, kind: .message)
        XCTAssertEqual(body, StableRelayPacketIdentifier.make(messageID: id, recipientID: first.id, kind: .message))
        XCTAssertNotEqual(body, StableRelayPacketIdentifier.make(messageID: id, recipientID: first.id, kind: .deliveryReceipt))
        XCTAssertNotEqual(body, StableRelayPacketIdentifier.make(messageID: id, recipientID: second.id, kind: .message))
    }

    func testAdmissionErrorsExplainTheAffectedDeviceWithoutSuggestingProxyRepairs() {
        let recipient = PrivateChatError.relayHTTPError(statusCode: 403, message: "recipient_not_admitted").localizedDescription
        XCTAssertTrue(recipient.contains("Empfängergerät"))
        XCTAssertFalse(recipient.contains("Caddy"))
        XCTAssertFalse(recipient.contains("Docker"))
        let own = PrivateChatError.relayHTTPError(statusCode: 403, message: "beta_admission_required").localizedDescription
        XCTAssertTrue(own.contains("Dieses Gerät"))
        let revoked = PrivateChatError.relayHTTPError(statusCode: 403, message: "device_access_revoked").localizedDescription
        XCTAssertTrue(revoked.contains("gesperrt"))
    }

    // Historical primitive regression: demonstrates why the protocol-2
    // encryption path was removed from ConversationService.
    func testHistoricalStaticPrimitiveDoesNotProvideForwardSecrecy() throws {
        let crypto = CryptoService()
        let alice = Curve25519.KeyAgreement.PrivateKey()
        let bob = Curve25519.KeyAgreement.PrivateKey()
        let context = Data("PrivateChat/pairwise-message/v3/synthetic-review-peers".utf8)
        let key = try crypto.derivePairwiseKey(privateKey: alice, peerPublicKey: bob.publicKey, context: context)
        let message = Data("synthetic historical message".utf8)
        let aad = Data("synthetic authenticated packet header".utf8)
        let recordedCiphertext = try crypto.encrypt(message, key: key, aad: aad)
        let laterExposedBobKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: bob.rawRepresentation)
        let recovered = try crypto.derivePairwiseKey(privateKey: laterExposedBobKey, peerPublicKey: alice.publicKey, context: context)
        XCTAssertEqual(try crypto.decrypt(recordedCiphertext, key: recovered, aad: aad), message)
    }
}
