//
// ChannelInvitePayload.swift
// schat
//

import Foundation

struct ChannelInvitePayload: Codable, Equatable {
    static let currentVersion = 3

    let version: Int
    let channelTag: String
    let isProtected: Bool
    let creatorPeerID: String?
    let keyCommitment: String?
    let channelKeyB64: String?
    let wrappedChannelKeyB64: String?
    let passphraseSaltB64: String?
    let inviteToken: String?
    let expiresAtUnix: Int?
    let retentionEnabled: Bool
    let createdAt: Date

    init(channelTag: String,
         isProtected: Bool,
         creatorPeerID: String?,
         keyCommitment: String?,
         channelKeyB64: String?,
         wrappedChannelKeyB64: String?,
         passphraseSaltB64: String?,
         inviteToken: String?,
         expiresAtUnix: Int?,
         retentionEnabled: Bool,
         createdAt: Date = Date()) {
        self.version = Self.currentVersion
        self.channelTag = channelTag
        self.isProtected = isProtected
        self.creatorPeerID = creatorPeerID
        self.keyCommitment = keyCommitment
        self.channelKeyB64 = channelKeyB64
        self.wrappedChannelKeyB64 = wrappedChannelKeyB64
        self.passphraseSaltB64 = passphraseSaltB64
        self.inviteToken = inviteToken
        self.expiresAtUnix = expiresAtUnix
        self.retentionEnabled = retentionEnabled
        self.createdAt = createdAt
    }

    func encodeString() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return nil }
        return data.base64EncodedString()
    }

    static func decodeString(_ string: String) -> ChannelInvitePayload? {
        guard let data = Data(base64Encoded: string) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ChannelInvitePayload.self, from: data)
    }
}
