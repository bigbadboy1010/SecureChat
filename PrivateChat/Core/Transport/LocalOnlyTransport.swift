import Foundation

final class LocalOnlyTransport: MessageTransport {
    var isAvailable: Bool { false }

    func send(_ packet: OutboundTransportPacket) async throws {
        _ = packet
        throw PrivateChatError.transportUnavailable
    }
}
