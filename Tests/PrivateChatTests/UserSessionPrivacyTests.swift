import CryptoKit
import XCTest
@testable import PrivateChat

@MainActor
final class UserSessionPrivacyTests: XCTestCase {
    func testUnlockReceivesMessageWithoutCreatingOrReloadingChatView() async throws {
        let fixture = try Fixture()
        fixture.transport.inbox = [try fixture.packet(body: "automatic incoming")]
        var state = fixture.service.securityState
        state.requireBiometricUnlock = false
        XCTAssertTrue(fixture.service.updateSecurityState(state))
        let container = AppContainer(conversationService: fixture.service,
                                     biometricGate: UnexpectedAutoSyncBiometricGate(), startupErrorMessage: nil)
        defer { container.lock() }
        await container.unlock()
        let deadline = Date().addingTimeInterval(2)
        while (fixture.service.conversations.first?.messages.first?.body != "automatic incoming" || fixture.service.isRelaySyncRunning), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(fixture.service.conversations.first?.messages.first?.body, "automatic incoming")
        XCTAssertEqual(fixture.transport.deletedIDs.count, 1)
        XCTAssertTrue(fixture.service.isRelayAutoPollingActive)
    }

    func testOpeningChatWakesIdleInboxAndLaterMessagesArriveWithoutManualSync() async throws {
        let fixture = try Fixture()
        let conversationID = try XCTUnwrap(fixture.service.createConversation(title: "Bob", peerID: fixture.bob.id))
        fixture.service.startRelayAutoSyncLoop()
        defer { fixture.service.endUserSession() }
        try await waitUntil { fixture.transport.fetchCount == 1 && !fixture.service.isRelaySyncRunning }
        // Let the first automatic cycle install its idle delay.
        try await Task.sleep(for: .milliseconds(50))
        fixture.transport.inbox = [try fixture.packet(body: "arrived while idle")]
        let token = try XCTUnwrap(fixture.service.beginObservingChat(conversationID: conversationID))
        try await waitUntil { fixture.service.conversations.first?.messages.count == 1 }
        fixture.transport.inbox = [try fixture.packet(body: "arrived in open chat")]
        try await waitUntil(timeout: 7) { fixture.service.conversations.first?.messages.count == 2 && !fixture.service.isRelaySyncRunning }
        XCTAssertEqual(fixture.service.conversations.first?.messages.last?.body, "arrived in open chat")
        XCTAssertEqual(fixture.transport.deletedIDs.count, 2)
        fixture.service.endObservingChat(token)
        XCTAssertEqual(fixture.service.foregroundInboxIntervalSeconds, 15)
    }

    func testChatObserversDoNotMultiplyLoopsAndLockClearsFastCadence() async throws {
        let fixture = try Fixture()
        let id = try XCTUnwrap(fixture.service.createConversation(title: "Bob", peerID: fixture.bob.id))
        let first = try XCTUnwrap(fixture.service.beginObservingChat(conversationID: id))
        let second = try XCTUnwrap(fixture.service.beginObservingChat(conversationID: id))
        fixture.service.startRelayAutoSyncLoop()
        fixture.service.startRelayAutoSyncLoop()
        try await waitUntil { fixture.transport.fetchCount == 1 }
        fixture.service.endObservingChat(first)
        XCTAssertEqual(fixture.service.foregroundInboxIntervalSeconds, 5)
        fixture.service.endUserSession()
        let fetchesAtLock = fixture.transport.fetchCount
        XCTAssertEqual(fixture.service.foregroundInboxIntervalSeconds, 15)
        XCTAssertFalse(fixture.service.isRelayAutoPollingActive)
        XCTAssertNil(fixture.service.beginObservingChat(conversationID: id))
        fixture.service.endObservingChat(second)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(fixture.transport.fetchCount, fetchesAtLock)
    }

    func testOpeningChatRespectsAutomaticServerBackoff() async throws {
        let fixture = try Fixture()
        let id = try XCTUnwrap(fixture.service.createConversation(title: "Bob", peerID: fixture.bob.id))
        fixture.transport.fetchFailure = PrivateChatError.relayHTTPError(statusCode: 429, message: nil)
        fixture.service.startRelayAutoSyncLoop()
        defer { fixture.service.endUserSession() }
        try await waitUntil { fixture.service.relayConnectivityStatus.isPaused }
        try await Task.sleep(for: .milliseconds(50))
        _ = fixture.service.beginObservingChat(conversationID: id)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(fixture.transport.fetchCount, 1)
        XCTAssertTrue(fixture.service.relayConnectivityStatus.isPaused)
    }

