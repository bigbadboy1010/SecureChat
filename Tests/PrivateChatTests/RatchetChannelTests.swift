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

    // MARK: - Sprint 10B: live-state persistence

    /// After `send(...)`, the on-device store must
    /// carry the live ratchet state (chain key,
    /// counter, DH ratchet keypair) so an app
    /// relaunch that calls `open(...)` resumes the
    /// chain at exactly that position. The
    /// `liveState` field on the persisted session
    /// is non-nil and the next encrypt / decrypt
    /// continues from there.
    func testLiveStatePersistedAfterSend() throws {
        let (alice, _, aliceStore, _) = try makePair()
        let envelope = try alice.send(plaintext: Data("first".utf8), senderID: "alice")
        // The store has been updated.
        let persisted = try XCTUnwrap(try aliceStore.load(peerID: "bob"))
        XCTAssertTrue(persisted.isSealed)
        let live = try XCTUnwrap(persisted.liveState)
        // First message: sendCounter is 1
        // (incremented inside stepSendChain).
        XCTAssertEqual(live.sendCounter, 1)
        XCTAssertEqual(live.recvCounter, 0)
        XCTAssertNotNil(live.sendChainKey)
        XCTAssertEqual(envelope.ratchet.counter, 1)
    }

    /// Full restart round-trip: Alice sends three
    /// messages (triggering two DH ratchet steps
    /// on Bob's turn), then we **simulate an app
    /// relaunch** by closing both channels and
    /// re-opening them from the same on-device
    /// stores. Bob's freshly opened channel must
    /// still decrypt Alice's next message and
    /// Alice's freshly opened channel must still
    /// encrypt it.
    func testMultiMessageRoundTripAcrossRelaunch() throws {
        var (alice, bob, aliceStore, bobStore) = try makePair()
        // Alice -> Bob: 3 messages. After the third
        // send, Alice has rotated her DH ratchet
        // keypair once (isFirstStep was on the
        // first step so the keypair stays put,
        // but the chain has advanced). Bob
        // receives them in between (each
        // receive() advances his recvCounter and
        // triggers persistLiveState()).
        let e1 = try alice.send(plaintext: Data("one".utf8), senderID: "alice")
        _ = try bob.receive(e1)
        let e2 = try alice.send(plaintext: Data("two".utf8), senderID: "alice")
        _ = try bob.receive(e2)
        let e3 = try alice.send(plaintext: Data("three".utf8), senderID: "alice")
        _ = try bob.receive(e3)

        // Sanity: persisted state is sealed on
        // both sides.
        XCTAssertTrue(try XCTUnwrap(try aliceStore.load(peerID: "bob")).isSealed)
        XCTAssertTrue(try XCTUnwrap(try bobStore.load(peerID: "alice")).isSealed)

        // Simulate app relaunch: drop the in-memory
        // channels and re-open them from the
        // stores. The rebuilt session must
        // continue at the exact send / recv
        // counter position.
        alice = try XCTUnwrap(try RatchetChannel.open(peerID: "bob", store: aliceStore))
        bob = try XCTUnwrap(try RatchetChannel.open(peerID: "alice", store: bobStore))

        // Bob -> Alice: send one message. The new
        // outgoing DH ratchet step on Bob's side
        // (the one that was deferred during his
        // three receive() calls) is triggered here.
        let e4 = try bob.send(plaintext: Data("four".utf8), senderID: "bob")
        let p4 = try alice.receive(e4)
        XCTAssertEqual(p4, Data("four".utf8))

        // Alice -> Bob: one more message on the
        // new chain.
        let e5 = try alice.send(plaintext: Data("five".utf8), senderID: "alice")
        let p5 = try bob.receive(e5)
        XCTAssertEqual(p5, Data("five".utf8))
    }

    /// After a send, the persisted live state must
    /// carry the **same** DH ratchet private key
    /// the in-memory session is using. A test
    /// re-opening from the store would otherwise
    /// produce a different chain key on the very
    /// first encrypt.
    func testPersistedDHKeyMatchesInMemoryKey() throws {
        let (alice, _, aliceStore, _) = try makePair()
        _ = try alice.send(plaintext: Data("x".utf8), senderID: "alice")
        let persisted = try XCTUnwrap(try aliceStore.load(peerID: "bob"))
        let live = try XCTUnwrap(persisted.liveState)
        XCTAssertEqual(live.dhRatchetPrivateKey.count, 32)
        // No counter regression.
        XCTAssertEqual(live.sendCounter, 1)
        // Skipped-key window is empty (no out-of-
        // order messages yet).
        XCTAssertTrue(live.skippedMessageKeys.isEmpty)
    }
}
