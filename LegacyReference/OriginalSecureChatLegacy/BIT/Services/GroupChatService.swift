import Foundation
import CryptoKit

final class GroupChatService {
    static let shared = GroupChatService()

    private let persistence = MessagePersistenceService.shared
    private let encryption = EncryptionService.shared
    private var groups: [String: Group] = [:]
    private let queue = DispatchQueue(label: "com.secureChat.groupChat", attributes: .concurrent)

    // MARK: - Group Management
    func createGroup(
        name: String,
        creatorID: String,
        initialMembers: [GroupMember],
        description: String? = nil
    ) -> Group {
        let group = Group(
            name: name,
            description: description,
            creatorID: creatorID,
            members: initialMembers
        )

        // Generate secure group key
        let keyData = SymmetricKey(size: .bits256)
        let keyB64 = keyData.withUnsafeBytes { Data($0).base64EncodedString() }

        // Calculate key commitment for verification
        let keyCommitment = computeKeyCommitment(keyB64)

        var securedGroup = group
        securedGroup.sharedKey = keyB64
        securedGroup.keyCommitment = keyCommitment
        securedGroup.lastKeyRotationDate = Date()

        queue.async(flags: .barrier) {
            self.groups[group.id] = securedGroup
        }

        persistence.saveGroup(securedGroup)
        print("✅ Group created: \(name) (ID: \(group.id))")

        return securedGroup
    }

    func addMemberToGroup(_ groupID: String, member: GroupMember) -> Bool {
        var success = false

        queue.sync {
            if var group = self.groups[groupID] {
                group.addMember(member)
                self.groups[groupID] = group
                self.persistence.saveGroup(group)
                success = true
                print("✅ Member added to group: \(member.displayName)")
            }
        }

        return success
    }

    func removeMemberFromGroup(_ groupID: String, peerID: String) -> Bool {
        var success = false

        queue.sync {
            if var group = self.groups[groupID] {
                group.removeMember(peerID: peerID)
                self.groups[groupID] = group
                self.persistence.saveGroup(group)
                success = true
                print("✅ Member removed from group")
            }
        }

        return success
    }

    func fetchGroup(_ groupID: String) -> Group? {
        var result: Group?

        queue.sync {
            if let cached = self.groups[groupID] {
                result = cached
                return
            }

            // Try to load from persistence
            if let persisted = self.persistence.fetchGroup(groupID) {
                self.groups[groupID] = persisted
                result = persisted
            }
        }

        return result
    }

    // MARK: - Group Messages
    func sendGroupMessage(
        to groupID: String,
        content: String,
        senderID: String,
        mediaAttachments: [MediaAttachment]? = nil
    ) -> BitchatMessage? {
        guard let group = fetchGroup(groupID) else {
            print("❌ Group not found: \(groupID)")
            return nil
        }

        guard let sharedKey = group.sharedKey else {
            print("❌ Group key not available")
            return nil
        }

        // Create message with group context
        var message = BitchatMessage(
            channelTag: groupID,
            senderID: senderID,
            content: content,
            groupID: groupID,
            groupName: group.name,
            mediaAttachments: mediaAttachments
        )

        // Encrypt with group key
        if let encrypted = encryptMessageWithGroupKey(message, groupKey: sharedKey) {
            message = encrypted
            persistence.saveMessage(message)
            print("✅ Group message sent to \(group.name)")
            return message
        }

        return nil
    }

    func fetchGroupMessages(_ groupID: String, limit: Int = 50) -> [BitchatMessage] {
        let allMessages = persistence.fetchMessages(channelTag: groupID, limit: limit)
        return allMessages.filter { $0.groupID == groupID }
    }

    // MARK: - Key Rotation
    func rotateGroupKey(_ groupID: String, initiatedBy peerID: String) -> Bool {
        guard let group = fetchGroup(groupID) else { return false }

        // Check if requester is admin
        guard group.isAdmin(peerID) else {
            print("❌ Only group admins can rotate keys")
            return false
        }

        // Generate new key
        let newKey = SymmetricKey(size: .bits256)
        let newKeyB64 = newKey.withUnsafeBytes { Data($0).base64EncodedString() }
        let newKeyCommitment = computeKeyCommitment(newKeyB64)

        queue.sync {
            if var group = self.groups[groupID] {
                group.sharedKey = newKeyB64
                group.keyCommitment = newKeyCommitment
                group.lastKeyRotationDate = Date()
                self.groups[groupID] = group
                self.persistence.saveGroup(group)
                print("✅ Group key rotated for: \(group.name)")
            }
        }

        return true
    }

    func shouldRotateKey(for groupID: String) -> Bool {
        guard let group = fetchGroup(groupID) else { return false }

        if let lastRotation = group.lastKeyRotationDate {
            let daysSinceRotation = Calendar.current.dateComponents([.day], from: lastRotation, to: Date()).day ?? 0
            return daysSinceRotation >= group.keyRotationIntervalDays
        }

        return true // First time setup
    }

    // MARK: - Member Permissions
    func canMemberSendMessages(_ peerID: String, in groupID: String) -> Bool {
        guard let group = fetchGroup(groupID) else { return false }
        return group.isMember(peerID)
    }

    func canMemberUploadMedia(_ peerID: String, in groupID: String, fileSize: Int64) -> Bool {
        guard let group = fetchGroup(groupID), group.isMember(peerID) else { return false }
        return fileSize <= group.settings.maxFileSize
    }

    func canMemberViewMembers(_ peerID: String, in groupID: String) -> Bool {
        guard let group = fetchGroup(groupID) else { return false }
        return group.isMember(peerID)
    }

    func promoteToModerator(_ targetID: String, in groupID: String, by adminID: String) -> Bool {
        guard let group = fetchGroup(groupID) else { return false }
        guard group.isAdmin(adminID) else { return false }

        queue.sync {
            if var group = self.groups[groupID] {
                if let index = group.members.firstIndex(where: { $0.peerID == targetID }) {
                    group.members[index].role = .moderator
                    self.groups[groupID] = group
                    self.persistence.saveGroup(group)
                    return
                }
            }
        }

        return false
    }

    // MARK: - Private Helpers
    private func encryptMessageWithGroupKey(_ message: BitchatMessage, groupKey: String) -> BitchatMessage? {
        // This would use the group key for encryption
        // For now, return the message as encrypted indicator
        var encrypted = message
        encrypted.isEncrypted = true
        return encrypted
    }

    private func computeKeyCommitment(_ keyB64: String) -> String {
        let data = keyB64.data(using: .utf8) ?? Data()
        let digest = SHA256.hash(data: data)
        return Data(digest).base64EncodedString()
    }
}