    func testPaginationReachesValidMessageBehindUnprocessablePageWithoutDiscardingJunk() async throws {
        let fixture = try Fixture()
        let valid = try fixture.packet(body: "valid trusted message behind first page")
        let junk = (0..<50).map { index in
            OutboundTransportPacket(id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!,
                senderID: String(repeating: "f", count: 64), recipientID: fixture.alice.id,
                sealedPayloadBase64: valid.sealedPayloadBase64, signatureBase64: valid.signatureBase64,
                createdAt: valid.createdAt, expiresAt: valid.expiresAt)
        }
        fixture.transport.respectInboxLimit = true
        fixture.transport.inbox = junk + [valid]
        await fixture.service.syncRelayInbox()
        XCTAssertTrue(fixture.service.conversations.isEmpty)
        XCTAssertEqual(fixture.service.lastRelaySyncSummary?.rejectedCount, 40)
        await fixture.service.syncRelayInbox()
        XCTAssertEqual(fixture.service.conversations.first?.messages.first?.body,
                       "valid trusted message behind first page")
        XCTAssertEqual(fixture.transport.deletedIDs, [valid.id], "Rejected packets must never be ACKed to hide the problem")
        XCTAssertNotNil(fixture.transport.requestedCursors.last!)
    }

    func testOnlyVerifiedContactsArePublishedAndBlockReplacesRelayGrant() async throws {
        let fixture = try Fixture()
        await fixture.service.syncRelayInbox()
        XCTAssertEqual(fixture.transport.consents.last?.senderIDs, [fixture.bob.id])
        fixture.service.blockPeer(id: fixture.bob.id)
        try await waitUntil { fixture.transport.consents.last?.senderIDs == [] }
        XCTAssertEqual(fixture.transport.consents.last?.recipientID, fixture.alice.id)
    }

    func testGrantFailureStopsFetchAndSendButPreservesDurableOutbox() async throws {
        let fixture = try Fixture()
        fixture.transport.consentFailure = PrivateChatError.relayHTTPError(statusCode: 503, message: nil)
        await fixture.service.syncRelayInbox()
        XCTAssertEqual(fixture.transport.fetchCount, 0)
        fixture.service.resetRelayConnectivityBackoff()
        let chat = try XCTUnwrap(fixture.service.createConversation(title: "Bob", peerID: fixture.bob.id))
        let accepted = await fixture.service.sendMessage(conversationID: chat, body: "retained offline")
        XCTAssertTrue(accepted)
        XCTAssertEqual(fixture.transport.sentPackets.count, 0)
        XCTAssertEqual(fixture.messages.persisted.first?.messages.first?.body, "retained offline")
    }

    func testConcurrentBlockCannotBeOverwrittenByInFlightOlderGrant() async throws {
        let fixture = try Fixture()
        fixture.transport.suspendFirstConsent = true
        let syncing = Task { await fixture.service.syncRelayInbox() }
        try await waitUntil { fixture.transport.consentBarrier != nil }
        fixture.service.blockPeer(id: fixture.bob.id)
        fixture.transport.consentBarrier?.resume()
        fixture.transport.consentBarrier = nil
        await syncing.value
        try await waitUntil { fixture.transport.consents.last?.senderIDs == [] }
        XCTAssertEqual(fixture.transport.consents.count, 2)
        XCTAssertEqual(fixture.transport.consents.last?.senderIDs, [])
    }

    func testLockDuringGrantDoesNotFetchOrReopenSessionAfterNetworkReturns() async throws {
        let fixture = try Fixture()
        fixture.transport.suspendFirstConsent = true
        let syncing = Task { await fixture.service.syncRelayInbox() }
        try await waitUntil { fixture.transport.consentBarrier != nil }
        fixture.service.endUserSession()
        fixture.transport.consentBarrier?.resume()
        fixture.transport.consentBarrier = nil
        await syncing.value
        XCTAssertNil(fixture.service.currentUserSessionID)
        XCTAssertEqual(fixture.transport.fetchCount, 0)
    }

