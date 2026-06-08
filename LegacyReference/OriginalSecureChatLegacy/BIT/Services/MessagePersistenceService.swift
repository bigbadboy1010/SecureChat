import Foundation
import SQLite3

final class MessagePersistenceService {
    static let shared = MessagePersistenceService()

    private let fileManager = FileManager.default
    private let documentsPath: String
    private let dbPath: String
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.secureChat.persistence", attributes: .concurrent)

    private init() {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        documentsPath = paths[0].path
        dbPath = "\(documentsPath)/messages.db"

        initializeDatabase()
    }

    // MARK: - Database Initialization
    private func initializeDatabase() {
        queue.async(flags: .barrier) {
            guard sqlite3_open(self.dbPath, &self.db) == SQLITE_OK else {
                print("❌ Failed to open database")
                return
            }

            let createMessagesTable = """
                CREATE TABLE IF NOT EXISTS messages (
                    id TEXT PRIMARY KEY,
                    channelTag TEXT NOT NULL,
                    groupID TEXT,
                    senderID TEXT NOT NULL,
                    content TEXT NOT NULL,
                    timestamp INTEGER NOT NULL,
                    isEncrypted INTEGER NOT NULL,
                    deliveryStatus TEXT NOT NULL,
                    mediaJSON TEXT,
                    replyTo TEXT,
                    editedAt INTEGER,
                    deletedAt INTEGER,
                    signature TEXT,
                    nonce TEXT,
                    publicKey TEXT,
                    createdAt INTEGER NOT NULL,
                    INDEX idx_channelTag (channelTag),
                    INDEX idx_groupID (groupID),
                    INDEX idx_timestamp (timestamp)
                );
            """

            let createGroupsTable = """
                CREATE TABLE IF NOT EXISTS groups (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    description TEXT,
                    creatorID TEXT NOT NULL,
                    createdAt INTEGER NOT NULL,
                    sharedKey TEXT,
                    keyCommitment TEXT,
                    lastKeyRotation INTEGER,
                    membersJSON TEXT NOT NULL,
                    settingsJSON TEXT NOT NULL
                );
            """

            var createError: UnsafeMutablePointer<Int8>?
            defer { sqlite3_free(createError) }

            if sqlite3_exec(self.db, createMessagesTable, nil, nil, &createError) != SQLITE_OK {
                let message = createError.map { String(cString: $0) } ?? "Unknown error"
                print("❌ Failed to create messages table: \(message)")
            } else {
                print("✅ Messages table ready")
            }

            if sqlite3_exec(self.db, createGroupsTable, nil, nil, &createError) != SQLITE_OK {
                let message = createError.map { String(cString: $0) } ?? "Unknown error"
                print("❌ Failed to create groups table: \(message)")
            } else {
                print("✅ Groups table ready")
            }
        }
    }

