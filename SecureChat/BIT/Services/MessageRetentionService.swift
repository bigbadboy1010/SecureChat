//
// MessageRetentionService.swift
// schat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import CryptoKit

struct StoredMessage: Codable {
    let id: String
    let sender: String
    let senderPeerID: String?
    let content: String
    let timestamp: Date
    let channelTag: String?
    let isPrivate: Bool
    let recipientPeerID: String?
}

/// Local, encrypted message retention for favorited channels.
/// Design goals:
/// - No crashes on filesystem issues (degrade gracefully)
/// - Encrypt-at-rest using a symmetric key stored in Keychain
/// - Basic TTL cleanup
final class MessageRetentionService: @unchecked Sendable {
    static let shared = MessageRetentionService()

    private let fileManager = FileManager.default
    private let documentsDirectory: URL
    private let messagesDirectory: URL
    private let favoriteChannelsKey = "schat.favoriteChannels"
    private let retentionDays: Int = 7

    private let encryptionKey: SymmetricKey
    private let queue = DispatchQueue(label: "chat.schat.retention", qos: .utility)

    private init() {
        // Prefer documents directory, but fall back safely.
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        self.documentsDirectory = docs
        self.messagesDirectory = docs.appendingPathComponent("Messages", isDirectory: true)

        try? fileManager.createDirectory(at: messagesDirectory, withIntermediateDirectories: true)

        if let keyData = KeychainManager.shared.getIdentityKey(forKey: "messageRetentionKey") {
            encryptionKey = SymmetricKey(data: keyData)
        } else {
            let k = SymmetricKey(size: .bits256)
            encryptionKey = k
            _ = KeychainManager.shared.saveIdentityKey(k.withUnsafeBytes { Data($0) }, forKey: "messageRetentionKey")
        }

        cleanupOldMessages()
    }

    // MARK: - Favorites

    func getFavoriteChannels() -> Set<String> {
        let channels = UserDefaults.standard.stringArray(forKey: favoriteChannelsKey) ?? []
        return Set(channels)
    }

    @discardableResult
    func toggleFavoriteChannel(_ channel: String) -> Bool {
        var favorites = getFavoriteChannels()
        if favorites.contains(channel) {
            favorites.remove(channel)
            deleteMessagesForChannel(channel)
        } else {
            favorites.insert(channel)
        }
        UserDefaults.standard.set(Array(favorites), forKey: favoriteChannelsKey)
        return favorites.contains(channel)
    }

    func deleteAllStoredMessages() {
        queue.async {
            let urls: [URL] = (try? self.fileManager.contentsOfDirectory(at: self.messagesDirectory, includingPropertiesForKeys: nil)) ?? []
            for url in urls where url.pathExtension == "enc" {
                try? self.fileManager.removeItem(at: url)
            }
        }
    }


    // MARK: - Crypto helpers (non-actor-isolated)

