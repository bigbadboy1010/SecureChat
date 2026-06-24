import Foundation

final class LocalOnlyTransport: MessageTransport {
    var isAvailable: Bool { false }

    func send(_ packet: OutboundTransportPacket) async throws {
        _ = packet
        throw PrivateChatError.transportUnavailable
    }
}

extension LocalOnlyTransport: RelayMessageTransporting {
    func fetchInbox(recipientID: String, limit: Int) async throws -> [OutboundTransportPacket] {
        _ = recipientID; _ = limit
        throw PrivateChatError.transportUnavailable
    }
    func delete(packetID: UUID) async throws -> Bool {
        _ = packetID
        throw PrivateChatError.transportUnavailable
    }
    func checkHealth() async throws -> RelayHealthStatus {
        throw PrivateChatError.transportUnavailable
    }
    func fetchStats() async throws -> RelayStatsResponse {
        throw PrivateChatError.transportUnavailable
    }
    func purgeInbox(recipientID: String) async throws -> RelayPurgeResponse {
        _ = recipientID
        throw PrivateChatError.transportUnavailable
    }
    func enrollPublicKey(_ identity: LocalIdentity) async throws -> RelayEnrollmentResponse {
        _ = identity
        throw PrivateChatError.transportUnavailable
    }
}
