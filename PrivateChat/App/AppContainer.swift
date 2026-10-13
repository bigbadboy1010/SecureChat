import Combine
import CryptoKit
import Foundation

@MainActor
final class AppContainer: ObservableObject {
    @Published var isUnlocked: Bool
    @Published var startupErrorMessage: String?
    @Published private(set) var isUnlocking = false
    @Published private(set) var isPrivacyCoverVisible = false

    let conversationService: ConversationService
    private let biometricGate: BiometricGating
    private let hasCriticalStartupFailure: Bool
    private var unlockRequestID: UUID?
    private var isInBackground = false
    private var enrollmentTask: Task<Void, Never>?
    private var criticalFailureSubscription: AnyCancellable?

    var canUnlock: Bool {
        hasCriticalStartupFailure == false
    }

    init(
        conversationService: ConversationService,
        biometricGate: BiometricGating,
        startupErrorMessage: String?,
        hasCriticalStartupFailure: Bool = false
    ) {
        self.conversationService = conversationService
        self.biometricGate = biometricGate
        self.startupErrorMessage = startupErrorMessage
        self.hasCriticalStartupFailure = hasCriticalStartupFailure
        self.isUnlocked = false
        conversationService.endUserSession()
        criticalFailureSubscription = conversationService.$criticalSessionFailure
            .compactMap { $0 }
            .sink { [weak self] failure in
                self?.lock()
                self?.startupErrorMessage = failure
            }
    }

    static func bootstrap() -> AppContainer {
        PrivateRoomPreviewFiles.cleanupOwnedFiles()
        let keychain = KeychainStore()
        let crypto = CryptoService()
        let identityManager = IdentityManager(keychain: keychain, crypto: crypto)
        let peerTrustStore = PeerTrustStore(keychain: keychain)
        let settingsStore = SecuritySettingsStore(keychain: keychain)
        let relayPacketLedgerStore = RelayPacketLedgerStore(keychain: keychain)
        // Production relay requests must be bound to the same long-term
        // identity that is stored in Keychain. Passing IdentityManager and
        // CryptoService here enables peer enrollment and X-Securechat-*
        // request signatures for SEND, inbox GET, ACK and other relay calls.
        let transportCoordinator = TransportCoordinator(
            signingContext: identityManager,
            crypto: crypto
        )
        let biometricGate = BiometricGate()

        do {
            let identity = try identityManager.loadOrCreateLocalIdentity(displayName: UIDeviceNameProvider.defaultDisplayName)
            let messageStore = try EncryptedMessageStore(keychain: keychain, crypto: crypto)
            let draftStore = try EncryptedDraftStore(keychain: keychain, crypto: crypto)
            let attachmentStore = try EncryptedAttachmentStore(keychain: keychain, crypto: crypto)
            let service = ConversationService(
                localIdentity: identity,
                messageStore: messageStore,
                draftStore: draftStore,
                peerTrustStore: peerTrustStore,
                settingsStore: settingsStore,
                relayPacketLedgerStore: relayPacketLedgerStore,
                identityManager: identityManager,
                crypto: crypto,
                transportCoordinator: transportCoordinator,
                attachmentStore: attachmentStore
            )
            guard service.load() else {
                throw PrivateChatError.persistenceFailed(
                    service.lastErrorMessage ?? "Sicherheitszustand konnte nicht geladen werden"
                )
            }
            let container = AppContainer(conversationService: service, biometricGate: biometricGate, startupErrorMessage: nil)
            return container
        } catch {
            let fallbackIdentity = LocalIdentity(
                id: "fallback",
                displayName: "PrivateChat",
                keyAgreementPrivateKey: .init(),
                signingPrivateKey: .init()
            )
            let service = ConversationService(
                localIdentity: fallbackIdentity,
                messageStore: InMemoryMessageStore(),
                draftStore: InMemoryDraftStore(),
                peerTrustStore: peerTrustStore,
                settingsStore: settingsStore,
                relayPacketLedgerStore: InMemoryRelayPacketLedgerStore(),
                identityManager: identityManager,
                crypto: crypto,
                transportCoordinator: transportCoordinator
            )
            service.load()
            return AppContainer(
                conversationService: service,
                biometricGate: biometricGate,
                startupErrorMessage: "Sicherheitskritischer Startfehler: \(error.localizedDescription)",
                hasCriticalStartupFailure: true
            )
        }
    }

    func unlock() async {
        guard hasCriticalStartupFailure == false, isUnlocking == false, isInBackground == false, !Task.isCancelled else {
            return
        }

        let requestID = UUID()
        unlockRequestID = requestID
        isUnlocking = true
        defer {
            if unlockRequestID == requestID {
                unlockRequestID = nil
                isUnlocking = false
            }
        }

        if conversationService.securityState.requireBiometricUnlock == false {
            guard conversationService.beginUserSession() else {
                startupErrorMessage = conversationService.criticalSessionFailure
                return
            }
            isUnlocked = true
            enrollAfterUnlock()
            return
        }

        do {
            try await biometricGate.unlock(reason: "PrivateRoom entsperren")
            guard unlockRequestID == requestID, isInBackground == false, Task.isCancelled == false else { return }
            guard conversationService.beginUserSession() else {
                startupErrorMessage = conversationService.criticalSessionFailure
                return
            }
            isUnlocked = true
            startupErrorMessage = nil
            enrollAfterUnlock()
        } catch {
            if unlockRequestID == requestID, isInBackground == false {
                startupErrorMessage = error.localizedDescription
            }
        }
    }

    func lock() {
        unlockRequestID = nil
        isUnlocking = false
        isUnlocked = false
        biometricGate.cancel()
        conversationService.endUserSession()
        enrollmentTask?.cancel()
        enrollmentTask = nil
        PrivateRoomPreviewFiles.cleanupOwnedFiles()
    }

    func becameInactive() {
        isPrivacyCoverVisible = true
        // System authentication briefly makes the scene inactive. It may
        // complete there, but backgrounding still cancels its request.
        if !isUnlocking { lock() }
    }

    func enteredBackground() {
        isInBackground = true
        isPrivacyCoverVisible = true
        lock()
    }

    func becameActive() {
        isInBackground = false
        isPrivacyCoverVisible = false
    }

    private func enrollAfterUnlock() {
        enrollmentTask?.cancel()
        enrollmentTask = Task { [weak self] in
            guard let self, self.isUnlocked, !Task.isCancelled else { return }
            await self.conversationService.enrollLocalPeerIfNeeded()
        }
    }
}
