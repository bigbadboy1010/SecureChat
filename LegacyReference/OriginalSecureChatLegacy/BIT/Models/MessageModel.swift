import Foundation

struct BitchatMessage: Identifiable, Codable, Equatable {
    let id: String
    let channelTag: String
    let senderID: String
    let content: String
    let timestamp: Date
    let isEncrypted: Bool
    let publicKey: String?
    let signature: String?
    let nonce: String?

    // Group Chat Support
    let groupID: String?
    let groupName: String?

    // Rich Media Support
    let mediaAttachments: [MediaAttachment]?

    // Message Status
    var deliveryStatus: DeliveryStatus = .pending
    var readBy: [String] = []

    // Reactions & Metadata
    var reactions: [String: [String]] = [:] // emoji -> [userIDs]
    var editedAt: Date?
    var deletedAt: Date?
    var replyTo: String? // message ID

    init(
        id: String = UUID().uuidString,
        channelTag: String,
        senderID: String,
        content: String,
        timestamp: Date = Date(),
        isEncrypted: Bool = true,
        publicKey: String? = nil,
        signature: String? = nil,
        nonce: String? = nil,
        groupID: String? = nil,
        groupName: String? = nil,
        mediaAttachments: [MediaAttachment]? = nil,
        replyTo: String? = nil
    ) {
        self.id = id
        self.channelTag = channelTag
        self.senderID = senderID
        self.content = content
        self.timestamp = timestamp
        self.isEncrypted = isEncrypted
        self.publicKey = publicKey
        self.signature = signature
        self.nonce = nonce
        self.groupID = groupID
        self.groupName = groupName
        self.mediaAttachments = mediaAttachments
        self.replyTo = replyTo
    }
}

enum DeliveryStatus: String, Codable {
    case pending
    case sent
    case delivered
    case read
    case failed
}

struct MediaAttachment: Identifiable, Codable, Equatable {
    let id: String
    let type: MediaType
    let fileName: String
    let fileSize: Int64
    let mimeType: String
    let encryptedData: Data
    let encryptionKey: String // Base64-encoded AES key
    let thumbnailBase64: String? // For images/videos
    let uploadProgress: Double? = nil

    enum MediaType: String, Codable {
        case image
        case video
        case audio
        case document
        case file
    }

    init(
        type: MediaType,
        fileName: String,
        fileSize: Int64,
        mimeType: String,
        encryptedData: Data,
        encryptionKey: String,
        thumbnailBase64: String? = nil
    ) {
        self.id = UUID().uuidString
        self.type = type
        self.fileName = fileName
        self.fileSize = fileSize
        self.mimeType = mimeType
        self.encryptedData = encryptedData
        self.encryptionKey = encryptionKey
        self.thumbnailBase64 = thumbnailBase64
    }
}
