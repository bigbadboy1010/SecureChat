import CryptoKit
import XCTest
@testable import PrivateChat

@MainActor
final class UserSessionPrivacyTests: XCTestCase {
    func testRateLimitAndServerFailureBackoffPreserveOutboxAndDoNotRetryImmediately() async throws {
        for status in [429, 503] {
            let fixture = try Fixture()
            let id = try XCTUnwrap(fixture.service.createConversation(title: "Bob", peerID: fixture.bob.id))
            fixture.transport.sendFailure = PrivateChatError.relayHTTPError(statusCode: status, message: nil)
            let first = await fixture.service.sendMessage(conversationID: id, body: "keep durable")
            XCTAssertTrue(first)
            XCTAssertTrue(fixture.service.relayConnectivityStatus.isPaused)
            XCTAssertEqual(fixture.transport.sentPackets.count, 1)
            await fixture.service.retryPendingOutboundMessages()
            XCTAssertEqual(fixture.transport.sentPackets.count, 1, "Backoff must prevent blind retry")
            let second = await fixture.service.sendMessage(conversationID: id, body: "new queued message")
            XCTAssertTrue(second)
            XCTAssertEqual(fixture.transport.sentPackets.count, 1, "New content may queue but must respect backoff")
            XCTAssertEqual(fixture.messages.persisted.first?.messages.count, 2)
            XCTAssertEqual(fixture.service.conversations.first?.messages.last?.status, .queued)
        }
    }
    func testUnsupportedControlCharactersAreRejectedBeforeQueueingOrTransport() async throws {
        let fixture = try Fixture()
        let id = try XCTUnwrap(fixture.service.createConversation(title: "Bob", peerID: fixture.bob.id))
        let accepted = await fixture.service.sendAttachment(conversationID: id, body: "caption\u{0001}", data: Data([1, 2]), kind: .document, fileName: "fixture.bin", mimeType: "application/octet-stream")
        XCTAssertFalse(accepted)
        XCTAssertTrue(fixture.service.conversations.first?.messages.isEmpty == true)
        XCTAssertTrue(fixture.transport.sentPackets.isEmpty)
        XCTAssertNotNil(fixture.service.lastErrorMessage)
    }
    func testLockedServiceRefusesSensitiveActionsAndNetworkCalls() async throws {
        let fixture = try Fixture()
        fixture.service.endUserSession()
        XCTAssertNil(fixture.service.currentUserSessionID)
        XCTAssertNil(fixture.service.createConversation(title: "Locked", peerID: fixture.bob.id))
        XCTAssertNil(fixture.service.createSoloTestConversation())
        let sent = await fixture.service.sendMessage(conversationID: UUID(), body: "private")
        XCTAssertFalse(sent)
        XCTAssertFalse(fixture.service.importPeer(from: "invalid"))
        XCTAssertFalse(fixture.service.verifyPeer(id: fixture.bob.id))
        let enabled = await fixture.service.enablePrivateRoomRelay()
        XCTAssertFalse(enabled)
        XCTAssertThrowsError(try fixture.service.makeLocalPairingCode())
        XCTAssertEqual(fixture.service.loadDraft(conversationID: UUID(), legacyUserDefaultsValue: "old-plain-draft"), "")
        await fixture.service.syncRelayInbox()
        await fixture.service.checkRelayHealth()
        await fixture.service.fetchRelayStats()
        XCTAssertEqual(fixture.transport.fetchCount, 0)
        XCTAssertEqual(fixture.transport.healthCount, 0)
        XCTAssertEqual(fixture.transport.statsCount, 0)
        XCTAssertEqual(fixture.transport.enrollmentCount, 0)
        XCTAssertTrue(fixture.transport.sentPackets.isEmpty)
        XCTAssertTrue(fixture.service.conversations.isEmpty)
    }

