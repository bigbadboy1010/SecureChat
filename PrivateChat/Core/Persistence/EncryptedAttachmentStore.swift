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
        expectedSHA256: String,
        transferContext: String
    ) throws -> Bool
}

extension AttachmentStoring {
    /// Compatibility for existing local fixtures. Production callers
    /// provide the authenticated sender/conversation/message identity.
    func storeIncomingChunk(
        attachmentID: UUID, index: Int, totalChunks: Int, data: Data,
        expectedByteCount: Int, expectedSHA256: String
    ) throws -> Bool {
        try storeIncomingChunk(
            attachmentID: attachmentID, index: index, totalChunks: totalChunks, data: data,
            expectedByteCount: expectedByteCount, expectedSHA256: expectedSHA256,
            transferContext: ""
        )
    }
}

final class EncryptedAttachmentStore: AttachmentStoring {
    private enum Account {
        static let encryptionKey = "local.encryptedAttachmentStore.key.v1"
    }

    private let keychain: KeychainStoring
    private let crypto: CryptoServicing
    private let fileManager: FileManager
    private let directoryURL: URL
    private let now: () -> Date
    private let maximumPendingTransfers: Int
    private let maximumPendingBytes: Int
    private let pendingLifetime: TimeInterval
    private static let storageLock = NSRecursiveLock()
    private static let chunkBytes = 64 * 1_024
    private static let maximumAttachmentBytes = 8 * 1_048_576
    private static let maximumManifestBytes = 4_096

    private struct PendingTransfer: Codable, Equatable {
        let version: Int
        let totalChunks: Int
        let byteCount: Int
        let sha256: String
        let transferContext: String
        let createdAt: Date
    }

    init(
        keychain: KeychainStoring,
        crypto: CryptoServicing,
        fileManager: FileManager = .default,
        storageDirectoryURL: URL? = nil,
        now: @escaping () -> Date = Date.init,
        maximumPendingTransfers: Int = 16,
        maximumPendingBytes: Int = 32 * 1_048_576,
        pendingLifetime: TimeInterval = 86_400
    ) throws {
        self.keychain = keychain
        self.crypto = crypto
        self.fileManager = fileManager
        self.now = now
        self.maximumPendingTransfers = max(1, min(maximumPendingTransfers, 16))
        self.maximumPendingBytes = max(1, min(maximumPendingBytes, 32 * 1_048_576))
        self.pendingLifetime = max(1, min(pendingLifetime, 86_400))

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
        Self.storageLock.lock()
        defer { Self.storageLock.unlock() }
        guard data.isEmpty == false, data.count <= Self.maximumAttachmentBytes else {
            throw PrivateChatError.invalidInboundPacket
        }
        if fileManager.fileExists(atPath: finalURL(id: id).path) {
            guard try loadAttachment(id: id) == data else {
                throw PrivateChatError.invalidInboundPacket
            }
            return
        }
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
        Self.storageLock.lock()
        defer { Self.storageLock.unlock() }
        do {
            let encrypted = try readBounded(finalURL(id: id), maximumBytes: Self.maximumAttachmentBytes + 28)
            return try crypto.decrypt(encrypted, key: try encryptionKey(), aad: finalAAD(id: id))
        } catch let error as PrivateChatError {
            throw error
        } catch {
            throw PrivateChatError.attachmentUnavailable
        }
    }

    func deleteAttachment(id: UUID) throws {
        Self.storageLock.lock()
        defer { Self.storageLock.unlock() }
        let final = finalURL(id: id)
        if fileManager.fileExists(atPath: final.path) {
            try fileManager.removeItem(at: final)
        }
        try removePendingChunks(attachmentID: id)
        try removeManifestIfPresent(id: id)
    }

