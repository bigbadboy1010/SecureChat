import CryptoKit
import Foundation
import XCTest
@testable import PrivateChat

@MainActor
final class AttachmentTransportTests: XCTestCase {
    func testDocumentAttachmentRoundTripsThroughMessageCoding() throws {
        let conversationID = UUID()
        let attachment = ChatAttachment(
            id: UUID(),
            kind: .document,
            fileName: "security-review.pdf",
            mimeType: "application/pdf",
            byteCount: 4_096
        )
        let message = ChatMessage(
            conversationID: conversationID,
            senderID: "alice",
            recipientID: "bob",
            body: "Review",
            status: .queued,
            isIncoming: false,
            attachment: attachment
        )

        let encoder = DateCoding.makeEncoder()
        let decoder = DateCoding.makeDecoder()
        let encoded = try encoder.encode(message)
        let decoded = try decoder.decode(ChatMessage.self, from: encoded)

        XCTAssertEqual(decoded, message)
        XCTAssertEqual(decoded.attachment?.kind, .document)
        XCTAssertEqual(decoded.attachment?.fileName, "security-review.pdf")
    }

    func testMaximumChunkFitsProductionRelayPacketLimit() throws {
        let chunk = Data(repeating: 0xA5, count: 64 * 1_024)
        let attachment = ChatAttachment(
            id: UUID(),
            kind: .document,
            fileName: "payload.bin",
            mimeType: "application/octet-stream",
            byteCount: chunk.count
        )
        let payload = TransportMessagePayload(
            version: 3,
            kind: .attachmentChunk,
            messageID: UUID(),
            conversationID: UUID(),
            senderID: String(repeating: "a", count: 64),
            recipientID: String(repeating: "b", count: 64),
            body: "Attachment",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            deliveredMessageID: nil,
            attachment: attachment,
            attachmentSHA256: RequestSigner.sha256Hex(chunk),
            chunkIndex: 0,
            totalChunks: 1,
            chunkDataBase64: chunk.base64EncodedString()
        )

        let encoder = DateCoding.makeEncoder()
        let crypto = CryptoService()
        let packetID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let expiresAt = createdAt.addingTimeInterval(86_400)
        let placeholderPacket = OutboundTransportPacket(
            id: packetID,
            senderID: payload.senderID,
            recipientID: payload.recipientID,
            sealedPayloadBase64: "pending",
            signatureBase64: "pending",
            createdAt: createdAt,
            expiresAt: expiresAt
        )
        let sealedPayload = try crypto.encrypt(
            encoder.encode(payload),
            key: SymmetricKey(size: .bits256),
            aad: placeholderPacket.payloadAAD
        )
        let unsignedPacket = OutboundTransportPacket(
            id: packetID,
            senderID: payload.senderID,
            recipientID: payload.recipientID,
            sealedPayloadBase64: sealedPayload.base64EncodedString(),
            signatureBase64: "pending",
            createdAt: createdAt,
            expiresAt: expiresAt
        )
        let signingKey = Curve25519.Signing.PrivateKey()
        let signature = try signingKey.signature(for: unsignedPacket.authenticatedData)
        let packet = OutboundTransportPacket(
            id: packetID,
            senderID: payload.senderID,
            recipientID: payload.recipientID,
            sealedPayloadBase64: unsignedPacket.sealedPayloadBase64,
            signatureBase64: signature.base64EncodedString(),
            createdAt: createdAt,
            expiresAt: expiresAt
        )

        let encodedPacket = try encoder.encode(packet)
        XCTAssertLessThan(encodedPacket.count, 131_072)
    }
}
