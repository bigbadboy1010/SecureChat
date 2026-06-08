import Foundation

struct OutboundTransportPacket: Codable, Equatable, Identifiable {
    let protocolVersion: Int
    let id: UUID
    let senderID: String
    let recipientID: String
    let sealedPayloadBase64: String
    let signatureBase64: String
    let createdAt: Date
    let expiresAt: Date

    init(
        protocolVersion: Int = 2,
        id: UUID = UUID(),
        senderID: String,
        recipientID: String,
        sealedPayloadBase64: String,
        signatureBase64: String,
        createdAt: Date = Date(),
        expiresAt: Date = Date().addingTimeInterval(86_400)
    ) {
        self.protocolVersion = protocolVersion
        self.id = id
        self.senderID = senderID
        self.recipientID = recipientID
        self.sealedPayloadBase64 = sealedPayloadBase64
        self.signatureBase64 = signatureBase64
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    var authenticatedData: Data {
        let fields = [
            "PrivateChat/transport-envelope/v2",
            String(protocolVersion),
            id.uuidString.lowercased(),
            senderID,
            recipientID,
            DateCoding.string(from: createdAt),
            DateCoding.string(from: expiresAt),
            sealedPayloadBase64
        ]
        return Data(fields.joined(separator: "|").utf8)
    }

    var payloadAAD: Data {
        let fields = [
            "PrivateChat/transport-payload/v2",
            String(protocolVersion),
            id.uuidString.lowercased(),
            senderID,
            recipientID,
            DateCoding.string(from: createdAt),
            DateCoding.string(from: expiresAt)
        ]
        return Data(fields.joined(separator: "|").utf8)
    }
}

struct RelayHealthStatus: Decodable, Equatable {
    let status: String
    let store: String?
    let authRequired: Bool?
    let adminAuthRequired: Bool?
    let productionMode: Bool?
    let httpsRequired: Bool?
    let clientPurgeEnabled: Bool?
    let maxPacketBytes: Int?
    let maxTTLSeconds: Int?
    let maxClockSkewSeconds: Int?
    let maxTotalPackets: Int?
    let maxPacketsPerRecipient: Int?

    var isHealthy: Bool {
        status == "ok"
    }

    var hardeningSummary: String {
        var parts: [String] = []
        if let store { parts.append("Store=\(store)") }
        if let authRequired { parts.append("Auth=\(authRequired ? "an" : "aus")") }
        if let adminAuthRequired { parts.append("Admin=\(adminAuthRequired ? "an" : "aus")") }
        if let httpsRequired { parts.append("HTTPS=\(httpsRequired ? "erzwungen" : "nicht erzwungen")") }
        if let clientPurgeEnabled { parts.append("Client-Purge=\(clientPurgeEnabled ? "an" : "aus")") }
        if let maxPacketsPerRecipient { parts.append("Queue/Peer=\(maxPacketsPerRecipient)") }
        return parts.isEmpty ? status : parts.joined(separator: ", ")
    }
}

struct RelaySendResponse: Decodable, Equatable {
    let accepted: Bool
    let packetID: UUID
}

struct RelayFetchResponse: Decodable, Equatable {
    let packets: [OutboundTransportPacket]
}

struct RelayDeleteResponse: Decodable, Equatable {
    let deleted: Bool
    let packetID: UUID
}


struct RelayStatsResponse: Decodable, Equatable {
    let storedPackets: Int
    let activeRecipients: Int
    let acknowledgedPacketTombstones: Int
}

struct RelayPurgeResponse: Decodable, Equatable {
    let deletedCount: Int
    let recipientID: String
}

struct RelayPurgeRequest: Encodable, Equatable {
    let recipientID: String
}