    func testLostSendResponseUsesSamePacketIdentifierOnRetry() async throws {
        let fixture = try Fixture()
        let chat = try XCTUnwrap(fixture.service.createConversation(title: "Bob", peerID: fixture.bob.id))
        fixture.transport.sendFailure = PrivateChatError.relayConnectionLost
        let accepted = await fixture.service.sendMessage(conversationID: chat, body: "same durable message")
        XCTAssertTrue(accepted)
        fixture.transport.sendFailure = nil
        fixture.service.resetRelayConnectivityBackoff()
        await fixture.service.retryPendingOutboundMessages()
        XCTAssertEqual(fixture.transport.sentPackets.count, 2)
        XCTAssertEqual(fixture.transport.sentPackets[0].id, fixture.transport.sentPackets[1].id)
        XCTAssertEqual(fixture.service.conversations.first?.messages.count, 1)
    }

    func testFailedReceiptKeepsPacketUntilRetryAndDoesNotDuplicateLocalMessage() async throws {
        let fixture = try Fixture()
        let incoming = try fixture.packet(body: "persist before receipt")
        fixture.transport.inbox = [incoming]
        fixture.transport.sendFailure = PrivateChatError.relayHTTPError(statusCode: 503, message: nil)
        await fixture.service.syncRelayInbox()
        XCTAssertEqual(fixture.service.conversations.first?.messages.count, 1)
        XCTAssertTrue(fixture.transport.deletedIDs.isEmpty)
        XCTAssertTrue(fixture.service.relayConnectivityStatus.isPaused)
        fixture.transport.sendFailure = nil
        fixture.service.resetRelayConnectivityBackoff()
        await fixture.service.syncRelayInbox()
        XCTAssertEqual(fixture.service.conversations.first?.messages.count, 1)
        XCTAssertEqual(fixture.transport.deletedIDs, [incoming.id])
        XCTAssertEqual(fixture.transport.sentPackets.count, 2)
        XCTAssertEqual(fixture.transport.sentPackets[0].id, fixture.transport.sentPackets[1].id)
    }

    func testACKRateLimitStopsBatchAndBackoffWithoutLosingLaterMessages() async throws {
        let fixture = try Fixture()
        fixture.transport.inbox = [try fixture.packet(body: "first"), try fixture.packet(body: "second")]
        fixture.transport.deleteFailure = PrivateChatError.relayHTTPError(statusCode: 429, message: nil)
        await fixture.service.syncRelayInbox()
        XCTAssertEqual(fixture.service.conversations.first?.messages.count, 1)
        XCTAssertTrue(fixture.service.relayConnectivityStatus.isPaused)
        let requests = fixture.transport.fetchCount
        await fixture.service.syncRelayInbox()
        XCTAssertEqual(fixture.transport.fetchCount, requests)
        fixture.transport.deleteFailure = nil
        fixture.service.resetRelayConnectivityBackoff()
        await fixture.service.syncRelayInbox()
        XCTAssertEqual(fixture.service.conversations.first?.messages.count, 2)
    }

    func testExpiredOutgoingContentIsRetainedWithoutSilentNewDeliveryWindow() async throws {
        let fixture = try Fixture(oldMessage: true, outgoingMessage: true)
        let chat = try XCTUnwrap(fixture.service.conversations.first)
        await fixture.service.retryMessage(messageID: chat.messages[0].id, conversationID: chat.id)
        XCTAssertTrue(fixture.transport.sentPackets.isEmpty)
        XCTAssertEqual(fixture.service.conversations.first?.messages.count, 1)
        XCTAssertTrue(fixture.service.lastErrorMessage?.contains("abgelaufen") == true)
    }

    func testPushConfigurationRequiresUnlockedSessionAndDoesNotSendChatContent() async throws {
        let fixture = try Fixture()
        let routingToken = String(repeating: "a", count: 64)
        let configured = await fixture.service.configureNeutralPush(enabled: true, token: routingToken)
        XCTAssertTrue(configured)
        XCTAssertEqual(fixture.transport.pushUpdates.count, 1)
        XCTAssertEqual(fixture.transport.pushUpdates.first?.token, routingToken)
        fixture.service.endUserSession()
        let locked = await fixture.service.configureNeutralPush(enabled: false, token: nil)
        XCTAssertFalse(locked)
        XCTAssertEqual(fixture.transport.pushUpdates.count, 1)
    }

