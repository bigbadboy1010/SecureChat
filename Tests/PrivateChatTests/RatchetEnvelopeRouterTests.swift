import XCTest
import CryptoKit
@testable import PrivateChat

/// Tests for the v2 envelope router. The router
/// sits in front of the v1 `OutboundTransportPacket`
/// transport; when a v2 `RatchetChannel` is on
/// file for the peer, the router produces a v2
/// packet; otherwise it returns `nil` and the
/// caller falls back to the v1 path.
final class RatchetEnvelopeRouterTests: XCTestCase {

    private func makeRouter() throws -> (
        RatchetEnvelopeRouter,
        InMemoryDoubleRatchetStore,
        String // peerID
    ) {
        let aliceKA = Curve25519.KeyAgreement.PrivateKey()
        let aliceSign = Curve25519.Signing.PrivateKey()
        let bobKA = Curve25519.KeyAgreement.PrivateKey()
        let bobSign = Curve25519.Signing.PrivateKey()
        let pairDate = Date(timeIntervalSince1970: 1_700_000_000)
        let store = InMemoryDoubleRatchetStore()
        _ = try RatchetChannel.register(
            peerID: "bob",
            localKeyAgreementPrivateKey: aliceKA,
            remoteKeyAgreementPublicKey: bobKA.publicKey,
            remoteSigningPublicKey: bobSign.publicKey,
            localPayloadCreatedAt: pairDate,
            remotePayloadCreatedAt: pairDate,
            store: store
        )
        // Mark the unused bob-side variables
        // referenced so the compiler does not
        // warn.
        _ = bobSign
        _ = aliceSign.publicKey
        let router = RatchetEnvelopeRouter(
            store: store,
            localIdentityID: { "alice" }
        )
        return (router, store, "bob")
    }

    private func samplePacket(peerID: String) -> OutboundTransportPacket {
        OutboundTransportPacket(
            protocolVersion: 2,
            senderID: "alice",
            recipientID: peerID,
            sealedPayloadBase64: "ignored-in-routing-tests",
            signatureBase64: "sig"
        )
    }

    func testMakeRatchetPacketReturnsV2WhenChannelExists() throws {
        let (router, _, _) = try makeRouter()
        let plaintext = Data("hello".utf8)
        let existing = samplePacket(peerID: "bob")
        let result = try router.makeRatchetPacket(
            peerID: "bob",
            plaintext: plaintext,
            existingPacket: existing
        )
        let (packet, obs) = try XCTUnwrap(result)
        XCTAssertEqual(packet.protocolVersion, 3, "v2 packet should bump protocolVersion to 3")
        XCTAssertEqual(packet.senderID, "alice")
        XCTAssertEqual(packet.recipientID, "bob")
        XCTAssertEqual(packet.id, existing.id, "v2 packet must reuse the v1 packet id")
        XCTAssertNotEqual(packet.sealedPayloadBase64, "ignored-in-routing-tests")
        XCTAssertTrue(obs.isV2)
        XCTAssertNotNil(obs.sessionID)
    }

    func testMakeRatchetPacketReturnsNilForUnknownPeer() throws {
        let (router, _, _) = try makeRouter()
        let existing = samplePacket(peerID: "mallory")
        let result = try router.makeRatchetPacket(
            peerID: "mallory",
            plaintext: Data("x".utf8),
            existingPacket: existing
        )
        XCTAssertNil(result, "router must return nil when no v2 channel exists")
    }

    func testTryDecodeV2AcceptsV2Packets() throws {
        // One shared keypair set: Alice and Bob
        // know each other's long-term keys from
        // the pairing. Both sides call
        // `RatchetChannel.register` with the
        // matching inputs (Alice is the local
        // side on Alice's store, Bob is the local
        // side on Bob's store, but they both
        // agree on the long-term keys and the
        // PairingPayload timestamps).
        let aliceKA = Curve25519.KeyAgreement.PrivateKey()
        let aliceSign = Curve25519.Signing.PrivateKey()
        let bobKA = Curve25519.KeyAgreement.PrivateKey()
        let bobSign = Curve25519.Signing.PrivateKey()
        let pairDate = Date(timeIntervalSince1970: 1_700_000_000)
        let aliceStore = InMemoryDoubleRatchetStore()
        let bobStore = InMemoryDoubleRatchetStore()
        _ = try RatchetChannel.register(
            peerID: "bob",
            localKeyAgreementPrivateKey: aliceKA,
            remoteKeyAgreementPublicKey: bobKA.publicKey,
            remoteSigningPublicKey: bobSign.publicKey,
            localPayloadCreatedAt: pairDate,
            remotePayloadCreatedAt: pairDate,
            store: aliceStore
        )
        _ = try RatchetChannel.register(
            peerID: "alice",
            localKeyAgreementPrivateKey: bobKA,
            remoteKeyAgreementPublicKey: aliceKA.publicKey,
            remoteSigningPublicKey: aliceSign.publicKey,
            localPayloadCreatedAt: pairDate,
            remotePayloadCreatedAt: pairDate,
            store: bobStore
        )
        let aliceRouter = RatchetEnvelopeRouter(
            store: aliceStore,
            localIdentityID: { "alice" }
        )
        let bobRouter = RatchetEnvelopeRouter(
            store: bobStore,
            localIdentityID: { "bob" }
        )
        let plaintext = Data("v2-hello".utf8)
        let existing = samplePacket(peerID: "bob")
        let (v2Packet, _) = try XCTUnwrap(
            try aliceRouter.makeRatchetPacket(
                peerID: "bob",
                plaintext: plaintext,
                existingPacket: existing
            )
        )
        let (decoded, obs) = try XCTUnwrap(try bobRouter.tryDecodeV2(packet: v2Packet))
        XCTAssertEqual(decoded, plaintext)
        XCTAssertTrue(obs.isV2)
        XCTAssertNotNil(obs.sessionID)
    }

    func testTryDecodeV2ReturnsNilForV1Packets() throws {
        let (router, _, _) = try makeRouter()
        let v1Packet = samplePacket(peerID: "bob")
        let result = try router.tryDecodeV2(packet: v1Packet)
        XCTAssertNil(result, "v1 packet (protocolVersion=2) must be skipped by the v2 router")
    }

    func testV1FallbackObservationMarksPeer() {
        let router = RatchetEnvelopeRouter(
            store: InMemoryDoubleRatchetStore(),
            localIdentityID: { "alice" }
        )
        let obs = router.v1FallbackObservation(peerID: "bob")
        XCTAssertEqual(obs.peerID, "bob")
        XCTAssertFalse(obs.isV2)
        XCTAssertNil(obs.sessionID)
    }
}
