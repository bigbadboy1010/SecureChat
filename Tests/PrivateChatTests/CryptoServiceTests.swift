import CryptoKit
import XCTest
@testable import PrivateChat

final class CryptoServiceTests: XCTestCase {
    private let crypto = CryptoService()

    func testEncryptDecryptRoundTripWithAAD() throws {
        let key = try crypto.makeSymmetricKey()
        let plaintext = Data("PrivateChat Test Message".utf8)
        let aad = Data("PrivateChat/test/aad/v1".utf8)

        let ciphertext = try crypto.encrypt(plaintext, key: key, aad: aad)
        let recovered = try crypto.decrypt(ciphertext, key: key, aad: aad)

        XCTAssertEqual(recovered, plaintext)
        XCTAssertNotEqual(ciphertext, plaintext)
    }

    func testAADBindingPreventsTampering() throws {
        let key = try crypto.makeSymmetricKey()
        let plaintext = Data("secret".utf8)
        let ciphertext = try crypto.encrypt(plaintext, key: key, aad: Data("context-A".utf8))

        XCTAssertThrowsError(try crypto.decrypt(ciphertext, key: key, aad: Data("context-B".utf8))) { error in
            XCTAssertEqual(error as? PrivateChatError, .decryptionFailed)
        }
    }

    func testCiphertextTamperingFailsDecryption() throws {
        let key = try crypto.makeSymmetricKey()
        let aad = Data("PrivateChat/tamper-test/v1".utf8)
        var ciphertext = try crypto.encrypt(Data("secret".utf8), key: key, aad: aad)
        XCTAssertFalse(ciphertext.isEmpty)

        ciphertext[ciphertext.count - 1] ^= 0x01

        XCTAssertThrowsError(try crypto.decrypt(ciphertext, key: key, aad: aad)) { error in
            XCTAssertEqual(error as? PrivateChatError, .decryptionFailed)
        }
    }

    func testSignVerifyRoundTripAndTamperDetection() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let data = Data("hello".utf8)
        let signature = try crypto.sign(data, privateKey: privateKey)

        XCTAssertTrue(crypto.verify(signature: signature, data: data, publicKey: privateKey.publicKey))
        XCTAssertFalse(crypto.verify(signature: signature, data: Data("hellp".utf8), publicKey: privateKey.publicKey))
    }

    func testPairwiseKeyIsDeterministicAcrossBothPeers() throws {
        let alice = Curve25519.KeyAgreement.PrivateKey()
        let bob = Curve25519.KeyAgreement.PrivateKey()
        let context = Data("PrivateChat/pairwise-message/v3/alice:bob".utf8)

        let aliceKey = try crypto.derivePairwiseKey(privateKey: alice, peerPublicKey: bob.publicKey, context: context)
        let bobKey = try crypto.derivePairwiseKey(privateKey: bob, peerPublicKey: alice.publicKey, context: context)

        XCTAssertEqual(aliceKey.testData, bobKey.testData)
    }

    func testPeerIDAndSafetyNumberAreStable() {
        let publicKeyData = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
        let peerID = crypto.peerID(publicKeyData: publicKeyData)

        XCTAssertEqual(peerID, crypto.peerID(publicKeyData: publicKeyData))
        XCTAssertEqual(peerID.count, 64)
        XCTAssertEqual(crypto.safetyNumber(peerID: peerID).split(separator: " ").count, 16)
    }
}

private extension SymmetricKey {
    var testData: Data {
        withUnsafeBytes { buffer in
            Data(buffer)
        }
    }
}