    func testLockDuringPrekeyClaimCannotSendLateCiphertextAndRetryKeepsClaimID() async throws {
        let fixture = try Fixture()
        let chat = try XCTUnwrap(fixture.service.createConversation(title: "Bob", peerID: fixture.bob.id))
        fixture.transport.suspendFirstClaim = true
        let sending = Task { await fixture.service.sendMessage(conversationID: chat, body: "kept through key request") }
        try await waitUntil { fixture.transport.claimBarrier != nil }
        fixture.service.endUserSession()
        XCTAssertTrue(fixture.service.beginUserSession())
        fixture.transport.claimBarrier?.resume(); fixture.transport.claimBarrier = nil
        _ = await sending.value
        XCTAssertTrue(fixture.transport.sentPackets.isEmpty)
        await fixture.service.retryPendingOutboundMessages()
        XCTAssertEqual(fixture.transport.sentPackets.count, 1)
        XCTAssertEqual(fixture.transport.sentPackets.first?.protocolVersion, 4)
        XCTAssertEqual(fixture.transport.claimIDs.count, 2)
        XCTAssertEqual(fixture.transport.claimIDs.first, fixture.transport.claimIDs.last)
    }

    func testNewClientRejectsSignedHistoricalProtocolWithoutAcknowledgingOrAppending() async throws {
        let fixture = try Fixture(), current = try fixture.packet(body: "must not downgrade")
        let unsigned = OutboundTransportPacket(protocolVersion: 2, id: current.id, senderID: current.senderID, recipientID: current.recipientID,
            sealedPayloadBase64: current.sealedPayloadBase64, signatureBase64: "pending", createdAt: current.createdAt, expiresAt: current.expiresAt)
        let old = OutboundTransportPacket(protocolVersion: 2, id: current.id, senderID: current.senderID, recipientID: current.recipientID,
            sealedPayloadBase64: current.sealedPayloadBase64, signatureBase64: try fixture.bob.signingPrivateKey.signature(for: unsigned.authenticatedData).base64EncodedString(), createdAt: current.createdAt, expiresAt: current.expiresAt)
        fixture.transport.inbox = [old]
        let before = fixture.aliceOlm.storage.data
        await fixture.service.syncRelayInbox()
        XCTAssertTrue(fixture.service.conversations.isEmpty)
        XCTAssertTrue(fixture.transport.deletedIDs.isEmpty)
        XCTAssertEqual(fixture.service.lastRelaySyncSummary?.rejectedCount, 1)
        XCTAssertEqual(before, fixture.aliceOlm.storage.data)
    }

    func testExplicitServerRetryAfterControlsServicePause() async throws {
        let fixture = try Fixture()
        fixture.transport.fetchFailure = PrivateChatError.relayBackoff(statusCode: 429, retryAfterSeconds: 120, message: "device_rate_limit")
        await fixture.service.syncRelayInbox()
        XCTAssertTrue(fixture.service.relayConnectivityStatus.isPaused)
        XCTAssertGreaterThanOrEqual(fixture.service.relayConnectivityStatus.remainingPauseSeconds, 119)
        XCTAssertLessThanOrEqual(fixture.service.relayConnectivityStatus.remainingPauseSeconds, 120)
    }

    private func waitUntil(timeout: TimeInterval = 2, _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(predicate(), "Automatic inbox update did not complete before deadline")
    }

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
        let aliceOlm: SyntheticOlmPeer
        let bobOlm: SyntheticOlmPeer
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
            let localAliceOlm = try SyntheticOlmPeer(localAlice)
            let localBobOlm = try SyntheticOlmPeer(localBob)
            let localAttachments = SessionAttachmentStore()
            let localTransport = SessionTransport()
            localTransport.requester = localAlice.id
            localTransport.prekeyProvider = localBobOlm
            localTransport.ownPrekeys = localAliceOlm.batch
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
                                          transportCoordinator: localTransport, attachmentStore: localAttachments, forwardSecretStore: localAliceOlm.storage)
            aliceOlm = localAliceOlm
            bobOlm = localBobOlm
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
            let now = Date()
            let payload = TransportMessagePayload(version: 3, kind: kind, messageID: UUID(), conversationID: UUID(),
                senderID: bob.id, recipientID: alice.id, body: body, createdAt: now, deliveredMessageID: deliveredMessageID)
            return try bobOlm.packet(to: aliceOlm, payload: payload)

        }
    }
}

