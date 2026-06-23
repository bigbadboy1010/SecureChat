import XCTest
import CryptoKit
@testable import PrivateChat

/// End-to-end tests for the v2 (Double Ratchet)
/// transport. Two channels are built with X3DH
/// material from a fresh pairing, then they
/// exchange a `RatchetChannelEnvelope` and confirm
/// that the plaintext survives the encrypt / decrypt
/// round-trip.
final class RatchetChannelTests: XCTestCase {

    private func makePair() throws -> (
        alice: RatchetChannel,
        bob: RatchetChannel,
        aliceStore: InMemoryDoubleRatchetStore,
        bobStore: InMemoryDoubleRatchetStore
    ) {
        // Two fresh long-term keypairs (the
        // hypothetical pairing that produced the
        // X3DH initial-bundle).
        let aliceKA = Curve25519.KeyAgreement.PrivateKey()
        let aliceSign = Curve25519.Signing.PrivateKey()
        let bobKA = Curve25519.KeyAgreement.PrivateKey()
        let bobSign = Curve25519.Signing.PrivateKey()
        let pairDate = Date(timeIntervalSince1970: 1_700_000_000)

        let aliceStore = InMemoryDoubleRatchetStore()
        let bobStore = InMemoryDoubleRatchetStore()

        let alice = try RatchetChannel.register(
            peerID: "bob",
            localKeyAgreementPrivateKey: aliceKA,
            remoteKeyAgreementPublicKey: bobKA.publicKey,
            remoteSigningPublicKey: bobSign.publicKey,
            localPayloadCreatedAt: pairDate,
            remotePayloadCreatedAt: pairDate,
            store: aliceStore
        )
        let bob = try RatchetChannel.register(
            peerID: "alice",
            localKeyAgreementPrivateKey: bobKA,
            remoteKeyAgreementPublicKey: aliceKA.publicKey,
            remoteSigningPublicKey: aliceSign.publicKey,
            localPayloadCreatedAt: pairDate,
            remotePayloadCreatedAt: pairDate,
            store: bobStore
        )
        return (alice, bob, aliceStore, bobStore)
    }

    func testRegisterPersistsX3DHBundle() throws {
        let (_, _, aliceStore, bobStore) = try makePair()
        let alicePersisted = try XCTUnwrap(aliceStore.load(peerID: "bob"))
        let bobPersisted = try XCTUnwrap(bobStore.load(peerID: "alice"))
        // Both sides agree on the sessionID and the
        // root key (X3DH symmetric).
        XCTAssertEqual(alicePersisted.sessionID, bobPersisted.sessionID)
        XCTAssertEqual(alicePersisted.rootKey, bobPersisted.rootKey)
        XCTAssertEqual(alicePersisted.rootKey.count, 32)
    }

    func testSingleMessageRoundTrip() throws {
        let (alice, bob, _, _) = try makePair()
        let plaintext = Data("hello bob, this is alice".utf8)
        let envelope = try alice.send(plaintext: plaintext, senderID: "alice")
        let decoded = try bob.receive(envelope)
        XCTAssertEqual(decoded, plaintext)
    }

    func testMultiMessageRoundTrip() throws {
        let (alice, bob, _, _) = try makePair()
        for i in 1...5 {
            let msg = Data("m\(i)".utf8)
            let env = try alice.send(plaintext: msg, senderID: "alice")
            let back = try bob.receive(env)
            XCTAssertEqual(back, msg, "message \(i) did not round-trip")
        }
    }

    func testEnvelopeIsJSONEncodable() throws {
        let (alice, _, _, _) = try makePair()
        let envelope = try alice.send(plaintext: Data("x".utf8), senderID: "alice")
        let encoder = DoubleRatchetStore.defaultEncoder
        let decoder = DoubleRatchetStore.defaultDecoder
        let data = try encoder.encode(envelope)
        XCTAssertGreaterThan(data.count, 32, "encoded envelope is too small")
        let decoded = try decoder.decode(RatchetChannelEnvelope.self, from: data)
        XCTAssertEqual(decoded, envelope)
    }

    func testPeerMismatchRejected() throws {
        let (alice, bob, _, _) = try makePair()
        let envelope = try alice.send(plaintext: Data("x".utf8), senderID: "alice")
        // Bob's channel is keyed to peerID "alice";
        // give it an envelope from a different sender.
        let wrong = RatchetChannelEnvelope(
            peerID: "mallory",
            ratchet: envelope.ratchet
        )
        XCTAssertThrowsError(try bob.receive(wrong)) { error in
            guard let channelError = error as? RatchetChannel.ChannelError,
                  case .peerMismatch(let expected, let actual) = channelError else {
                XCTFail("expected peerMismatch, got \(error)")
                return
            }
            XCTAssertEqual(expected, "alice")
            XCTAssertEqual(actual, "mallory")
        }
    }

    func testOpenReusesPersistedSession() throws {
        let (alice, bob, aliceStore, bobStore) = try makePair()
        // Open a second channel pair from the same
        // stores. The sessionID and root key should
        // match what the first pair saw.
        let aliceAgain = try XCTUnwrap(
            RatchetChannel.open(peerID: "bob", store: aliceStore)
        )
        let bobAgain = try XCTUnwrap(
            RatchetChannel.open(peerID: "alice", store: bobStore)
        )
        XCTAssertEqual(aliceAgain.sessionID, bobAgain.sessionID)
        XCTAssertEqual(aliceAgain.sessionID, alice.sessionID)
        // And a round-trip still works.
        let env = try aliceAgain.send(plaintext: Data("again".utf8), senderID: "alice")
        let back = try bobAgain.receive(env)
        XCTAssertEqual(back, Data("again".utf8))
    }

    func testOpenReturnsNilWhenNoSession() throws {
        let store = InMemoryDoubleRatchetStore()
        let channel = try RatchetChannel.open(peerID: "unknown", store: store)
        XCTAssertNil(channel)
    }
}