    func storeIncomingChunk(
        attachmentID: UUID,
        index: Int,
        totalChunks: Int,
        data: Data,
        expectedByteCount: Int,
        expectedSHA256: String,
        transferContext: String = ""
    ) throws -> Bool {
        Self.storageLock.lock()
        defer { Self.storageLock.unlock() }
        guard totalChunks > 0,
              totalChunks <= 128,
              index >= 0,
              index < totalChunks,
              data.isEmpty == false,
              data.count <= Self.chunkBytes,
              expectedByteCount > 0,
              expectedByteCount <= Self.maximumAttachmentBytes,
              totalChunks == (expectedByteCount + Self.chunkBytes - 1) / Self.chunkBytes,
              data.count == min(Self.chunkBytes, expectedByteCount - index * Self.chunkBytes),
              transferContext.utf8.count <= 512,
              expectedSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw PrivateChatError.invalidInboundPacket
        }

        // A finished attachment belongs to the user's existing history.
        // Retransmission of identical content is idempotent; another
        // payload under the same UUID must never overwrite it.
        if fileManager.fileExists(atPath: finalURL(id: attachmentID).path) {
            let finished = try loadAttachment(id: attachmentID)
            guard finished.count == expectedByteCount,
                  RequestSigner.sha256Hex(finished) == expectedSHA256,
                  finished.subdata(in: (index * Self.chunkBytes)..<(index * Self.chunkBytes + data.count)) == data else {
                throw PrivateChatError.invalidInboundPacket
            }
            return true
        }

        try expirePendingTransfers()
        let manifestURL = pendingURL(id: attachmentID)
        let manifest: PendingTransfer
        let encryptedManifest: Data?
        if fileManager.fileExists(atPath: manifestURL.path) {
            manifest = try loadManifest(id: attachmentID)
            guard manifest.totalChunks == totalChunks,
                  manifest.byteCount == expectedByteCount,
                  manifest.sha256 == expectedSHA256,
                  manifest.transferContext == transferContext else {
                throw PrivateChatError.invalidInboundPacket
            }
            encryptedManifest = nil
        } else {
            manifest = PendingTransfer(
                version: 1, totalChunks: totalChunks, byteCount: expectedByteCount,
                sha256: expectedSHA256, transferContext: transferContext, createdAt: now()
            )
            encryptedManifest = try crypto.encrypt(
                DateCoding.makeEncoder().encode(manifest), key: try encryptionKey(), aad: manifestAAD(id: attachmentID)
            )
        }

        let incomingURL = chunkURL(id: attachmentID, index: index)
        let encrypted: Data?
        if fileManager.fileExists(atPath: incomingURL.path) {
            let previousEncrypted = try readBounded(incomingURL, maximumBytes: Self.chunkBytes + 28)
            let previousChunk = try crypto.decrypt(
                previousEncrypted, key: try encryptionKey(), aad: chunkAAD(id: attachmentID, index: index)
            )
            guard previousChunk == data else { throw PrivateChatError.invalidInboundPacket }
            encrypted = nil
        } else {
            encrypted = try crypto.encrypt(
                data, key: try encryptionKey(), aad: chunkAAD(id: attachmentID, index: index)
            )
        }

        let pending = try pendingStorageSnapshot()
        let newBytes = (encryptedManifest?.count ?? 0) + (encrypted?.count ?? 0)
        let count = pending.ids.union([attachmentID]).count
        guard count <= maximumPendingTransfers,
              newBytes <= maximumPendingBytes,
              pending.bytes <= maximumPendingBytes - newBytes else {
            throw PrivateChatError.persistenceFailed("Zu viele unvollständige Anhänge. Bitte später erneut versuchen.")
        }

        if let encryptedManifest { try protectedWrite(encryptedManifest, to: manifestURL) }
        if let encrypted { try protectedWrite(encrypted, to: incomingURL) }

