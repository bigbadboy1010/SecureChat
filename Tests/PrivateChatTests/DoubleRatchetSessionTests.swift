import XCTest
import CryptoKit
@testable import PrivateChat

/// Tests for the Double Ratchet session (ADR-006).
///
/// Coverage:
///   * First message round-trip (sender + receiver agree)
///   * Mid-chain message
///   * DH ratchet step (turn change)
///   * Out-of-order delivery within the skipped-key window
///   * Past-key eviction (forward secrecy)
final class DoubleRatchetSessionTests: XCTestCase {

    // MARK: - Helpers

    private func makeSessionPair() throws -> (alice: DoubleRatchetSession, bob: DoubleRatchetSession) {
        // X3DH initial-bundle (Sprint 9, two-DH variant):
        // both sides have two long-term Curve25519 keys (one
        // key-agreement key, one signing key). The shared
        // root key comes from two DH agreements:
        //   DH(alice_keyAgreementPriv, bob_signingPub)
        //   DH(alice_keyAgreementPriv, bob_keyAgreementPub)
        // and the symmetric equivalent on Bob's side.
        let aliceKeyAgreement = Curve25519.KeyAgreement.PrivateKey()
        let aliceSigning = Curve25519.Signing.PrivateKey()
        let bobKeyAgreement = Curve25519.KeyAgreement.PrivateKey()
        let bobSigning = Curve25519.Signing.PrivateKey()
        let pairDate = Date(timeIntervalSince1970: 1_700_000_000)
        let salt = X3DHAgreement.sessionSalt(
            localPayloadCreatedAt: pairDate,
            remotePayloadCreatedAt: pairDate
        )
        let aliceRoot = try X3DHAgreement.deriveRootKey(
            localKeyAgreementPrivateKey: aliceKeyAgreement,
            remoteKeyAgreementPublicKey: bobKeyAgreement.publicKey,
            remoteSigningPublicKey: bobSigning.publicKey,
            sessionSalt: salt
        )
        let bobRoot = try X3DHAgreement.deriveRootKey(
            localKeyAgreementPrivateKey: bobKeyAgreement,
            remoteKeyAgreementPublicKey: aliceKeyAgreement.publicKey,
            remoteSigningPublicKey: aliceSigning.publicKey,
            sessionSalt: salt
        )
        // Sanity: both sides MUST derive the same root key.
        XCTAssertEqual(aliceRoot, bobRoot, "X3DH root-key derivation must be symmetric")
        let sessionID = X3DHAgreement.sessionID(fromRootKey: aliceRoot)

        // The initial ratchet keypair is the long-term
        // **key-agreement** key itself (Sprint 9 fix to
        // ADR-007: the initial ratchet step is symmetric when
        // both sides use their long-term key as the initial
        // ratchet key). Both sides pre-exchange it via the
        // PairingPayload.
        let alice = DoubleRatchetSession(
            sessionID: sessionID,
            rootKey: aliceRoot,
            initialRatchetPrivateKey: aliceKeyAgreement,
            initialRemoteRatchetPublicKey: bobKeyAgreement.publicKey
        )
        let bob = DoubleRatchetSession(
            sessionID: sessionID,
            rootKey: bobRoot,
            initialRatchetPrivateKey: bobKeyAgreement,
            initialRemoteRatchetPublicKey: aliceKeyAgreement.publicKey
        )
        return (alice, bob)
    }

    // MARK: - Tests

    func testX3DHRootKeyDerivationIsSymmetric() throws {
        // Sanity check the X3DH two-DH module in isolation.
        let aliceKeyAgreement = Curve25519.KeyAgreement.PrivateKey()
        let aliceSigning = Curve25519.Signing.PrivateKey()
        let bobKeyAgreement = Curve25519.KeyAgreement.PrivateKey()
        let bobSigning = Curve25519.Signing.PrivateKey()
        let salt = X3DHAgreement.sessionSalt(
            localPayloadCreatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            remotePayloadCreatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let a = try X3DHAgreement.deriveRootKey(
            localKeyAgreementPrivateKey: aliceKeyAgreement,
            remoteKeyAgreementPublicKey: bobKeyAgreement.publicKey,
            remoteSigningPublicKey: bobSigning.publicKey,
            sessionSalt: salt
        )
        let b = try X3DHAgreement.deriveRootKey(
            localKeyAgreementPrivateKey: bobKeyAgreement,
            remoteKeyAgreementPublicKey: aliceKeyAgreement.publicKey,
            remoteSigningPublicKey: aliceSigning.publicKey,
            sessionSalt: salt
        )
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 32)
    }