@MainActor
private final class UnexpectedAutoSyncBiometricGate: BiometricGating {
    func unlock(reason: String) async throws { XCTFail("Biometrics are disabled in this synthetic fixture") }
    func cancel() {}
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
    var requester = ""
    var prekeyProvider: SyntheticOlmPeer?
    var ownPrekeys: OlmPrekeyBatch?
    func olmPrekeyStatus(relayConfiguration: RelayConfiguration) async throws -> OlmPrekeyStatus {
        OlmPrekeyStatus(identity: ownPrekeys?.identity, sequence: ownPrekeys?.sequence ?? 0, available: 50)
    }
    var suspendFirstClaim = false
    var claimIDs: [UUID] = []
    var claimBarrier: CheckedContinuation<Void, Never>?
    func publishOlmPrekeys(_ batch: OlmPrekeyBatch, relayConfiguration: RelayConfiguration) async throws {}
    func claimOlmPrekey(recipientID: String, claimID: UUID, relayConfiguration: RelayConfiguration) async throws -> OlmPrekeyClaim {
        claimIDs.append(claimID)
        if suspendFirstClaim && claimIDs.count == 1 { await withCheckedContinuation { claimBarrier = $0 } }
        return try XCTUnwrap(prekeyProvider).claim(requester: requester, claimID: claimID)
    }

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
    var fetchFailure: Error?
    var deleteFailure: Error?
    var pushUpdates: [(enabled: Bool, token: String?, environment: String)] = []
    func configureNeutralPush(enabled: Bool, token: String?, environment: String, relayConfiguration: RelayConfiguration) async throws {
        pushUpdates.append((enabled, token, environment))
    }
    var respectInboxLimit = false
    var consents: [RelayRecipientConsent] = []
    var consentFailure: Error?
    var suspendFirstConsent = false
    var consentBarrier: CheckedContinuation<Void, Never>?
    var requestedCursors: [String?] = []
    func fetchRelayInboxPage(recipientID: String, after: String?, relayConfiguration: RelayConfiguration) async throws -> RelayFetchResponse {
        requestedCursors.append(after)
        let result = try await fetchRelayInbox(recipientID: recipientID, relayConfiguration: relayConfiguration)
        guard respectInboxLimit else { return RelayFetchResponse(packets: result) }
        let available = inbox.filter { after == nil || $0.id.uuidString.lowercased() > after! }
            .sorted { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }
        let page = Array(available.prefix(min(40, relayConfiguration.inboxPollingLimit)))
        return RelayFetchResponse(packets: page, nextCursor: available.count > page.count ? page.last?.id.uuidString.lowercased() : nil)
    }
    func send(_ packet: OutboundTransportPacket, mode: TransportMode, relayConfiguration: RelayConfiguration) async throws {
        sentPackets.append(packet); await Task.yield(); onSend?()
        if let sendFailure { throw sendFailure }
    }
    func fetchRelayInbox(recipientID: String, relayConfiguration: RelayConfiguration) async throws -> [OutboundTransportPacket] {
        fetchCount += 1; await Task.yield(); onFetch?()
        if let fetchFailure { throw fetchFailure }
        return respectInboxLimit ? Array(inbox.prefix(relayConfiguration.inboxPollingLimit)) : inbox
    }
    func deleteRelayPacket(packetID: UUID, relayConfiguration: RelayConfiguration) async throws -> Bool { if let deleteFailure { throw deleteFailure }; deletedIDs.append(packetID); return true }
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
    func replaceRecipientConsent(_ consent: RelayRecipientConsent, relayConfiguration: RelayConfiguration) async throws {
        consents.append(consent)
        if suspendFirstConsent && consents.count == 1 {
            await withCheckedContinuation { consentBarrier = $0 }
        }
        if let consentFailure { throw consentFailure }
    }

    func enrollLocalPeer(_ identity: LocalIdentity, relayConfiguration: RelayConfiguration) async throws -> RelayEnrollmentResponse {
        enrollmentCount += 1; await Task.yield(); onEnroll?()
        return RelayEnrollmentResponse(peerID: identity.id, registeredAt: 0, registrySize: 1)
    }
}
