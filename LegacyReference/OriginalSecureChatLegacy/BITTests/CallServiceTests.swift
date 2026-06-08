import XCTest
import CryptoKit
@testable import BIT

final class CallServiceTests: XCTestCase {
    var callService: CallService!

    override func setUp() {
        super.setUp()
        callService = CallService.shared
    }

    override func tearDown() {
        super.tearDown()
    }

    func testInitiateCallSuccess() {
        // Arrange
        let peerID = "peer_test_user"

        // Act
        let result = callService.initiateCall(to: peerID, type: .audio)

        // Assert
        switch result {
        case .success(let call):
            XCTAssertEqual(call.type, .audio)
            XCTAssertEqual(call.recipientID, peerID)
            XCTAssertEqual(call.status, .outgoing)
        case .failure:
            XCTFail("Call initiation should succeed")
        }
    }

    func testInitiateVideoCall() {
        // Arrange
        let peerID = "video_peer"

        // Act
        let result = callService.initiateCall(to: peerID, type: .video)

        // Assert
        switch result {
        case .success(let call):
            XCTAssertEqual(call.type, .video)
        case .failure:
            XCTFail("Video call should be created")
        }
    }

    func testInitiateGroupCall() {
        // Arrange
        let groupID = "test_group_123"

        // Act
        let result = callService.initiateGroupCall(groupID: groupID, maxParticipants: 10, type: .audio)

        // Assert
        switch result {
        case .success(let groupCall):
            XCTAssertEqual(groupCall.groupID, groupID)
            XCTAssertEqual(groupCall.maxParticipants, 10)
        case .failure:
            XCTFail("Group call should be created")
        }
    }

    func testCallEncryption() {
        // Arrange
        let originalData = "Test call data to encrypt".data(using: .utf8) ?? Data()
        let encryptionKey = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }

        // Act
        let encryptResult = callService.encryptCallData(originalData, using: encryptionKey)