    func testLateFetchCannotProcessOrAcknowledgeAfterLockAndNewUnlock() async throws {
        let fixture = try Fixture()
        fixture.transport.inbox = [try fixture.packet(body: "confidential incoming")]
        let oldID = fixture.service.currentUserSessionID
        fixture.transport.onFetch = {
            fixture.service.endUserSession()
            XCTAssertTrue(fixture.service.beginUserSession())
        }
        await fixture.service.syncRelayInbox()
        XCTAssertFalse(fixture.service.isCurrentUserSession(oldID))
        XCTAssertTrue(fixture.service.conversations.isEmpty)
        XCTAssertTrue(fixture.transport.deletedIDs.isEmpty)
        XCTAssertTrue(fixture.transport.sentPackets.isEmpty)
        XCTAssertNil(fixture.service.lastRelaySyncSummary)

        fixture.transport.onFetch = nil
        await fixture.service.syncRelayInbox()
        XCTAssertEqual(fixture.service.conversations.first?.messages.first?.body, "confidential incoming")
        XCTAssertEqual(fixture.transport.deletedIDs.count, 1)
    }

    func testLockDuringReceiptStopsFurtherAcknowledgementAndSuccessPublishing() async throws {
        let fixture = try Fixture()
        fixture.transport.inbox = [try fixture.packet(body: "already durable")]
        fixture.transport.onSend = {
            fixture.service.endUserSession()
            XCTAssertTrue(fixture.service.beginUserSession())
        }
        await fixture.service.syncRelayInbox()
        XCTAssertEqual(fixture.messages.persisted.first?.messages.first?.body, "already durable")
        XCTAssertEqual(fixture.transport.sentPackets.count, 1, "An already handed-off request cannot be withdrawn")
        XCTAssertTrue(fixture.transport.deletedIDs.isEmpty, "No new ACK is allowed after the session changed")
        XCTAssertNil(fixture.service.lastRelaySyncSummary)
    }

    func testAttachmentSendStopsAfterFirstChunkWhenSessionChanges() async throws {
        let fixture = try Fixture()
        let conversationID = try XCTUnwrap(fixture.service.createConversation(title: "Bob", peerID: fixture.bob.id))
        fixture.transport.onSend = {
            fixture.service.endUserSession()
            XCTAssertTrue(fixture.service.beginUserSession())
        }
        let accepted = await fixture.service.sendAttachment(
            conversationID: conversationID, body: "test caption", data: Data(repeating: 7, count: 150_000),
            kind: .document, fileName: "test.bin", mimeType: "application/octet-stream"
        )
        XCTAssertFalse(accepted, "Stale UI work must not publish a success to its old view")
        XCTAssertEqual(fixture.transport.sentPackets.count, 1)
        XCTAssertEqual(fixture.service.conversations.first?.messages.first?.status, .queued)
    }

    func testLateEnrollmentDoesNotPublishConnectedState() async throws {
        let fixture = try Fixture()
        fixture.transport.onEnroll = {
            fixture.service.endUserSession()
            XCTAssertTrue(fixture.service.beginUserSession())
        }
        let enrolled = await fixture.service.enrollLocalPeerIfNeeded()
        XCTAssertFalse(enrolled)
        XCTAssertNotEqual(fixture.service.lastRelayHealthMessage, "PrivateRoom ist verbunden.")
    }

    func testDeletionAndRetentionDoNotReclaimFilesWhenDatabaseCommitFails() throws {
        let attachment = ChatAttachment(id: UUID(), kind: .image, fileName: "photo.jpg", mimeType: "image/jpeg", byteCount: 4)
        let fixture = try Fixture(attachment: attachment, oldMessage: true)
        let conversationID = try XCTUnwrap(fixture.service.conversations.first?.id)
        let messageID = try XCTUnwrap(fixture.service.conversations.first?.messages.first?.id)
        fixture.messages.failSaves = true
        fixture.service.deleteMessage(messageID: messageID, conversationID: conversationID)
        fixture.service.clearConversationMessages(id: conversationID)
        fixture.service.deleteConversation(id: conversationID)
        fixture.service.purgeExpiredLocalMessages()
        XCTAssertEqual(fixture.service.conversations, fixture.messages.persisted)
        XCTAssertEqual(fixture.service.conversations.first?.messages.count, 1)
        XCTAssertTrue(fixture.attachments.deletedIDs.isEmpty)
        XCTAssertEqual(try fixture.attachments.loadAttachment(id: attachment.id), Data([1, 2, 3, 4]))
        XCTAssertNil(fixture.service.lastLocalRetentionSummary)
    }

