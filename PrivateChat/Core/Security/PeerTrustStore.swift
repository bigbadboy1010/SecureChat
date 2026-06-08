import Foundation

protocol PeerTrustStoring {
    func loadPeers() throws -> [TrustedPeer]
    func savePeers(_ peers: [TrustedPeer]) throws
}

final class PeerTrustStore: PeerTrustStoring {
    private enum Account {
        static let trustedPeers = "trustedPeers.json.v1"
    }

    private let keychain: KeychainStoring
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(keychain: KeychainStoring) {
        self.keychain = keychain
        self.encoder = DateCoding.makeEncoder()
        self.decoder = DateCoding.makeDecoder()
    }

    func loadPeers() throws -> [TrustedPeer] {
        guard let data = try keychain.readData(account: Account.trustedPeers) else {
            return []
        }
        return try decoder.decode([TrustedPeer].self, from: data)
    }

    func savePeers(_ peers: [TrustedPeer]) throws {
        let data = try encoder.encode(peers.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending })
        try keychain.writeData(data, account: Account.trustedPeers)
    }
}
