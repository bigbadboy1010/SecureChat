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
    /// Sprint 27 (2026-06-24): register the
    /// local iOS app's Ed25519 signing public
    /// key with the relay so subsequent
    /// peer-signed requests are accepted.
    /// Idempotent: a re-enrollment for the
    /// same peerID overwrites the existing
    /// entry (used after key rotation).
    func enrollPublicKey(_ identity: LocalIdentity) async throws -> RelayEnrollmentResponse
}