    func testFailedBlockClosesSessionAndRecoveryPersistsTheBlockBeforeReopening() throws {
        let fixture = try Fixture()
        fixture.peers.failSaves = true
        fixture.service.blockPeer(id: fixture.bob.id)
        XCTAssertEqual(fixture.service.trustedPeers.first?.trustState, .blocked)
        XCTAssertNotNil(fixture.service.criticalSessionFailure)
        XCTAssertNil(fixture.service.currentUserSessionID)
        XCTAssertFalse(fixture.service.beginUserSession())
        fixture.peers.failSaves = false
        XCTAssertTrue(fixture.service.beginUserSession())
        XCTAssertEqual(fixture.peers.persisted.first?.trustState, .blocked)
        XCTAssertNil(fixture.service.criticalSessionFailure)
    }

    func testFailedPeerDeletionRollsBackTrustAndPreservesHistoryAndPhotos() throws {
        let attachment = ChatAttachment(id: UUID(), kind: .image, fileName: "photo.jpg", mimeType: "image/jpeg", byteCount: 4)
        let fixture = try Fixture(attachment: attachment)
        fixture.messages.failSaves = true
        fixture.service.deletePeer(id: fixture.bob.id)
        XCTAssertEqual(fixture.peers.persisted.count, 1)
        XCTAssertEqual(fixture.service.trustedPeers.count, 1)
        XCTAssertEqual(fixture.service.conversations, fixture.messages.persisted)
        XCTAssertTrue(fixture.attachments.deletedIDs.isEmpty)
    }

    func testUndurableDeliveryReceiptIsNotAcknowledged() async throws {
        let fixture = try Fixture(outgoingMessage: true)
        let message = try XCTUnwrap(fixture.service.conversations.first?.messages.first)
        fixture.transport.inbox = [try fixture.packet(kind: .deliveryReceipt, body: nil, deliveredMessageID: message.id)]
        fixture.messages.failSaves = true
        await fixture.service.syncRelayInbox()
        XCTAssertTrue(fixture.transport.deletedIDs.isEmpty)
        XCTAssertEqual(fixture.service.conversations.first?.messages.first?.status, .sentToRelay)
        XCTAssertEqual(fixture.service.lastRelaySyncSummary?.rejectedCount, 1)
    }

    @MainActor
    private final class Fixture {
        let alice: LocalIdentity
        let bob: LocalIdentity
        let messages: SessionMessageStore
        let peers: SessionPeerStore
        let attachments: SessionAttachmentStore
        let transport: SessionTransport
        let service: ConversationService

