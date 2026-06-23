import Foundation
import CryptoKit

/// Additive v2-envelope adapter for the existing
/// v1 `OutboundTransportPacket` transport.
///
/// The `ConversationService` calls
/// `RatchetEnvelopeRouter.makeRatchetPacket(...)` first
/// when it has a body to send; if the router returns
/// `nil` (no v2 channel for that peer), the service
/// falls back to the v1 `makeTransportPacket` path.
/// Likewise, the router exposes
/// `tryDecodeV2(...)` which the inbound path can call
/// before the v1 AES-GCM decrypt step; if the router
/// returns `nil`, the inbound path falls back to v1.
///
/// The router **does not modify** the v1
/// `makeTransportPacket` or `processInboundPacket`.
/// It is a pure side-channel: the v1 path stays
/// 100% intact for any peer that has not been
/// registered with `RatchetChannel.register(...)`.
///
/// The router also exposes the
/// `RatchetSentinelObservation` returned by the
/// last send/receive call, so the `SecurityAISentinel`
/// can surface a "session still on v1" finding when
/// a peer that has a v1 fallback path was used.
struct RatchetEnvelopeRouter {
    let store: DoubleRatchetStoring
    let localIdentityID: () -> String

    /// Build a v2-envelope `OutboundTransportPacket`
    /// for `peerID` if a `RatchetChannel` is on file;
    /// otherwise return `nil` so the caller can
    /// fall back to the v1 `makeTransportPacket`.
    ///
    /// - Parameters:
    ///   - peerID: the recipient's identity (used as
    ///     the keychain key for the channel).
    ///   - plaintext: the v1 payload bytes (the
    ///     `TransportMessagePayload` JSON).
    ///   - existingPacket: a pre-built v1
    ///     `OutboundTransportPacket`. The router
    ///     re-uses its `id`, `createdAt`, and
    ///     `expiresAt` so the wire stays consistent.
    /// - Returns: a v2-style
    ///   `OutboundTransportPacket` whose
    ///   `sealedPayloadBase64` is the
    ///   `RatchetChannelEnvelope` JSON, or `nil` if
    ///   no v2 channel is registered for `peerID`.
    func makeRatchetPacket(
        peerID: String,
        plaintext: Data,
        existingPacket: OutboundTransportPacket
    ) throws -> (OutboundTransportPacket, RatchetSentinelObservation)? {
        guard let channel = try RatchetChannel.open(peerID: peerID, store: store) else {
            return nil
        }
        let envelope = try channel.send(plaintext: plaintext, senderID: localIdentityID())
        let envelopeData = try DoubleRatchetStore.defaultEncoder.encode(envelope)
        let packet = OutboundTransportPacket(
            protocolVersion: 3,
            id: existingPacket.id,
            senderID: existingPacket.senderID,
            recipientID: existingPacket.recipientID,
            sealedPayloadBase64: envelopeData.base64EncodedString(),
            signatureBase64: existingPacket.signatureBase64,
            createdAt: existingPacket.createdAt,
            expiresAt: existingPacket.expiresAt
        )
        return (packet, RatchetSentinelObservation(
            peerID: peerID,
            isV2: true,
            sessionID: channel.sessionID
        ))
    }

    /// Try to decode a v2 envelope on the inbound
    /// path. Returns the decoded plaintext if the
    /// `OutboundTransportPacket` carries a v2
    /// envelope and a `RatchetChannel` is on file for
    /// the sender; otherwise returns `nil` so the
    /// caller can fall back to the v1 decrypt path.
    func tryDecodeV2(
        packet: OutboundTransportPacket
    ) throws -> (Data, RatchetSentinelObservation)? {
        guard packet.protocolVersion == 3 else {
            return nil
        }
        guard let sealedData = Data(base64Encoded: packet.sealedPayloadBase64) else {
            return nil
        }
        let envelope = try DoubleRatchetStore.defaultDecoder.decode(
            RatchetChannelEnvelope.self,
            from: sealedData
        )
        guard let channel = try RatchetChannel.open(peerID: envelope.peerID, store: store) else {
            return nil
        }
        let plaintext = try channel.receive(envelope)
        return (plaintext, RatchetSentinelObservation(
            peerID: envelope.peerID,
            isV2: true,
            sessionID: channel.sessionID
        ))
    }

    /// Build a sentinel observation for the case
    /// where a v1 fallback was used. The
    /// `SecurityAISentinel` uses this to surface a
    /// "session still on v1" finding.
    func v1FallbackObservation(peerID: String) -> RatchetSentinelObservation {
        RatchetSentinelObservation(peerID: peerID, isV2: false, sessionID: nil)
    }
}

/// One row of v2 / v1 routing telemetry, exposed
/// to the `SecurityAISentinel` so it can show a
/// "session still on v1" finding for any peer
/// whose only path is the legacy v1 envelope.
struct RatchetSentinelObservation: Equatable {
    let peerID: String
    let isV2: Bool
    let sessionID: String?
}
