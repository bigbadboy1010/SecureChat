import CryptoKit
import Foundation

protocol MessageStoring {
    func load() throws -> [StoredConversation]
    func save(_ conversations: [StoredConversation]) throws
}

final class EncryptedMessageStore: MessageStoring {
    private enum Account {
        static let databaseKey = "local.encryptedMessageStore.key.v1"
    }

    private let keychain: KeychainStoring
    private let crypto: CryptoServicing
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileURL: URL
    private let aad = Data("PrivateChat/EncryptedMessageStore/v1".utf8)

    init(keychain: KeychainStoring, crypto: CryptoServicing, fileManager: FileManager = .default) throws {
        self.keychain = keychain
        self.crypto = crypto
        self.encoder = DateCoding.makeEncoder()
        self.decoder = DateCoding.makeDecoder()

        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = applicationSupportURL.appendingPathComponent("PrivateChat", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        self.fileURL = directoryURL.appendingPathComponent("messages.store", isDirectory: false)
    }

    func load() throws -> [StoredConversation] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        do {
            let encryptedData = try Data(contentsOf: fileURL)
            let plaintext = try crypto.decrypt(encryptedData, key: try databaseKey(), aad: aad)
            return try decoder.decode([StoredConversation].self, from: plaintext)
        } catch let error as PrivateChatError {
            throw error
        } catch {
            throw PrivateChatError.persistenceFailed(error.localizedDescription)
        }
    }

    func save(_ conversations: [StoredConversation]) throws {
        do {
            let plaintext = try encoder.encode(conversations)
            let encryptedData = try crypto.encrypt(plaintext, key: try databaseKey(), aad: aad)
            #if os(iOS)
            try encryptedData.write(to: fileURL, options: [.atomic, .completeFileProtection])
            #else
            try encryptedData.write(to: fileURL, options: [.atomic])
            #endif
        } catch let error as PrivateChatError {
            throw error
        } catch {
            throw PrivateChatError.persistenceFailed(error.localizedDescription)
        }
    }

    private func databaseKey() throws -> SymmetricKey {
        if let storedKeyData = try keychain.readData(account: Account.databaseKey) {
            guard storedKeyData.count == 32 else {
                throw PrivateChatError.invalidKeyMaterial
            }
            return SymmetricKey(data: storedKeyData)
        }

        let keyData = try SecureRandom.data(byteCount: 32)
        try keychain.writeData(keyData, account: Account.databaseKey)
        return SymmetricKey(data: keyData)
    }
}
