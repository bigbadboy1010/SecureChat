import Foundation

protocol TransportCoordinating {
    func send(_ packet: OutboundTransportPacket, mode: TransportMode, relayConfiguration: RelayConfiguration) async throws
    func fetchRelayInbox(recipientID: String, relayConfiguration: RelayConfiguration) async throws -> [OutboundTransportPacket]
    func deleteRelayPacket(packetID: UUID, relayConfiguration: RelayConfiguration) async throws -> Bool
    func checkRelayHealth(relayConfiguration: RelayConfiguration) async throws -> RelayHealthStatus
    func fetchRelayStats(relayConfiguration: RelayConfiguration) async throws -> RelayStatsResponse
    func purgeRelayInbox(recipientID: String, relayConfiguration: RelayConfiguration) async throws -> RelayPurgeResponse
    /// Sprint 27 (2026-06-24): register the
    /// local iOS peer with the relay so
    /// subsequent signed requests succeed.
    /// Called from AppContainer.bootstrap
    /// after `loadOrCreateLocalIdentity`.
    func enrollLocalPeer(_ identity: LocalIdentity, relayConfiguration: RelayConfiguration) async throws -> RelayEnrollmentResponse
}

final class TransportCoordinator: TransportCoordinating {
    private let localTransport: MessageTransport
    private let relayTransportFactory: (RelayConfiguration) -> RelayMessageTransporting

    init(
        localTransport: MessageTransport = LocalOnlyTransport(),
        signingContext: PeerBoundSigningContext? = nil,
        crypto: CryptoServicing? = nil,
        relayTransportFactory: ((RelayConfiguration) -> RelayMessageTransporting)? = nil
    ) {
        self.localTransport = localTransport
        self.signingContext = signingContext
        self.crypto = crypto
        self.relayTransportFactory = relayTransportFactory ?? { config in
            RelayTransport(
                configuration: config,
                signingContext: signingContext,
                crypto: crypto
            )
        }
    }

    private let signingContext: PeerBoundSigningContext?
    private let crypto: CryptoServicing?

    func send(_ packet: OutboundTransportPacket, mode: TransportMode, relayConfiguration: RelayConfiguration) async throws {
        switch mode {
        case .localOnly:
            guard localTransport.isAvailable else {
                throw PrivateChatError.localTransportUnavailable
            }
            try await localTransport.send(packet)
        case .relayAllowed:
            let relayTransport = relayTransportFactory(relayConfiguration)
            try await relayTransport.send(packet)
        }
    }

    func fetchRelayInbox(recipientID: String, relayConfiguration: RelayConfiguration) async throws -> [OutboundTransportPacket] {
        let relayTransport = relayTransportFactory(relayConfiguration)
        return try await relayTransport.fetchInbox(recipientID: recipientID, limit: relayConfiguration.inboxPollingLimit)
    }

    func deleteRelayPacket(packetID: UUID, relayConfiguration: RelayConfiguration) async throws -> Bool {
        let relayTransport = relayTransportFactory(relayConfiguration)
        return try await relayTransport.delete(packetID: packetID)
    }

    func checkRelayHealth(relayConfiguration: RelayConfiguration) async throws -> RelayHealthStatus {
        let relayTransport = relayTransportFactory(relayConfiguration)
        return try await relayTransport.checkHealth()
    }

    func fetchRelayStats(relayConfiguration: RelayConfiguration) async throws -> RelayStatsResponse {
        let relayTransport = relayTransportFactory(relayConfiguration)
        return try await relayTransport.fetchStats()
    }

    func purgeRelayInbox(recipientID: String, relayConfiguration: RelayConfiguration) async throws -> RelayPurgeResponse {
        let relayTransport = relayTransportFactory(relayConfiguration)
        return try await relayTransport.purgeInbox(recipientID: recipientID)
    }

    func enrollLocalPeer(_ identity: LocalIdentity, relayConfiguration: RelayConfiguration) async throws -> RelayEnrollmentResponse {
        let relayTransport = relayTransportFactory(relayConfiguration)
        return try await relayTransport.enrollPublicKey(identity)
    }
}
