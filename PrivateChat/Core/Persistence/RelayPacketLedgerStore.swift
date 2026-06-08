import Foundation

protocol RelayPacketLedgerStoring {
    func load() throws -> RelayPacketLedger
    func save(_ ledger: RelayPacketLedger) throws
}

final class RelayPacketLedgerStore: RelayPacketLedgerStoring {
    private enum Account {
        static let relayPacketLedger = "relayPacketLedger.json.v1"
    }

    private let keychain: KeychainStoring
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(keychain: KeychainStoring) {
        self.keychain = keychain
        self.encoder = DateCoding.makeEncoder()
        self.decoder = DateCoding.makeDecoder()
    }

    func load() throws -> RelayPacketLedger {
        guard let data = try keychain.readData(account: Account.relayPacketLedger) else {
            return .empty
        }
        return try decoder.decode(RelayPacketLedger.self, from: data)
    }

    func save(_ ledger: RelayPacketLedger) throws {
        let data = try encoder.encode(ledger)
        try keychain.writeData(data, account: Account.relayPacketLedger)
    }
}

final class InMemoryRelayPacketLedgerStore: RelayPacketLedgerStoring {
    private var ledger: RelayPacketLedger = .empty

    func load() throws -> RelayPacketLedger {
        ledger
    }

    func save(_ ledger: RelayPacketLedger) throws {
        self.ledger = ledger
    }
}
