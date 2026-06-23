import Foundation

protocol TransportCoordinating {
    func send(_ packet: OutboundTransportPacket, mode: TransportMode, relayConfiguration: RelayConfiguration) async throws
    func fetchRelayInbox(recipientID: String, relayConfiguration: RelayConfiguration) async throws -> [OutboundTransportPacket]
    func deleteRelayPacket(packetID: UUID, relayConfiguration: RelayConfiguration) async throws -> Bool
    func checkRelayHealth(relayConfiguration: RelayConfiguration) async throws -> RelayHealthStatus
    func fetchRelayStats(relayConfiguration: RelayConfiguration) async throws -> RelayStatsResponse
    func purgeRelayInbox(recipientID: String, relayConfiguration: RelayConfiguration) async throws -> RelayPurgeResponse
}

final class TransportCoordinator: TransportCoordinating {
    private let localTransport: MessageTransport
    private let relayTransportFactory: (RelayConfiguration) -> RelayMessageTransporting

    init(
        localTransport: MessageTransport = LocalOnlyTransport(),
        signingContext: PeerBoundSigningContext? = nil,
        relayTransportFactory: @escaping (RelayConfiguration) -> RelayMessageTransporting = { RelayTransport(configuration: $0, signingContext: nil) }
    ) {
        self.localTransport = localTransport
        self.signingContext = signingContext
        self.relayTransportFactory = relayTransportFactory
    }

    private let signingContext: PeerBoundSigningContext?

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
}
