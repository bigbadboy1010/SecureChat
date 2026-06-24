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

extension CryptoServiceTests {
    /// Sprint 27 (2026-06-24): peer enrollment
    /// helper. The iOS PEM-export is verified
    /// against a fixed test vector generated
    /// with python `cryptography` lib:
    ///
    ///   seed = 0x42 * 32
    ///   Ed25519PrivateKey.from_private_bytes(seed)
    ///   .public_key().public_bytes(DER, SPKI)
    ///   = 302a300506032b6570032100...edb12 (44 bytes)
    ///   PEM:
    ///     MCowBQYDK2VwAyEAIVL40Zt5HSRFMkLhXy6rbLfP+ntqXtMAl5YOBpiB2xI=
    ///   peerID (sha256(raw)):
    ///     3097e2dee2cb4a34b53840cdb705aed71067c36f68db0e0f559c3f3fa043315f
    ///
    /// If this test fails the relay will reject
    /// every enrollment from a fresh iOS install
    /// (the failure mode of Sprint 26.2).
    func testPemEncodedSigningPublicKeyMatchesPythonReference() throws {
        let seed = Data(repeating: 0x42, count: 32)
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        let pem = crypto.pemEncodedSigningPublicKey(privateKey.publicKey)
        // The Swift implementation appends a final
        // newline after `-----END PUBLIC KEY-----`
        // for clean concatenation. Strip both sides
        // before comparison so the test is robust to
        // the trailing-newline convention.
        let trimmedPem = pem.trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedPEM = """
        -----BEGIN PUBLIC KEY-----
        MCowBQYDK2VwAyEAIVL40Zt5HSRFMkLhXy6rbLfP+ntqXtMAl5YOBpiB2xI=
        -----END PUBLIC KEY-----
        """
        XCTAssertEqual(trimmedPem, expectedPEM, "Swift PEM must match python cryptography output")

        // peerID must be sha256(raw 32-byte pubkey).
        let expectedPeerID = "3097e2dee2cb4a34b53840cdb705aed71067c36f68db0e0f559c3f3fa043315f"
        let actualPeerID = crypto.peerID(publicKeyData: privateKey.publicKey.rawRepresentation)
        XCTAssertEqual(actualPeerID, expectedPeerID, "Swift peerID must match python sha256")

        // Roundtrip: rawRepresentation must be 32 bytes.
        XCTAssertEqual(privateKey.publicKey.rawRepresentation.count, 32)
    }
}
