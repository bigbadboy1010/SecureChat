import CryptoKit
import Foundation

protocol DraftStoring {
    func loadDraft(conversationID: UUID) throws -> String?
    func saveDraft(_ draft: String, conversationID: UUID) throws
    func deleteDraft(conversationID: UUID) throws
    func migrateLegacyDraftIfNeeded(conversationID: UUID, legacyValue: String?) throws -> String?
}

final class EncryptedDraftStore: DraftStoring {
    private enum Account {
        static let databaseKey = "local.encryptedDraftStore.key.v1"
    }

    private let keychain: KeychainStoring
    private let crypto: CryptoServicing
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileURL: URL
    private let aad = Data("PrivateChat/EncryptedDraftStore/v1".utf8)

    init(
        keychain: KeychainStoring,
        crypto: CryptoServicing,
        fileManager: FileManager = .default,
        storageDirectoryURL: URL? = nil
    ) throws {
        self.keychain = keychain
        self.crypto = crypto
        self.encoder = DateCoding.makeEncoder()
        self.decoder = DateCoding.makeDecoder()

        let directoryURL: URL
        if let storageDirectoryURL {
            directoryURL = storageDirectoryURL
        } else {
            let applicationSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            directoryURL = applicationSupportURL.appendingPathComponent("PrivateChat", isDirectory: true)
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Self.excludeFromBackup(directoryURL)
        self.fileURL = directoryURL.appendingPathComponent("drafts.store", isDirectory: false)
    }

    func loadDraft(conversationID: UUID) throws -> String? {
        let drafts = try loadAllDrafts()
        return drafts[conversationID.uuidString]
    }

    func saveDraft(_ draft: String, conversationID: UUID) throws {
        var drafts = try loadAllDrafts()
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDraft.isEmpty {
            drafts.removeValue(forKey: conversationID.uuidString)
        } else {
            drafts[conversationID.uuidString] = draft
        }
        try saveAllDrafts(drafts)
    }

    func deleteDraft(conversationID: UUID) throws {
        var drafts = try loadAllDrafts()
        drafts.removeValue(forKey: conversationID.uuidString)
        try saveAllDrafts(drafts)
    }

    func migrateLegacyDraftIfNeeded(conversationID: UUID, legacyValue: String?) throws -> String? {
        if let existingDraft = try loadDraft(conversationID: conversationID) {
            return existingDraft
        }

        guard let legacyValue, legacyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }

        try saveDraft(legacyValue, conversationID: conversationID)
        return legacyValue
    }

    private func loadAllDrafts() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        do {
            let encryptedData = try Data(contentsOf: fileURL)
            let plaintext = try crypto.decrypt(encryptedData, key: try databaseKey(), aad: aad)
            return try decoder.decode([String: String].self, from: plaintext)
        } catch let error as PrivateChatError {
            throw error
        } catch {
            throw PrivateChatError.persistenceFailed(error.localizedDescription)
        }
    }

    private func saveAllDrafts(_ drafts: [String: String]) throws {
        do {
            if drafts.isEmpty {
                try? FileManager.default.removeItem(at: fileURL)
                return
            }

            let plaintext = try encoder.encode(drafts)
            let encryptedData = try crypto.encrypt(plaintext, key: try databaseKey(), aad: aad)
            #if os(iOS)
            try encryptedData.write(to: fileURL, options: [.atomic, .completeFileProtection])
            #else
            try encryptedData.write(to: fileURL, options: [.atomic])
            #endif
            try Self.excludeFromBackup(fileURL)
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

    private static func excludeFromBackup(_ url: URL) throws {
        var mutableURL = url
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try mutableURL.setResourceValues(resourceValues)
    }
}

final class InMemoryDraftStore: DraftStoring {
    private var drafts: [String: String]

    init(drafts: [String: String] = [:]) {
        self.drafts = drafts
    }

    func loadDraft(conversationID: UUID) throws -> String? {
        drafts[conversationID.uuidString]
    }

    func saveDraft(_ draft: String, conversationID: UUID) throws {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDraft.isEmpty {
            drafts.removeValue(forKey: conversationID.uuidString)
        } else {
            drafts[conversationID.uuidString] = draft
        }
    }

    func deleteDraft(conversationID: UUID) throws {
        drafts.removeValue(forKey: conversationID.uuidString)
    }

    func migrateLegacyDraftIfNeeded(conversationID: UUID, legacyValue: String?) throws -> String? {
        if let existingDraft = drafts[conversationID.uuidString] {
            return existingDraft
        }
        guard let legacyValue, legacyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        drafts[conversationID.uuidString] = legacyValue
        return legacyValue
    }
}
