import Foundation
@testable import PrivateChat

final class MockKeychainStore: KeychainStoring {
    private var values: [String: Data]

    init(values: [String: Data] = [:]) {
        self.values = values
    }

    func readData(account: String) throws -> Data? {
        values[account]
    }

    func writeData(_ data: Data, account: String) throws {
        values[account] = data
    }

    func deleteData(account: String) throws {
        values.removeValue(forKey: account)
    }
}

enum TestDirectoryFactory {
    static func make(_ name: String = UUID().uuidString) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrivateChatTests", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
