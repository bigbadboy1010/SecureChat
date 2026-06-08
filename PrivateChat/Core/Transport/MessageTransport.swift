import Foundation

protocol MessageTransport {
    var isAvailable: Bool { get }
    func send(_ packet: OutboundTransportPacket) async throws
}

protocol RelayMessageTransporting: MessageTransport {
    func fetchInbox(recipientID: String, limit: Int) async throws -> [OutboundTransportPacket]
    func delete(packetID: UUID) async throws -> Bool
    func checkHealth() async throws -> RelayHealthStatus
    func fetchStats() async throws -> RelayStatsResponse
    func purgeInbox(recipientID: String) async throws -> RelayPurgeResponse
}