    func testFirstMessageRoundTrip() throws {
        let (alice, bob) = try makeSessionPair()
        let plaintext = Data("hello bob".utf8)

        let wire = try alice.encrypt(plaintext)
        let decoded = try bob.decrypt(wire)

        XCTAssertEqual(decoded, plaintext)
    }

    func testMidChainMessage() throws {
        let (alice, bob) = try makeSessionPair()
        let m1 = try alice.encrypt(Data("m1".utf8))
        _ = try bob.decrypt(m1)
        let m2 = try alice.encrypt(Data("m2".utf8))
        let d2 = try bob.decrypt(m2)
        XCTAssertEqual(d2, Data("m2".utf8))
        let m3 = try alice.encrypt(Data("m3".utf8))
        let d3 = try bob.decrypt(m3)
        XCTAssertEqual(d3, Data("m3".utf8))
    }

    func testDHRatchetStepOnTurnChange() throws {
        let (alice, bob) = try makeSessionPair()
        let m1 = try alice.encrypt(Data("alice->bob 1".utf8))
        _ = try bob.decrypt(m1)
        let m2 = try bob.encrypt(Data("bob->alice 1".utf8))
        let d2 = try alice.decrypt(m2)
        XCTAssertEqual(d2, Data("bob->alice 1".utf8))
    }

    func testOutOfOrderDelivery() throws {
        let (alice, bob) = try makeSessionPair()
        let m1 = try alice.encrypt(Data("m1".utf8))
        let m2 = try alice.encrypt(Data("m2".utf8))
        let m3 = try alice.encrypt(Data("m3".utf8))
        let d2 = try bob.decrypt(m2)
        let d1 = try bob.decrypt(m1)
        let d3 = try bob.decrypt(m3)
        XCTAssertEqual(d1, Data("m1".utf8))
        XCTAssertEqual(d2, Data("m2".utf8))
        XCTAssertEqual(d3, Data("m3".utf8))
    }

    func testForwardSecrecyByPastKeyEviction() throws {
        let (alice, bob) = try makeSessionPair()
        let m1 = try alice.encrypt(Data("secret-1".utf8))
        _ = try bob.decrypt(m1)
        for i in 2...10 {
            let m = try alice.encrypt(Data("m\(i)".utf8))
            _ = try bob.decrypt(m)
        }
        XCTAssertThrowsError(try bob.decrypt(m1))
    }

    func testVersionRejection() throws {
        let (alice, _) = try makeSessionPair()
        let bogus = DoubleRatchetSession.WireMessage(
            v: 99,
            sessionID: "test-session-1",
            ratchetPK: Data().base64EncodedString(),
            counter: 0,
            prevChainLen: 0,
            ciphertext: Data().base64EncodedString()
        )
        // We need a peer that has Alice's PK to test this.
        // Build a third session whose only purpose is to
        // attempt to decrypt.
        let rootKey = SymmetricKey(size: .bits256)
        let rootData = rootKey.withUnsafeBytes { Data($0) }
        let priv = Curve25519.KeyAgreement.PrivateKey()
        let observer = DoubleRatchetSession(
            sessionID: "test-session-1",
            rootKey: rootData,
            initialRatchetPrivateKey: priv
        )
        XCTAssertThrowsError(try observer.decrypt(bogus)) { error in
            guard case DoubleRatchetSession.SessionError.unknownVersion(let v) = error else {
                return XCTFail("expected unknownVersion, got \(error)")
            }
            XCTAssertEqual(v, 99)
        }
    }
}
