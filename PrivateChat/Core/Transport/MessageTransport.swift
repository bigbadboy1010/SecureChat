import Foundation

protocol MessageTransport {
    var isAvailable: Bool { get }
    func send(_ packet: OutboundTransportPacket) async throws
}

protocol RelayMessageTransporting: MessageTransport {
    func olmPrekeyStatus() async throws -> OlmPrekeyStatus
    func publishOlmPrekeys(_ batch: OlmPrekeyBatch) async throws
    func claimOlmPrekey(recipientID: String, claimID: UUID) async throws -> OlmPrekeyClaim
    func configureNeutralPush(enabled: Bool, token: String?, environment: String) async throws
    func fetchInboxPage(recipientID: String, limit: Int, after: String?) async throws -> RelayFetchResponse
    func replaceRecipientConsent(_ consent: RelayRecipientConsent) async throws
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

extension RelayMessageTransporting {
    func olmPrekeyStatus() async throws -> OlmPrekeyStatus { throw ForwardSecretError.unavailable }
    func publishOlmPrekeys(_ batch: OlmPrekeyBatch) async throws { throw ForwardSecretError.unavailable }
    func claimOlmPrekey(recipientID: String, claimID: UUID) async throws -> OlmPrekeyClaim { throw ForwardSecretError.unavailable }
    func configureNeutralPush(enabled: Bool, token: String?, environment: String) async throws {
        throw PrivateChatError.relayInvalidResponse
    }
    func fetchInboxPage(recipientID: String, limit: Int, after: String?) async throws -> RelayFetchResponse {
        RelayFetchResponse(packets: try await fetchInbox(recipientID: recipientID, limit: limit))
    }
    func replaceRecipientConsent(_ consent: RelayRecipientConsent) async throws {
        throw PrivateChatError.relayInvalidResponse
    }
}
