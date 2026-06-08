import Foundation
import AVFoundation

final class CallService: NSObject, ObservableObject {
    static let shared = CallService()

    @Published var activeCall: Call?
    @Published var callHistory: [CallRecord] = []
    @Published var isMicrophoneEnabled: Bool = true
    @Published var isCameraEnabled: Bool = false

    private let persistence = MessagePersistenceService.shared
    private let encryption = EncryptionService.shared
    private let multiPeer = MultipeerConnectivityService.shared
    private let queue = DispatchQueue(label: "com.secureChat.call", attributes: .concurrent)

    private var audioSession: AVAudioSession?
    private var callStartTime: Date?

    private override init() {
        super.init()
        setupAudioSession()
        loadCallHistory()
    }

    // MARK: - Call Lifecycle
    func initiateCall(
        to peerID: String,
        type: CallType = .audio
    ) -> Result<Call, CallError> {
        // Validate peer is online
        guard multiPeer.isConnected(to: peerID) else {
            return .failure(.peerNotAvailable)
        }

        let call = Call(
            id: UUID().uuidString,
            initiatorID: multiPeer.myPeerID,
            recipientID: peerID,
            type: type,
            startTime: Date(),
            encryptionKey: generateCallKey(),
            status: .outgoing
        )

        DispatchQueue.main.async {
            self.activeCall = call
        }

        callStartTime = Date()

        // Send call invitation
        sendCallInvitation(call)

        print("📞 Call initiated to \(peerID)")
        return .success(call)
    }

    func acceptCall(_ call: Call) -> Result<Void, CallError> {
        guard let activeCall = activeCall, activeCall.id == call.id else {
            return .failure(.noIncomingCall)
        }

        // Start audio/video
        do {
            if activeCall.type == .audio {
                try startAudio()
            } else {
                try startVideo()
            }
        } catch {
            return .failure(.audioVideoSetupFailed)
        }

        DispatchQueue.main.async {
            var updatedCall = call
            updatedCall.status = .active
            updatedCall.answerTime = Date()
            self.activeCall = updatedCall
        }

        // Notify caller
        sendCallAccepted(call)

        print("✅ Call accepted")
        return .success(())
    }

    func rejectCall(_ call: Call) {
        DispatchQueue.main.async {
            self.activeCall = nil
        }

        sendCallRejected(call, reason: "User declined")
        recordCallHistory(call, status: .rejected, duration: 0)

        print("❌ Call rejected")
    }

    func endCall() {
        guard let call = activeCall else { return }

        // Stop audio/video
        stopAudio()
        stopVideo()

        let duration = Date().timeIntervalSince(callStartTime ?? Date())

        recordCallHistory(call, status: .completed, duration: Int(duration))

        DispatchQueue.main.async {
            self.activeCall = nil
        }

        // Notify peer
        sendCallEnded(call)

        print("📞 Call ended - Duration: \(Int(duration))s")
    }