    // MARK: - Message Operations
    func saveMessage(_ message: BitchatMessage) {
        queue.async(flags: .barrier) {
            guard let db = self.db else { return }

            let mediaJSON = try? JSONEncoder().encode(message.mediaAttachments).base64EncodedString()
            let timestamp = Int(message.timestamp.timeIntervalSince1970)
            let editedAt = message.editedAt.map { Int($0.timeIntervalSince1970) }
            let deletedAt = message.deletedAt.map { Int($0.timeIntervalSince1970) }

            let query = """
                INSERT OR REPLACE INTO messages
                (id, channelTag, groupID, senderID, content, timestamp, isEncrypted, deliveryStatus,
                 mediaJSON, replyTo, editedAt, deletedAt, signature, nonce, publicKey, createdAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
                print("❌ Failed to prepare insert statement")
                return
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, message.id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, message.channelTag, -1, SQLITE_TRANSIENT)
            if let groupID = message.groupID {
                sqlite3_bind_text(stmt, 3, groupID, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            sqlite3_bind_text(stmt, 4, message.senderID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, message.content, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 6, Int64(timestamp))
            sqlite3_bind_int(stmt, 7, message.isEncrypted ? 1 : 0)
            sqlite3_bind_text(stmt, 8, message.deliveryStatus.rawValue, -1, SQLITE_TRANSIENT)
            if let mediaJSON = mediaJSON {
                sqlite3_bind_text(stmt, 9, mediaJSON, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 9)
            }
            if let replyTo = message.replyTo {
                sqlite3_bind_text(stmt, 10, replyTo, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 10)
            }
            if let editedAt = editedAt {
                sqlite3_bind_int64(stmt, 11, Int64(editedAt))
            } else {
                sqlite3_bind_null(stmt, 11)
            }
            if let deletedAt = deletedAt {
                sqlite3_bind_int64(stmt, 12, Int64(deletedAt))
            } else {
                sqlite3_bind_null(stmt, 12)
            }
            if let signature = message.signature {
                sqlite3_bind_text(stmt, 13, signature, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 13)
            }
            if let nonce = message.nonce {
                sqlite3_bind_text(stmt, 14, nonce, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 14)
            }
            if let publicKey = message.publicKey {
                sqlite3_bind_text(stmt, 15, publicKey, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 15)
            }
            sqlite3_bind_int64(stmt, 16, Int64(Date().timeIntervalSince1970))

            if sqlite3_step(stmt) == SQLITE_DONE {
                print("✅ Message saved: \(message.id)")
            } else {
                print("❌ Failed to insert message")
            }
        }
    }

    func fetchMessages(channelTag: String, limit: Int = 100, offset: Int = 0) -> [BitchatMessage] {
        var result: [BitchatMessage] = []

        queue.sync {
            guard let db = self.db else { return }

            let query = """
                SELECT id, channelTag, groupID, senderID, content, timestamp, isEncrypted,
                       deliveryStatus, mediaJSON, replyTo, editedAt, deletedAt, signature, nonce, publicKey
                FROM messages
                WHERE channelTag = ? AND deletedAt IS NULL
                ORDER BY timestamp DESC
                LIMIT ? OFFSET ?
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, channelTag, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 2, Int32(limit))
            sqlite3_bind_int(stmt, 3, Int32(offset))

            while sqlite3_step(stmt) == SQLITE_ROW {
                if let message = self.parseMessageFromStatement(stmt) {
                    result.append(message)
                }
            }
        }