        let chunkURLs = (0..<totalChunks).map { chunkURL(id: attachmentID, index: $0) }
        guard chunkURLs.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
            return false
        }

        var assembled = Data()
        assembled.reserveCapacity(expectedByteCount)
        let key = try encryptionKey()
        for (chunkIndex, url) in chunkURLs.enumerated() {
            let encryptedChunk = try readBounded(url, maximumBytes: Self.chunkBytes + 28)
            let chunk = try crypto.decrypt(
                encryptedChunk,
                key: key,
                aad: chunkAAD(id: attachmentID, index: chunkIndex)
            )
            guard chunk.count == min(Self.chunkBytes, expectedByteCount - chunkIndex * Self.chunkBytes),
                  chunk.count <= expectedByteCount - assembled.count else {
                throw PrivateChatError.invalidInboundPacket
            }
            assembled.append(chunk)
        }

        guard assembled.count == expectedByteCount,
              RequestSigner.sha256Hex(assembled) == expectedSHA256 else {
            throw PrivateChatError.invalidInboundPacket
        }

        try saveAttachment(id: attachmentID, data: assembled)
        try removePendingChunks(attachmentID: attachmentID)
        try removeManifestIfPresent(id: attachmentID)
        return true
    }

    private func encryptionKey() throws -> SymmetricKey {
        if let existing = try keychain.readData(account: Account.encryptionKey) {
            guard existing.count == 32 else {
                throw PrivateChatError.invalidKeyMaterial
            }
            return SymmetricKey(data: existing)
        }

        // Missing key material must not silently replace the key for
        // existing encrypted files and make recovery impossible.
        let urls = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        guard urls.contains(where: { $0.pathExtension == "attachment" || pendingIdentity(for: $0) != nil }) == false else {
            throw PrivateChatError.invalidKeyMaterial
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

    private func pendingURL(id: UUID) -> URL {
        directoryURL.appendingPathComponent("\(id.uuidString.lowercased()).pending")
    }

    private func manifestAAD(id: UUID) -> Data {
        Data("PrivateRoom/AttachmentPending/v1/\(id.uuidString.lowercased())".utf8)
    }

    private func loadManifest(id: UUID) throws -> PendingTransfer {
        let encrypted = try readBounded(pendingURL(id: id), maximumBytes: Self.maximumManifestBytes + 28)
        let data = try crypto.decrypt(encrypted, key: try encryptionKey(), aad: manifestAAD(id: id))
        let manifest = try DateCoding.makeDecoder().decode(PendingTransfer.self, from: data)
        guard manifest.version == 1, manifest.byteCount > 0,
              manifest.byteCount <= Self.maximumAttachmentBytes,
              manifest.totalChunks == (manifest.byteCount + Self.chunkBytes - 1) / Self.chunkBytes,
              manifest.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              manifest.transferContext.utf8.count <= 512,
              manifest.createdAt.timeIntervalSince1970.isFinite else {
            throw PrivateChatError.invalidInboundPacket
        }
        return manifest
    }

    /// Only recognized pending files are ever counted or expired. Stored
    /// final attachments and unrelated files remain untouched.
    private func pendingIdentity(for url: URL) -> UUID? {
        let parts = url.lastPathComponent.split(separator: ".", omittingEmptySubsequences: false)
        guard let first = parts.first, let id = UUID(uuidString: String(first)),
              String(first) == id.uuidString.lowercased() else { return nil }
        if parts.count == 2, parts[1] == "pending" { return id }
        if parts.count == 3, parts[2] == "chunk", let index = Int(parts[1]),
           (0..<128).contains(index), String(index) == parts[1] { return id }
        return nil
    }

    private func pendingStorageSnapshot() throws -> (ids: Set<UUID>, bytes: Int) {
        let urls = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        var ids = Set<UUID>()
        var bytes = 0
        for url in urls {
            guard let id = pendingIdentity(for: url) else { continue }
            ids.insert(id)
            let size = try fileSize(url)
            guard size <= maximumPendingBytes, bytes <= maximumPendingBytes - size else {
                throw PrivateChatError.persistenceFailed("Speichergrenze für unvollständige Anhänge erreicht.")
            }
            bytes += size
        }
        return (ids, bytes)
    }

    private func expirePendingTransfers() throws {
        let urls = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey])
        let ids = Set(urls.compactMap { pendingIdentity(for: $0) })
        let current = now()
        for id in ids {
            let manifest = pendingURL(id: id)
            if fileManager.fileExists(atPath: manifest.path) {
                let state = try loadManifest(id: id)
                if current.timeIntervalSince(state.createdAt) >= pendingLifetime {
                    try removePendingChunks(attachmentID: id)
                    try removeManifestIfPresent(id: id)
                }
            } else {
                // Incomplete legacy transfers or crash leftovers have no
                // authenticated creation clock. Retain them until their
                // filesystem age exceeds the same bounded lifetime.
                for url in urls where pendingIdentity(for: url) == id {
                    let values = try url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                    if let created = values.creationDate ?? values.contentModificationDate,
                       current.timeIntervalSince(created) >= pendingLifetime {
                        try fileManager.removeItem(at: url)
                    }
                }
            }
        }
    }

    private func removeManifestIfPresent(id: UUID) throws {
        let url = pendingURL(id: id)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    private func fileSize(_ url: URL) throws -> Int {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let number = attributes[.size] as? NSNumber, number.int64Value >= 0,
              number.int64Value <= Int64(Int.max) else { throw PrivateChatError.attachmentUnavailable }
        return number.intValue
    }

    private func readBounded(_ url: URL, maximumBytes: Int) throws -> Data {
        guard try fileSize(url) <= maximumBytes else { throw PrivateChatError.attachmentUnavailable }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= maximumBytes else { throw PrivateChatError.attachmentUnavailable }
        return bytes
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
    private var descriptors: [UUID: (byteCount: Int, totalChunks: Int, sha256: String, context: String)] = [:]

    func saveAttachment(id: UUID, data: Data) throws {
        if let existing = attachments[id], existing != data { throw PrivateChatError.invalidInboundPacket }
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
        descriptors.removeValue(forKey: id)
    }

    func storeIncomingChunk(
        attachmentID: UUID,
        index: Int,
        totalChunks: Int,
        data: Data,
        expectedByteCount: Int,
        expectedSHA256: String,
        transferContext: String = ""
    ) throws -> Bool {
        guard totalChunks > 0,
              totalChunks <= 128,
              index >= 0,
              index < totalChunks,
              data.isEmpty == false,
              data.count <= 64 * 1_024,
              expectedByteCount > 0,
              expectedByteCount <= 8 * 1_048_576,
              totalChunks == Int(ceil(Double(expectedByteCount) / Double(64 * 1_024))),
              data.count == min(64 * 1_024, expectedByteCount - index * 64 * 1_024),
              transferContext.utf8.count <= 512,
              expectedSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw PrivateChatError.invalidInboundPacket
        }
        if let existing = attachments[attachmentID] {
            guard existing.count == expectedByteCount,
                  RequestSigner.sha256Hex(existing) == expectedSHA256,
                  existing.subdata(in: (index * 65_536)..<(index * 65_536 + data.count)) == data else {
                throw PrivateChatError.invalidInboundPacket
            }
            return true
        }
        if let descriptor = descriptors[attachmentID] {
            guard descriptor.byteCount == expectedByteCount,
                  descriptor.totalChunks == totalChunks,
                  descriptor.sha256 == expectedSHA256,
                  descriptor.context == transferContext else { throw PrivateChatError.invalidInboundPacket }
        }
        if let existing = chunks[attachmentID]?[index], existing != data { throw PrivateChatError.invalidInboundPacket }
        let pendingBytes = chunks.values.reduce(0) { sum, chunkSet in
            sum + chunkSet.values.reduce(0) { $0 + $1.count }
        }
        let addedBytes = chunks[attachmentID]?[index] == nil ? data.count : 0
        guard chunks[attachmentID] != nil || chunks.count < 16,
              pendingBytes <= 32 * 1_048_576 - addedBytes else {
            throw PrivateChatError.persistenceFailed("Speichergrenze für unvollständige Anhänge erreicht.")
        }
        descriptors[attachmentID] = (expectedByteCount, totalChunks, expectedSHA256, transferContext)
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
        descriptors.removeValue(forKey: attachmentID)
        return true
    }
}
