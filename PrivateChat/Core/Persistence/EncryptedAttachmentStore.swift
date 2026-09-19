import CryptoKit
import Foundation

protocol AttachmentStoring {
    func saveAttachment(id: UUID, data: Data) throws
    func loadAttachment(id: UUID) throws -> Data
    func deleteAttachment(id: UUID) throws
    func storeIncomingChunk(
        attachmentID: UUID,
        index: Int,
        totalChunks: Int,
        data: Data,
        expectedByteCount: Int,
        expectedSHA256: String
    ) throws -> Bool
}

final class EncryptedAttachmentStore: AttachmentStoring {
    private enum Account {
        static let encryptionKey = "local.encryptedAttachmentStore.key.v1"
    }

    private let keychain: KeychainStoring
    private let crypto: CryptoServicing
    private let fileManager: FileManager
    private let directoryURL: URL

    init(
        keychain: KeychainStoring,
        crypto: CryptoServicing,
        fileManager: FileManager = .default,
        storageDirectoryURL: URL? = nil
    ) throws {
        self.keychain = keychain
        self.crypto = crypto
        self.fileManager = fileManager

        if let storageDirectoryURL {
            self.directoryURL = storageDirectoryURL
        } else {
            let applicationSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.directoryURL = applicationSupportURL
                .appendingPathComponent("PrivateChat", isDirectory: true)
                .appendingPathComponent("Attachments", isDirectory: true)
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Self.excludeFromBackup(directoryURL)
    }

    func saveAttachment(id: UUID, data: Data) throws {
        do {
            let encrypted = try crypto.encrypt(data, key: try encryptionKey(), aad: finalAAD(id: id))
            try protectedWrite(encrypted, to: finalURL(id: id))
        } catch let error as PrivateChatError {
            throw error
        } catch {
            throw PrivateChatError.attachmentUnavailable
        }
    }

    func loadAttachment(id: UUID) throws -> Data {
        do {
            let encrypted = try Data(contentsOf: finalURL(id: id))
            return try crypto.decrypt(encrypted, key: try encryptionKey(), aad: finalAAD(id: id))
        } catch let error as PrivateChatError {
            throw error
        } catch {
            throw PrivateChatError.attachmentUnavailable
        }
    }

    func deleteAttachment(id: UUID) throws {
        let final = finalURL(id: id)
        if fileManager.fileExists(atPath: final.path) {
            try fileManager.removeItem(at: final)
        }
        try removePendingChunks(attachmentID: id)
    }

    func storeIncomingChunk(
        attachmentID: UUID,
        index: Int,
        totalChunks: Int,
        data: Data,
        expectedByteCount: Int,
        expectedSHA256: String
    ) throws -> Bool {
        guard totalChunks > 0,
              totalChunks <= 256,
              index >= 0,
              index < totalChunks,
              data.isEmpty == false,
              data.count <= 64 * 1_024,
              expectedByteCount > 0,
              expectedByteCount <= 8 * 1_048_576,
              totalChunks == Int(ceil(Double(expectedByteCount) / Double(64 * 1_024))),
              expectedSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw PrivateChatError.invalidInboundPacket
        }

        let encrypted = try crypto.encrypt(
            data,
            key: try encryptionKey(),
            aad: chunkAAD(id: attachmentID, index: index)
        )
        try protectedWrite(encrypted, to: chunkURL(id: attachmentID, index: index))

        let chunkURLs = (0..<totalChunks).map { chunkURL(id: attachmentID, index: $0) }
        guard chunkURLs.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
            return false
        }

        var assembled = Data()
        assembled.reserveCapacity(expectedByteCount)
        let key = try encryptionKey()
        for (chunkIndex, url) in chunkURLs.enumerated() {
            let encryptedChunk = try Data(contentsOf: url)
            let chunk = try crypto.decrypt(
                encryptedChunk,
                key: key,
                aad: chunkAAD(id: attachmentID, index: chunkIndex)
            )
            assembled.append(chunk)
        }

        guard assembled.count == expectedByteCount,
              RequestSigner.sha256Hex(assembled) == expectedSHA256 else {
            try removePendingChunks(attachmentID: attachmentID)
            throw PrivateChatError.invalidInboundPacket
        }

        try saveAttachment(id: attachmentID, data: assembled)
        try removePendingChunks(attachmentID: attachmentID)
        return true
    }

    private func encryptionKey() throws -> SymmetricKey {
        if let existing = try keychain.readData(account: Account.encryptionKey) {
            guard existing.count == 32 else {
                throw PrivateChatError.invalidKeyMaterial
            }
            return SymmetricKey(data: existing)
        }

        let keyData = try SecureRandom.data(byteCount: 32)
        try keychain.writeData(keyData, account: Account.encryptionKey)
        return SymmetricKey(data: keyData)
    }

    private func finalURL(id: UUID) -> URL {
        directoryURL.appendingPathComponent("\(id.uuidString.lowercased()).attachment")
    }

    private func chunkURL(id: UUID, index: Int) -> URL {
        directoryURL.appendingPathComponent("\(id.uuidString.lowercased()).\(index).chunk")
    }

    private func finalAAD(id: UUID) -> Data {
        Data("SecureChat/Attachment/v1/\(id.uuidString.lowercased())".utf8)
    }

    private func chunkAAD(id: UUID, index: Int) -> Data {
        Data("SecureChat/AttachmentChunk/v1/\(id.uuidString.lowercased())/\(index)".utf8)
    }

    private func protectedWrite(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
        try Self.excludeFromBackup(url)
    }

    private func removePendingChunks(attachmentID: UUID) throws {
        let prefix = attachmentID.uuidString.lowercased() + "."
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        for url in urls where url.lastPathComponent.hasPrefix(prefix) && url.pathExtension == "chunk" {
            try fileManager.removeItem(at: url)
        }
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }
}

final class InMemoryAttachmentStore: AttachmentStoring {
    private var attachments: [UUID: Data] = [:]
    private var chunks: [UUID: [Int: Data]] = [:]

    func saveAttachment(id: UUID, data: Data) throws {
        attachments[id] = data
    }

    func loadAttachment(id: UUID) throws -> Data {
        guard let data = attachments[id] else {
            throw PrivateChatError.attachmentUnavailable
        }
        return data
    }

    func deleteAttachment(id: UUID) throws {
        attachments.removeValue(forKey: id)
        chunks.removeValue(forKey: id)
    }

    func storeIncomingChunk(
        attachmentID: UUID,
        index: Int,
        totalChunks: Int,
        data: Data,
        expectedByteCount: Int,
        expectedSHA256: String
    ) throws -> Bool {
        guard totalChunks > 0,
              totalChunks <= 256,
              index >= 0,
              index < totalChunks,
              data.isEmpty == false,
              data.count <= 64 * 1_024,
              expectedByteCount > 0,
              expectedByteCount <= 8 * 1_048_576,
              totalChunks == Int(ceil(Double(expectedByteCount) / Double(64 * 1_024))),
              expectedSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw PrivateChatError.invalidInboundPacket
        }
        chunks[attachmentID, default: [:]][index] = data
        guard chunks[attachmentID]?.count == totalChunks else {
            return false
        }
        var assembled = Data()
        for index in 0..<totalChunks {
            guard let chunk = chunks[attachmentID]?[index] else {
                return false
            }
            assembled.append(chunk)
        }
        guard assembled.count == expectedByteCount,
              RequestSigner.sha256Hex(assembled) == expectedSHA256 else {
            throw PrivateChatError.invalidInboundPacket
        }
        attachments[attachmentID] = assembled
        chunks.removeValue(forKey: attachmentID)
        return true
    }
}
