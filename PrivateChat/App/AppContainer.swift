import Combine
import CryptoKit
import Foundation

@MainActor
final class AppContainer: ObservableObject {
    @Published var isUnlocked: Bool
    @Published var startupErrorMessage: String?

    let conversationService: ConversationService
    private let biometricGate: BiometricGating

    private init(conversationService: ConversationService, biometricGate: BiometricGating, startupErrorMessage: String?) {
        self.conversationService = conversationService
        self.biometricGate = biometricGate
        self.startupErrorMessage = startupErrorMessage
        self.isUnlocked = false
    }

    static func bootstrap() -> AppContainer {
        let keychain = KeychainStore()
        let crypto = CryptoService()
        let identityManager = IdentityManager(keychain: keychain, crypto: crypto)
        let peerTrustStore = PeerTrustStore(keychain: keychain)
        let settingsStore = SecuritySettingsStore(keychain: keychain)
        let relayPacketLedgerStore = RelayPacketLedgerStore(keychain: keychain)
        let transportCoordinator = TransportCoordinator()
        let biometricGate = BiometricGate()

        do {
            let identity = try identityManager.loadOrCreateLocalIdentity(displayName: UIDeviceNameProvider.defaultDisplayName)
            let messageStore = try EncryptedMessageStore(keychain: keychain, crypto: crypto)
            let service = ConversationService(
                localIdentity: identity,
                messageStore: messageStore,
                peerTrustStore: peerTrustStore,
                settingsStore: settingsStore,
                relayPacketLedgerStore: relayPacketLedgerStore,
                identityManager: identityManager,
                crypto: crypto,
                transportCoordinator: transportCoordinator
            )
            service.load()
            return AppContainer(conversationService: service, biometricGate: biometricGate, startupErrorMessage: nil)
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
                peerTrustStore: peerTrustStore,
                settingsStore: settingsStore,
                relayPacketLedgerStore: InMemoryRelayPacketLedgerStore(),
                identityManager: identityManager,
                crypto: crypto,
                transportCoordinator: transportCoordinator
            )
            service.load()
            return AppContainer(conversationService: service, biometricGate: biometricGate, startupErrorMessage: error.localizedDescription)
        }
    }

    func unlock() async {
        if conversationService.securityState.requireBiometricUnlock == false {
            isUnlocked = true
            return
        }

        do {
            try await biometricGate.unlock(reason: "PrivateChat entsperren")
            isUnlocked = true
            startupErrorMessage = nil
        } catch {
            startupErrorMessage = error.localizedDescription
        }
    }
}