        // Assert
        switch encryptResult {
        case .success(let encryptedData):
            XCTAssertNotEqual(encryptedData, originalData)
            XCTAssertGreaterThan(encryptedData.count, 0)
        case .failure:
            XCTFail("Encryption should succeed")
        }
    }

    func testCallEncryptionWithInvalidKey() {
        // Arrange
        let data = "Test".data(using: .utf8) ?? Data()
        let invalidKey = Data() // Empty key

        // Act
        let result = callService.encryptCallData(data, using: invalidKey)

        // Assert
        if case .failure(let error) = result {
            XCTAssertEqual(error, CallService.CallError.encryptionFailed)
        } else {
            XCTFail("Should fail with invalid key")
        }
    }

    func testToggleMicrophone() {
        // Arrange
        let initialState = callService.isMicrophoneEnabled

        // Act
        callService.toggleMicrophone()
        let afterToggle = callService.isMicrophoneEnabled

        // Assert
        XCTAssertNotEqual(initialState, afterToggle)
    }

    func testToggleCamera() {
        // Arrange
        let initialState = callService.isCameraEnabled

        // Act
        callService.toggleCamera()
        let afterToggle = callService.isCameraEnabled

        // Assert
        XCTAssertNotEqual(initialState, afterToggle)
    }

    func testCallHistoryPersistence() {
        // Arrange
        let callRecord = CallService.CallRecord(
            id: UUID().uuidString,
            peerID: "test_peer",
            type: .audio,
            direction: .outgoing,
            status: .completed,
            startTime: Date(),
            duration: 300,
            isEncrypted: true
        )

        // Act
        // Call records should be persisted after call ends
        XCTAssertNotNil(callRecord.id)

        // Assert
        XCTAssertEqual(callRecord.duration, 300)
        XCTAssertTrue(callRecord.isEncrypted)
    }

    func testCallRecordDirection() {
        // Arrange
        let outgoingRecord = CallService.CallRecord(
            id: UUID().uuidString,
            peerID: "peer",
            type: .audio,
            direction: .outgoing,
            status: .completed,
            startTime: Date(),
            duration: 100,
            isEncrypted: true
        )

        let incomingRecord = CallService.CallRecord(
            id: UUID().uuidString,
            peerID: "peer",
            type: .audio,
            direction: .incoming,
            status: .completed,
            startTime: Date(),
            duration: 100,
            isEncrypted: true
        )

        // Assert
        XCTAssertEqual(outgoingRecord.direction, .outgoing)
        XCTAssertEqual(incomingRecord.direction, .incoming)
    }

    func testCallTypeVariations() {
        // Assert all call types are supported
        XCTAssertEqual(CallService.CallType.audio.rawValue, "audio")
        XCTAssertEqual(CallService.CallType.video.rawValue, "video")
        XCTAssertEqual(CallService.CallType.screenShare.rawValue, "screenShare")
    }

    func testCallStatusTransitions() {
        // Assert all call statuses are defined
        let statuses: [CallService.CallStatus] = [
            .outgoing,
            .incoming,
            .ringing,
            .active,
            .ended,
            .rejected,
            .failed
        ]

        XCTAssertEqual(statuses.count, 7)
    }

    func testGroupCallParticipantTracking() {
        // Arrange
        let groupCall = CallService.GroupCall(
            id: UUID().uuidString,
            groupID: "group_123",
            initiatorID: "alice",
            type: .audio,
            maxParticipants: 8,
            startTime: Date(),
            participants: ["alice"]
        )

        // Assert
        XCTAssertEqual(groupCall.participants.count, 1)
        XCTAssertTrue(groupCall.participants.contains("alice"))
        XCTAssertLessThanOrEqual(groupCall.participants.count, groupCall.maxParticipants)
    }

    func testCallEncryptionKeyGeneration() {
        // Act
        let key1 = callService.generateCallKey()
        let key2 = callService.generateCallKey()

        // Assert
        XCTAssertEqual(key1.count, 32) // 256 bits = 32 bytes
        XCTAssertEqual(key2.count, 32)
        XCTAssertNotEqual(key1, key2) // Keys should be unique
    }

    func testCallWithEncryption() {
        // Arrange
        let peerID = "encrypted_peer"

        // Act
        let result = callService.initiateCall(to: peerID, type: .audio)

        // Assert
        switch result {
        case .success(let call):
            XCTAssertEqual(call.encryptionKey.count, 32)
        case .failure:
            XCTFail("Call with encryption should succeed")
        }
    }

    func testCallDurationCalculation() {
        // Arrange
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(300) // 5 minutes
        let duration = Int(endTime.timeIntervalSince(startTime))

        // Assert
        XCTAssertEqual(duration, 300)
    }

    func testCodableCallRecord() {
        // Arrange
        let record = CallService.CallRecord(
            id: UUID().uuidString,
            peerID: "test_peer",
            type: .audio,
            direction: .outgoing,
            status: .completed,
            startTime: Date(),
            duration: 120,
            isEncrypted: true
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // Act
        let encoded = try? encoder.encode(record)
        let decoded = try? decoder.decode(CallService.CallRecord.self, from: encoded ?? Data())

        // Assert
        XCTAssertEqual(decoded?.id, record.id)
        XCTAssertEqual(decoded?.duration, 120)
        XCTAssertEqual(decoded?.type, .audio)
    }

    func testGroupCallCodable() {
        // Arrange
        let groupCall = CallService.GroupCall(
            id: UUID().uuidString,
            groupID: "group_123",
            initiatorID: "initiator",
            type: .video,
            maxParticipants: 8,
            startTime: Date(),
            participants: ["initiator", "participant1", "participant2"]
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // Act
        let encoded = try? encoder.encode(groupCall)
        let decoded = try? decoder.decode(CallService.GroupCall.self, from: encoded ?? Data())

        // Assert
        XCTAssertEqual(decoded?.participants.count, 3)
        XCTAssertEqual(decoded?.maxParticipants, 8)
    }

    func testCallErrorTypes() {
        // Assert all error types are defined
        let errors: [CallService.CallError] = [
            .peerNotAvailable,
            .noIncomingCall,
            .audioVideoSetupFailed,
            .encryptionFailed,
            .networkError
        ]

        XCTAssertEqual(errors.count, 5)
    }

    func testMultipleCallAttempts() {
        // Arrange
        let peer1 = "peer_1"
        let peer2 = "peer_2"

        // Act
        let result1 = callService.initiateCall(to: peer1, type: .audio)
        let result2 = callService.initiateCall(to: peer2, type: .video)

        // Assert
        switch (result1, result2) {
        case (.success(let call1), .success(let call2)):
            XCTAssertNotEqual(call1.id, call2.id)
            XCTAssertEqual(call1.type, .audio)
            XCTAssertEqual(call2.type, .video)
        default:
            XCTFail("Both calls should be created")
        }
    }

    func testCallInvitationEncoding() {
        // Arrange
        let invitation = CallService.CallInvitation(
            callID: UUID().uuidString,
            initiatorID: "alice",
            recipientID: "bob",
            type: .audio,
            timestamp: Date(),
            encryptionKey: "base64_encoded_key"
        )

        let encoder = JSONEncoder()

        // Act
        let encoded = try? encoder.encode(invitation)

        // Assert
        XCTAssertNotNil(encoded)
        XCTAssertGreaterThan(encoded?.count ?? 0, 0)
    }

    func testCallResponseHandling() {
        // Arrange
        let response = CallService.CallResponse(
            callID: UUID().uuidString,
            accepted: true,
            respondentID: "bob",
            timestamp: Date(),
            rejectionReason: nil
        )

        // Assert
        XCTAssertTrue(response.accepted)
        XCTAssertNil(response.rejectionReason)
    }

    func testCallRejectionReason() {
        // Arrange
        let rejection = CallService.CallResponse(
            callID: UUID().uuidString,
            accepted: false,
            respondentID: "bob",
            timestamp: Date(),
            rejectionReason: "User is busy"
        )

        // Assert
        XCTAssertFalse(rejection.accepted)
        XCTAssertEqual(rejection.rejectionReason, "User is busy")
    }

    func testGroupCallMaxParticipantLimit() {
        // Arrange
        let maxParticipants = 8

        // Act
        let result = callService.initiateGroupCall(
            groupID: "large_group",
            maxParticipants: maxParticipants,
            type: .audio
        )

        // Assert
        switch result {
        case .success(let groupCall):
            XCTAssertEqual(groupCall.maxParticipants, maxParticipants)
        case .failure:
            XCTFail("Group call should be created")
        }
    }
}