        init(attachment: ChatAttachment? = nil, oldMessage: Bool = false, outgoingMessage: Bool = false) throws {
            let crypto = CryptoService()
            func identity(_ name: String) -> LocalIdentity {
                let signing = Curve25519.Signing.PrivateKey()
                return LocalIdentity(id: crypto.peerID(publicKeyData: signing.publicKey.rawRepresentation), displayName: name,
                                     keyAgreementPrivateKey: .init(), signingPrivateKey: signing)
            }
            let localAlice = identity("Alice")
            let localBob = identity("Bob")
            let localAttachments = SessionAttachmentStore()
            let localTransport = SessionTransport()
            let peer = TrustedPeer(
                id: localBob.id, displayName: "Bob", keyAgreementPublicKeyBase64: localBob.keyAgreementPublicKeyData.base64EncodedString(),
                signingPublicKeyBase64: localBob.signingPublicKeyData.base64EncodedString(),
                safetyNumber: SafetyNumberV3.make(localSigningPublicKeyData: localAlice.signingPublicKeyData,
                                                localKeyAgreementPublicKeyData: localAlice.keyAgreementPublicKeyData,
                                                remoteSigningPublicKeyData: localBob.signingPublicKeyData,
                                                remoteKeyAgreementPublicKeyData: localBob.keyAgreementPublicKeyData), trustState: .verified
            )
            let localPeers = SessionPeerStore(seed: [peer])
            var seed: [StoredConversation] = []
            if attachment != nil || outgoingMessage {
                let date = oldMessage ? Date().addingTimeInterval(-40 * 86_400) : Date()
                let conversation = Conversation(title: "Bob", peerID: localBob.id, createdAt: date)
                let message = ChatMessage(conversationID: conversation.id, senderID: outgoingMessage ? localAlice.id : localBob.id,
                                          recipientID: outgoingMessage ? localBob.id : localAlice.id, body: "owned test history", createdAt: date,
                                          status: outgoingMessage ? .sentToRelay : .delivered, isIncoming: !outgoingMessage, attachment: attachment)
                seed = [StoredConversation(conversation: conversation, messages: [message])]
                if let attachment { try localAttachments.saveAttachment(id: attachment.id, data: Data([1, 2, 3, 4])) }
            }
            let localMessages = SessionMessageStore(seed: seed)
            var state = AppSecurityState.secureDefault
            state.transportMode = .relayAllowed
            state.relayConfiguration = RelayConfiguration(isEnabled: true, baseURLString: SecureChatProductionProfile.relayBaseURLString, registrationToken: nil)
            let localService = ConversationService(localIdentity: localAlice, messageStore: localMessages, draftStore: MockDraftStore(), peerTrustStore: localPeers,
                                          settingsStore: MockSecuritySettingsStore(seed: state), relayPacketLedgerStore: MockRelayPacketLedgerStore(),
                                          identityManager: MockIdentityManager(localIdentity: localAlice), crypto: crypto,
                                          transportCoordinator: localTransport, attachmentStore: localAttachments)
            alice = localAlice
            bob = localBob
            messages = localMessages
            peers = localPeers
            attachments = localAttachments
            transport = localTransport
            service = localService
            XCTAssertTrue(service.load())
        }

        func packet(kind: TransportPayloadKind = .message, body: String?, deliveredMessageID: UUID? = nil) throws -> OutboundTransportPacket {
            let crypto = CryptoService()
            let now = Date()
            let payload = TransportMessagePayload(version: 3, kind: kind, messageID: UUID(), conversationID: UUID(),
                                                  senderID: bob.id, recipientID: alice.id, body: body, createdAt: now, deliveredMessageID: deliveredMessageID)
            let id = UUID()
            let template = OutboundTransportPacket(id: id, senderID: bob.id, recipientID: alice.id, sealedPayloadBase64: "pending",
                                                   signatureBase64: "pending", createdAt: now, expiresAt: now.addingTimeInterval(3_600))
            let key = try crypto.derivePairwiseKey(privateKey: bob.keyAgreementPrivateKey, peerPublicKey: alice.keyAgreementPrivateKey.publicKey,
                                                 context: Data("PrivateChat/pairwise-message/v3/\([alice.id, bob.id].sorted().joined(separator: ":"))".utf8))
            let ciphertext = try crypto.encrypt(DateCoding.makeEncoder().encode(payload), key: key, aad: template.payloadAAD)
            let unsigned = OutboundTransportPacket(id: id, senderID: bob.id, recipientID: alice.id, sealedPayloadBase64: ciphertext.base64EncodedString(),
                                                   signatureBase64: "pending", createdAt: now, expiresAt: template.expiresAt)
            let signature = try crypto.sign(unsigned.authenticatedData, privateKey: bob.signingPrivateKey)
            return OutboundTransportPacket(id: id, senderID: bob.id, recipientID: alice.id, sealedPayloadBase64: unsigned.sealedPayloadBase64,
                                           signatureBase64: signature.base64EncodedString(), createdAt: now, expiresAt: template.expiresAt)
        }
    }
}