    /// Encrypt data for at-rest storage. Kept `static` to avoid default-global-actor isolation issues in Swift 6.
    nonisolated static func _encrypt(_ data: Data, key: SymmetricKey) -> Data? {
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            guard let combined = sealedBox.combined else { return nil }
            return combined
        } catch {
            return nil
        }
    }

    /// Decrypt data previously encrypted via `_encrypt`.
    nonisolated static func _decrypt(_ data: Data, key: SymmetricKey) -> Data? {
        do {
            let box = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(box, using: key)
        } catch {
            return nil
        }
    }

    // MARK: - Storage

    func saveMessage(_ message: BitchatMessage, in channel: String) {
        guard getFavoriteChannels().contains(channel) else { return }
    
        let stored = StoredMessage(
            id: message.id,
            sender: message.sender,
            senderPeerID: message.senderPeerID,
            content: message.content,
            timestamp: message.timestamp,
            channelTag: message.channel,
            isPrivate: message.isPrivate,
            recipientPeerID: nil
        )
    
        // Capture isolated state *before* hopping to a detached task. This avoids Swift 6
        // default-global-actor isolation issues (e.g. MainActor) when compiling in strict mode.
        let encryptionKey = self.encryptionKey
        let messagesDirectory = self.messagesDirectory
    
        Task.detached(priority: .utility) {
            let messageData: Data
            do {
                messageData = try await MainActor.run {
                    try JSONEncoder().encode(stored)
                }
            } catch {
                return
            }
    
            guard let encryptedData = MessageRetentionService._encrypt(messageData, key: encryptionKey) else { return }
    
            let fileName = "\(channel)_\(stored.timestamp.timeIntervalSince1970)_\(stored.id).enc"
            let fileURL = messagesDirectory.appendingPathComponent(fileName)
            try? encryptedData.write(to: fileURL, options: [.atomic])
        }
    }

    func loadMessagesForChannel(_ channel: String) -> [BitchatMessage] {
        guard getFavoriteChannels().contains(channel) else { return [] }

        let encryptionKey = self.encryptionKey

        let urls: [URL] = (try? fileManager.contentsOfDirectory(at: messagesDirectory, includingPropertiesForKeys: nil)) ?? []
        let prefix = "\(channel)_"

        var out: [BitchatMessage] = []
        for url in urls where url.lastPathComponent.hasPrefix(prefix) && url.pathExtension == "enc" {
            guard let encrypted = try? Data(contentsOf: url) else { continue }
            guard let decrypted = MessageRetentionService._decrypt(encrypted, key: encryptionKey) else { continue }

            // Decode on main actor to avoid Swift 6 isolation issues if Codable is actor-isolated via module settings.
            let stored: StoredMessage?
            if Thread.isMainThread {
                stored = try? JSONDecoder().decode(StoredMessage.self, from: decrypted)
            } else {
                let sema = DispatchSemaphore(value: 0)
                var tmp: StoredMessage?
                Task { @MainActor in
                    tmp = try? JSONDecoder().decode(StoredMessage.self, from: decrypted)
                    sema.signal()
                }
                _ = sema.wait(timeout: .now() + 1.0)
                stored = tmp
            }
            guard let stored else { continue }

            let msg = BitchatMessage(
                id: stored.id,
                sender: stored.sender,
                content: stored.content,
                timestamp: stored.timestamp,
                isRelay: false,
                originalSender: nil,
                isPrivate: stored.isPrivate,
                recipientNickname: nil,
                senderPeerID: stored.senderPeerID,
                mentions: nil,
                channel: stored.channelTag,
                encryptedContent: nil,
                isEncrypted: false,
                deliveryStatus: stored.isPrivate ? .sent : nil
            )
            out.append(msg)
        }
        return out.sorted { $0.timestamp < $1.timestamp }
    }

    func deleteMessagesForChannel(_ channel: String) {
        queue.async {
            let urls: [URL] = (try? self.fileManager.contentsOfDirectory(at: self.messagesDirectory, includingPropertiesForKeys: nil)) ?? []
            let prefix = "\(channel)_"
            for url in urls where url.lastPathComponent.hasPrefix(prefix) && url.pathExtension == "enc" {
                try? self.fileManager.removeItem(at: url)
            }
        }
    }

    private func cleanupOldMessages() {
        queue.async {
            let urls: [URL] = (try? self.fileManager.contentsOfDirectory(at: self.messagesDirectory, includingPropertiesForKeys: [.creationDateKey])) ?? []
            let cutoff = Date().addingTimeInterval(-Double(self.retentionDays) * 24.0 * 3600.0)

            for url in urls where url.pathExtension == "enc" {
                if let attrs = try? self.fileManager.attributesOfItem(atPath: url.path),
                   let created = attrs[.creationDate] as? Date,
                   created < cutoff {
                    try? self.fileManager.removeItem(at: url)
                }
            }
        }
    }

    // MARK: - Crypto

    private func encrypt(_ data: Data) -> Data? {
        do {
            let sealed = try AES.GCM.seal(data, using: encryptionKey)
            // Persist nonce+ciphertext+tag in a single blob
            return sealed.combined
        } catch {
            return nil
        }
    }

    private func decrypt(_ data: Data) -> Data? {
        do {
            let box = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(box, using: encryptionKey)
        } catch {
            return nil
        }
    }
}