        return result.reversed()
    }

    func deleteMessage(_ messageID: String) {
        queue.async(flags: .barrier) {
            guard let db = self.db else { return }

            let query = "UPDATE messages SET deletedAt = ? WHERE id = ?"
            var stmt: OpaquePointer?

            if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, Int64(Date().timeIntervalSince1970))
                sqlite3_bind_text(stmt, 2, messageID, -1, SQLITE_TRANSIENT)

                if sqlite3_step(stmt) == SQLITE_DONE {
                    print("✅ Message deleted: \(messageID)")
                }

                sqlite3_finalize(stmt)
            }
        }
    }

    // MARK: - Group Operations
    func saveGroup(_ group: Group) {
        queue.async(flags: .barrier) {
            guard let db = self.db else { return }

            let membersJSON = (try? JSONEncoder().encode(group.members).base64EncodedString()) ?? ""
            let settingsJSON = (try? JSONEncoder().encode(group.settings).base64EncodedString()) ?? ""
            let lastKeyRotation = group.lastKeyRotationDate.map { Int($0.timeIntervalSince1970) }

            let query = """
                INSERT OR REPLACE INTO groups
                (id, name, description, creatorID, createdAt, sharedKey, keyCommitment, lastKeyRotation, membersJSON, settingsJSON)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, group.id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, group.name, -1, SQLITE_TRANSIENT)
            if let desc = group.description {
                sqlite3_bind_text(stmt, 3, desc, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            sqlite3_bind_text(stmt, 4, group.creatorID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 5, Int64(group.createdAt.timeIntervalSince1970))
            if let key = group.sharedKey {
                sqlite3_bind_text(stmt, 6, key, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            if let commit = group.keyCommitment {
                sqlite3_bind_text(stmt, 7, commit, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            if let rotation = lastKeyRotation {
                sqlite3_bind_int64(stmt, 8, Int64(rotation))
            } else {
                sqlite3_bind_null(stmt, 8)
            }
            sqlite3_bind_text(stmt, 9, membersJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 10, settingsJSON, -1, SQLITE_TRANSIENT)

            if sqlite3_step(stmt) == SQLITE_DONE {
                print("✅ Group saved: \(group.name)")
            }
        }
    }

    func fetchGroup(_ groupID: String) -> Group? {
        var result: Group?

        queue.sync {
            guard let db = self.db else { return }

            let query = """
                SELECT id, name, description, creatorID, createdAt, sharedKey, keyCommitment, lastKeyRotation, membersJSON, settingsJSON
                FROM groups WHERE id = ?
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, groupID, -1, SQLITE_TRANSIENT)

            if sqlite3_step(stmt) == SQLITE_ROW {
                result = self.parseGroupFromStatement(stmt)
            }
        }

        return result
    }

    // MARK: - Cleanup
    func deleteExpiredMessages(olderThan days: Int) {
        let expirationDate = Date().addingTimeInterval(-TimeInterval(days * 86400))
        queue.async(flags: .barrier) {
            guard let db = self.db else { return }

            let query = "UPDATE messages SET deletedAt = ? WHERE timestamp < ?"
            var stmt: OpaquePointer?

            if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, Int64(Date().timeIntervalSince1970))
                sqlite3_bind_int64(stmt, 2, Int64(expirationDate.timeIntervalSince1970))

                if sqlite3_step(stmt) == SQLITE_DONE {
                    print("✅ Expired messages cleaned up")
                }

                sqlite3_finalize(stmt)
            }
        }
    }

    // MARK: - Helper Methods
    private func parseMessageFromStatement(_ stmt: OpaquePointer) -> BitchatMessage? {
        guard let id = String(cString: sqlite3_column_text(stmt, 0), encoding: .utf8),
              let channelTag = String(cString: sqlite3_column_text(stmt, 1), encoding: .utf8),
              let senderID = String(cString: sqlite3_column_text(stmt, 3), encoding: .utf8),
              let content = String(cString: sqlite3_column_text(stmt, 4), encoding: .utf8),
              let statusStr = String(cString: sqlite3_column_text(stmt, 7), encoding: .utf8) else {
            return nil
        }

        let timestamp = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 5)))
        let isEncrypted = sqlite3_column_int(stmt, 6) != 0
        let groupID = sqlite3_column_text(stmt, 2) != nil ? String(cString: sqlite3_column_text(stmt, 2), encoding: .utf8) : nil
        let deliveryStatus = DeliveryStatus(rawValue: statusStr) ?? .pending

        var message = BitchatMessage(
            id: id,
            channelTag: channelTag,
            senderID: senderID,
            content: content,
            timestamp: timestamp,
            isEncrypted: isEncrypted,
            groupID: groupID
        )
        message.deliveryStatus = deliveryStatus

        if sqlite3_column_text(stmt, 8) != nil,
           let mediaJSON = String(cString: sqlite3_column_text(stmt, 8), encoding: .utf8),
           let mediaData = Data(base64Encoded: mediaJSON),
           let attachments = try? JSONDecoder().decode([MediaAttachment].self, from: mediaData) {
            message.mediaAttachments = attachments
        }

        return message
    }

    private func parseGroupFromStatement(_ stmt: OpaquePointer) -> Group? {
        guard let id = String(cString: sqlite3_column_text(stmt, 0), encoding: .utf8),
              let name = String(cString: sqlite3_column_text(stmt, 1), encoding: .utf8),
              let creatorID = String(cString: sqlite3_column_text(stmt, 3), encoding: .utf8) else {
            return nil
        }

        let createdAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 4)))
        let description = sqlite3_column_text(stmt, 2) != nil ? String(cString: sqlite3_column_text(stmt, 2), encoding: .utf8) : nil
        let sharedKey = sqlite3_column_text(stmt, 5) != nil ? String(cString: sqlite3_column_text(stmt, 5), encoding: .utf8) : nil
        let keyCommitment = sqlite3_column_text(stmt, 6) != nil ? String(cString: sqlite3_column_text(stmt, 6), encoding: .utf8) : nil

        var members: [GroupMember] = []
        if sqlite3_column_text(stmt, 8) != nil,
           let membersJSON = String(cString: sqlite3_column_text(stmt, 8), encoding: .utf8),
           let membersData = Data(base64Encoded: membersJSON),
           let decodedMembers = try? JSONDecoder().decode([GroupMember].self, from: membersData) {
            members = decodedMembers
        }

        var group = Group(
            id: id,
            name: name,
            description: description,
            creatorID: creatorID,
            createdAt: createdAt,
            members: members,
            sharedKey: sharedKey,
            keyCommitment: keyCommitment
        )

        if sqlite3_column_text(stmt, 9) != nil,
           let settingsJSON = String(cString: sqlite3_column_text(stmt, 9), encoding: .utf8),
           let settingsData = Data(base64Encoded: settingsJSON),
           let settings = try? JSONDecoder().decode(GroupSettings.self, from: settingsData) {
            group.settings = settings
        }

        return group
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
}