@MainActor
private final class SessionMessageStore: MessageStoring {
    var persisted: [StoredConversation]
    var failSaves = false
    init(seed: [StoredConversation]) { persisted = seed }
    func load() throws -> [StoredConversation] { persisted }
    func save(_ conversations: [StoredConversation]) throws {
        if failSaves { throw PrivateChatError.persistenceFailed("Synthetic disk failure") }
        persisted = conversations
    }
}

@MainActor
private final class SessionPeerStore: PeerTrustStoring {
    var persisted: [TrustedPeer]
    var failSaves = false
    init(seed: [TrustedPeer]) { persisted = seed }
    func loadPeers() throws -> [TrustedPeer] { persisted }
    func savePeers(_ peers: [TrustedPeer]) throws {
        if failSaves { throw PrivateChatError.persistenceFailed("Synthetic keychain failure") }
        persisted = peers
    }
}

@MainActor
private final class SessionAttachmentStore: AttachmentStoring {
    var data: [UUID: Data] = [:]
    var deletedIDs: [UUID] = []
    func saveAttachment(id: UUID, data: Data) throws { self.data[id] = data }
    func loadAttachment(id: UUID) throws -> Data { try XCTUnwrap(data[id]) }
    func deleteAttachment(id: UUID) throws { deletedIDs.append(id); data.removeValue(forKey: id) }
    func storeIncomingChunk(attachmentID: UUID, index: Int, totalChunks: Int, data: Data,
                            expectedByteCount: Int, expectedSHA256: String, transferContext: String) throws -> Bool {
        throw PrivateChatError.unsupportedAttachment
    }
}

@MainActor
private final class SessionTransport: TransportCoordinating {
    var inbox: [OutboundTransportPacket] = []
    var sentPackets: [OutboundTransportPacket] = []
    var deletedIDs: [UUID] = []
    var fetchCount = 0
    var healthCount = 0
    var statsCount = 0
    var enrollmentCount = 0
    var onFetch: (() -> Void)?
    var onSend: (() -> Void)?
    var onEnroll: (() -> Void)?
    var sendFailure: Error?
    func send(_ packet: OutboundTransportPacket, mode: TransportMode, relayConfiguration: RelayConfiguration) async throws {
        sentPackets.append(packet); await Task.yield(); onSend?()
        if let sendFailure { throw sendFailure }
    }
    func fetchRelayInbox(recipientID: String, relayConfiguration: RelayConfiguration) async throws -> [OutboundTransportPacket] {
        fetchCount += 1; await Task.yield(); onFetch?(); return inbox
    }
    func deleteRelayPacket(packetID: UUID, relayConfiguration: RelayConfiguration) async throws -> Bool { deletedIDs.append(packetID); return true }
    func checkRelayHealth(relayConfiguration: RelayConfiguration) async throws -> RelayHealthStatus {
        healthCount += 1
        return RelayHealthStatus(status: "ok", store: nil, authRequired: nil, adminAuthRequired: nil, productionMode: nil,
                                 httpsRequired: nil, clientPurgeEnabled: nil, maxPacketBytes: nil, maxTTLSeconds: nil,
                                 maxClockSkewSeconds: nil, maxTotalPackets: nil, maxPacketsPerRecipient: nil)
    }
    func fetchRelayStats(relayConfiguration: RelayConfiguration) async throws -> RelayStatsResponse {
        statsCount += 1
        return RelayStatsResponse(storedPackets: 0, activeRecipients: 0, acknowledgedPacketTombstones: 0,
                                  v1EnvelopeRequests: nil, v2EnvelopeRequests: nil, firstV2RequestAt: nil, lastV2RequestAt: nil)
    }
    func purgeRelayInbox(recipientID: String, relayConfiguration: RelayConfiguration) async throws -> RelayPurgeResponse {
        RelayPurgeResponse(deletedCount: 0, recipientID: recipientID)
    }
    func enrollLocalPeer(_ identity: LocalIdentity, relayConfiguration: RelayConfiguration) async throws -> RelayEnrollmentResponse {
        enrollmentCount += 1; await Task.yield(); onEnroll?()
        return RelayEnrollmentResponse(peerID: identity.id, registeredAt: 0, registrySize: 1)
    }
}