    // MARK: - Audio/Video Management
    private func setupAudioSession() {
        audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession?.setCategory(.playAndRecord, mode: .voiceChat, options: [.duckOthers])
            try audioSession?.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("❌ Audio session setup failed: \(error)")
        }
    }

    private func startAudio() throws {
        guard let audioSession = audioSession else {
            throw CallError.audioVideoSetupFailed
        }

        try audioSession.setActive(true)
        print("🎤 Audio started")
    }

    private func startVideo() throws {
        // This would initialize camera capture
        // Requires AVCaptureSession setup
        print("📹 Video started")
    }

    private func stopAudio() {
        try? audioSession?.setActive(false)
        print("🔇 Audio stopped")
    }

    private func stopVideo() {
        print("📹 Video stopped")
    }

    func toggleMicrophone() {
        DispatchQueue.main.async {
            self.isMicrophoneEnabled.toggle()
            print(self.isMicrophoneEnabled ? "🎤 Microphone ON" : "🔇 Microphone OFF")
        }
    }

    func toggleCamera() {
        DispatchQueue.main.async {
            self.isCameraEnabled.toggle()
            print(self.isCameraEnabled ? "📹 Camera ON" : "📹 Camera OFF")
        }
    }

    // MARK: - Group Calls
    func initiateGroupCall(
        groupID: String,
        maxParticipants: Int = 8,
        type: CallType = .audio
    ) -> Result<GroupCall, CallError> {
        let call = GroupCall(
            id: UUID().uuidString,
            groupID: groupID,
            initiatorID: multiPeer.myPeerID,
            type: type,
            maxParticipants: maxParticipants,
            startTime: Date(),
            participants: [multiPeer.myPeerID]
        )

        // Broadcast call invitation to group
        broadcastGroupCallInvitation(call)

        print("👥 Group call initiated in \(groupID)")
        return .success(call)
    }

    // MARK: - Encryption for Calls
    private func generateCallKey() -> Data {
        return SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    func encryptCallData(_ data: Data, using key: Data) -> Result<Data, CallError> {
        guard let symmetricKey = try? SymmetricKey(data: key) else {
            return .failure(.encryptionFailed)
        }

        do {
            let sealedBox = try AES.GCM.seal(data, using: symmetricKey)
            var encryptedData = sealedBox.nonce.withUnsafeBytes { Data($0) }
            encryptedData.append(sealedBox.ciphertext)
            encryptedData.append(sealedBox.tag)
            return .success(encryptedData)
        } catch {
            return .failure(.encryptionFailed)
        }
    }

    // MARK: - Network Operations
    private func sendCallInvitation(_ call: Call) {
        let invitation = CallInvitation(
            callID: call.id,
            initiatorID: call.initiatorID,
            recipientID: call.recipientID,
            type: call.type,
            timestamp: Date(),
            encryptionKey: call.encryptionKey.base64EncodedString()
        )

        if let encoded = try? JSONEncoder().encode(invitation) {
            // Send via multiPeer connectivity
            multiPeer.send(encoded, to: call.recipientID)
        }
    }

    private func sendCallAccepted(_ call: Call) {
        let response = CallResponse(
            callID: call.id,
            accepted: true,
            respondentID: multiPeer.myPeerID,
            timestamp: Date()
        )

        if let encoded = try? JSONEncoder().encode(response) {
            multiPeer.send(encoded, to: call.initiatorID)
        }
    }

    private func sendCallRejected(_ call: Call, reason: String) {
        let response = CallResponse(
            callID: call.id,
            accepted: false,
            respondentID: multiPeer.myPeerID,
            timestamp: Date(),
            rejectionReason: reason
        )

        if let encoded = try? JSONEncoder().encode(response) {
            multiPeer.send(encoded, to: call.initiatorID)
        }
    }

    private func sendCallEnded(_ call: Call) {
        let endMessage = CallEndMessage(
            callID: call.id,
            senderID: multiPeer.myPeerID,
            timestamp: Date(),
            duration: Int(Date().timeIntervalSince(callStartTime ?? Date()))
        )

        if let encoded = try? JSONEncoder().encode(endMessage) {
            multiPeer.send(encoded, to: call.recipientID)
        }
    }

    private func broadcastGroupCallInvitation(_ call: GroupCall) {
        let invitation = GroupCallInvitation(
            callID: call.id,
            groupID: call.groupID,
            initiatorID: call.initiatorID,
            type: call.type,
            timestamp: Date(),
            maxParticipants: call.maxParticipants
        )

        if let encoded = try? JSONEncoder().encode(invitation) {
            // Broadcast to all group members
            // Implementation depends on group member list
        }
    }

    // MARK: - Call History
    private func recordCallHistory(
        _ call: Call,
        status: CallStatus,
        duration: Int
    ) {
        let record = CallRecord(
            id: call.id,
            peerID: call.recipientID,
            type: call.type,
            direction: call.initiatorID == multiPeer.myPeerID ? .outgoing : .incoming,
            status: status,
            startTime: call.startTime,
            duration: duration,
            isEncrypted: true
        )

        queue.async(flags: .barrier) {
            self.callHistory.append(record)
            self.saveCallHistory()
        }
    }

    private func saveCallHistory() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(callHistory) else { return }

        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let historyPath = paths[0].appendingPathComponent("call_history.json")

        try? data.write(to: historyPath)
    }

    private func loadCallHistory() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let historyPath = paths[0].appendingPathComponent("call_history.json")

        guard let data = try? Data(contentsOf: historyPath) else { return }

        let decoder = JSONDecoder()
        if let history = try? decoder.decode([CallRecord].self, from: data) {
            DispatchQueue.main.async {
                self.callHistory = history
            }
        }
    }

    // MARK: - Models
    struct Call: Codable, Identifiable {
        let id: String
        let initiatorID: String
        let recipientID: String
        let type: CallType
        let startTime: Date
        let encryptionKey: Data
        var status: CallStatus
        var answerTime: Date?

        enum CodingKeys: String, CodingKey {
            case id, initiatorID, recipientID, type, startTime, encryptionKey, status, answerTime
        }
    }

    struct GroupCall: Codable, Identifiable {
        let id: String
        let groupID: String
        let initiatorID: String
        let type: CallType
        let maxParticipants: Int
        let startTime: Date
        var participants: [String]
    }

    enum CallType: String, Codable {
        case audio
        case video
        case screenShare
    }

    enum CallStatus: String, Codable {
        case outgoing
        case incoming
        case ringing
        case active
        case ended
        case rejected
        case failed
    }

    struct CallRecord: Codable, Identifiable {
        let id: String
        let peerID: String
        let type: CallType
        let direction: Direction
        let status: CallStatus
        let startTime: Date
        let duration: Int // seconds
        let isEncrypted: Bool

        enum Direction: String, Codable {
            case incoming
            case outgoing
        }
    }

    enum CallError: Error {
        case peerNotAvailable
        case noIncomingCall
        case audioVideoSetupFailed
        case encryptionFailed
        case networkError
    }

    // MARK: - Internal Message Types
    private struct CallInvitation: Codable {
        let callID: String
        let initiatorID: String
        let recipientID: String
        let type: CallType
        let timestamp: Date
        let encryptionKey: String
    }

    private struct CallResponse: Codable {
        let callID: String
        let accepted: Bool
        let respondentID: String
        let timestamp: Date
        let rejectionReason: String?
    }

    private struct CallEndMessage: Codable {
        let callID: String
        let senderID: String
        let timestamp: Date
        let duration: Int
    }

    private struct GroupCallInvitation: Codable {
        let callID: String
        let groupID: String
        let initiatorID: String
        let type: CallType
        let timestamp: Date
        let maxParticipants: Int
    }
}
