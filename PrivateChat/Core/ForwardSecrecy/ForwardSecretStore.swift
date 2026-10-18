import CryptoKit
import Darwin
import Foundation

protocol ForwardSecretStoring {
    func load() throws -> Data?
    func save(_ data: Data) throws
}
final class InMemoryForwardSecretStore: ForwardSecretStoring {
    var data: Data?
    func load() throws -> Data? { data }
    func save(_ data: Data) throws { self.data = data }
}

/// Atomic replacement and explicit file/directory flush. A post-rename failure
/// poisons this instance; no subsequent operation may continue with stale state.
final class DurablePrivateFile {
    private(set) var failed = false
    func write(_ data: Data, to url: URL) throws {
        guard !failed else { throw ForwardSecretError.persistence }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        var renamed = false
        defer { if !renamed { try? FileManager.default.removeItem(at: temporary) } }
        do {
            #if os(iOS)
            try data.write(to: temporary, options: [.completeFileProtection, .withoutOverwriting])
            #else
            try data.write(to: temporary, options: [.withoutOverwriting])
            #endif
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var excluded = temporary; try excluded.setResourceValues(values)
            let file = open(temporary.path, O_RDONLY | O_NOFOLLOW)
            guard file >= 0 else { throw ForwardSecretError.persistence }
            // F_FULLFSYNC asks Apple storage to flush volatile drive caches too.
            let flushed = fcntl(file, F_FULLFSYNC)
            let synced = flushed == 0 || fsync(file) == 0
            close(file)
            guard synced else { throw ForwardSecretError.persistence }
            guard rename(temporary.path, url.path) == 0 else { throw ForwardSecretError.persistence }
            renamed = true
            let directory = open(url.deletingLastPathComponent().path, O_RDONLY)
            guard directory >= 0 else { throw ForwardSecretError.persistence }
            let result = fsync(directory); close(directory)
            guard result == 0 else { throw ForwardSecretError.persistence }
        } catch {
            if renamed { failed = true }
            throw error
        }
    }
}

final class EncryptedForwardSecretStore: ForwardSecretStoring {
    private let keychain: KeychainStoring
    private let file: URL
    private let durable = DurablePrivateFile()
    private let keyAccount = "forward-secrecy.storage-key.v1"
    private let markerAccount = "forward-secrecy.initialized.v1"
    private let aad = Data("PrivateRoom/ForwardSecretStore/v1".utf8)
    private let crypto = CryptoService()
    init(keychain: KeychainStoring, storageDirectoryURL: URL? = nil) throws {
        self.keychain = keychain
        let parent = try storageDirectoryURL ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("PrivateChat", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var excluded = parent; try excluded.setResourceValues(values)
        file = parent.appendingPathComponent("forward-secrecy.store")
    }
    func load() throws -> Data? {
        guard !durable.failed else { throw ForwardSecretError.persistence }
        guard FileManager.default.fileExists(atPath: file.path) else {
            if try keychain.readData(account: markerAccount) != nil { throw ForwardSecretError.persistence }
            return nil
        }
        guard let key = try keychain.readData(account: keyAccount), key.count == 32 else { throw ForwardSecretError.persistence }
        let bytes = try Data(contentsOf: file)
        guard bytes.count <= 32 * 1_048_576 else { throw ForwardSecretError.persistence }
        let data = try crypto.decrypt(bytes, key: SymmetricKey(data: key), aad: aad)
        if try keychain.readData(account: markerAccount) == nil { try keychain.writeData(Data([1]), account: markerAccount) }
        return data
    }
    func save(_ data: Data) throws {
        guard data.count <= 32 * 1_048_576 else { throw ForwardSecretError.persistence }
        var key = try keychain.readData(account: keyAccount)
        if key == nil {
            guard try keychain.readData(account: markerAccount) == nil else { throw ForwardSecretError.persistence }
            key = try SecureRandom.data(byteCount: 32); try keychain.writeData(key!, account: keyAccount)
        }
        guard let key, key.count == 32 else { throw ForwardSecretError.persistence }
        try durable.write(crypto.encrypt(data, key: SymmetricKey(data: key), aad: aad), to: file)
        try keychain.writeData(Data([1]), account: markerAccount)
    }
}
