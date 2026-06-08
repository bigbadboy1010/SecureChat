import Foundation

protocol SecuritySettingsStoring {
    func load() throws -> AppSecurityState
    func save(_ state: AppSecurityState) throws
}

final class SecuritySettingsStore: SecuritySettingsStoring {
    private enum Account {
        static let settings = "securitySettings.json.v1"
    }

    private let keychain: KeychainStoring
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(keychain: KeychainStoring) {
        self.keychain = keychain
        self.encoder = DateCoding.makeEncoder()
        self.decoder = DateCoding.makeDecoder()
    }

    func load() throws -> AppSecurityState {
        guard let data = try keychain.readData(account: Account.settings) else {
            return .secureDefault
        }
        return try decoder.decode(AppSecurityState.self, from: data)
    }

    func save(_ state: AppSecurityState) throws {
        let data = try encoder.encode(state)
        try keychain.writeData(data, account: Account.settings)
    }
}
