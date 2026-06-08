import Foundation

struct Group: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String?
    let creatorID: String
    let createdAt: Date
    var members: [GroupMember]
    var sharedKey: String? // Base64-encoded shared group key
    var keyCommitment: String? // HMAC for key verification
    var settings: GroupSettings
    var avatar: String? // Base64-encoded image

    // Security
    var lastKeyRotationDate: Date?
    var keyRotationIntervalDays: Int = 30

    init(
        id: String = UUID().uuidString,
        name: String,
        description: String? = nil,
        creatorID: String,
        createdAt: Date = Date(),
        members: [GroupMember] = [],
        sharedKey: String? = nil,
        keyCommitment: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.creatorID = creatorID
        self.createdAt = createdAt
        self.members = members
        self.sharedKey = sharedKey
        self.keyCommitment = keyCommitment
        self.settings = GroupSettings()
    }

    mutating func addMember(_ member: GroupMember) {
        if !members.contains(where: { $0.peerID == member.peerID }) {
            members.append(member)
        }
    }

    mutating func removeMember(peerID: String) {
        members.removeAll { $0.peerID == peerID }
    }

    func isMember(_ peerID: String) -> Bool {
        members.contains { $0.peerID == peerID }
    }

    func isAdmin(_ peerID: String) -> Bool {
        members.first(where: { $0.peerID == peerID })?.role == .admin
    }
}

struct GroupMember: Identifiable, Codable, Equatable {
    let id: String = UUID().uuidString
    let peerID: String
    let displayName: String
    let joinedAt: Date
    let role: MemberRole
    var identityFingerprint: String?
    var isVerified: Bool = false

    enum MemberRole: String, Codable {
        case admin
        case moderator
        case member
    }
}

struct GroupSettings: Codable, Equatable {
    var allowedFileTypes: Set<String> = ["txt", "jpg", "png", "gif", "pdf", "doc", "docx"]
    var maxFileSize: Int64 = 50 * 1024 * 1024 // 50MB
    var messageRetentionDays: Int? = nil
    var requiresMemberApproval: Bool = false
    var encryptionLevel: EncryptionLevel = .standard

    enum EncryptionLevel: String, Codable {
        case standard
        case maximum
    }

    enum CodingKeys: String, CodingKey {
        case allowedFileTypes
        case maxFileSize
        case messageRetentionDays
        case requiresMemberApproval
        case encryptionLevel
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Array(allowedFileTypes), forKey: .allowedFileTypes)
        try container.encode(maxFileSize, forKey: .maxFileSize)
        try container.encode(messageRetentionDays, forKey: .messageRetentionDays)
        try container.encode(requiresMemberApproval, forKey: .requiresMemberApproval)
        try container.encode(encryptionLevel, forKey: .encryptionLevel)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fileTypes = try container.decode([String].self, forKey: .allowedFileTypes)
        allowedFileTypes = Set(fileTypes)
        maxFileSize = try container.decode(Int64.self, forKey: .maxFileSize)
        messageRetentionDays = try container.decode(Int?.self, forKey: .messageRetentionDays)
        requiresMemberApproval = try container.decode(Bool.self, forKey: .requiresMemberApproval)
        encryptionLevel = try container.decode(EncryptionLevel.self, forKey: .encryptionLevel)
    }
}
