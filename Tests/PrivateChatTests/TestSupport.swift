import Foundation
import CryptoKit
@testable import PrivateChat

final class MockKeychainStore: KeychainStoring {
    private var values: [String: Data]

    init(values: [String: Data] = [:]) {
        self.values = values
    }

    func readData(account: String) throws -> Data? {
        values[account]
    }

    func writeData(_ data: Data, account: String) throws {
        values[account] = data
    }

    func deleteData(account: String) throws {
        values.removeValue(forKey: account)
    }
}

enum TestDirectoryFactory {
    static func make(_ name: String = UUID().uuidString) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrivateChatTests", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

// MARK: - ConversationService test mocks (Sprint 11A)

/// In-memory `MessageStoring` mock. Returns the
/// seeded conversations on `load()`, captures
/// `save(...)` calls so tests can assert on the
/// final state.
final class MockMessageStore: MessageStoring {
    private var stored: [StoredConversation]
    var savedCalls: [[StoredConversation]] = []

    init(seed: [StoredConversation] = []) {
        self.stored = seed
    }

    func load() throws -> [StoredConversation] { stored }
    func save(_ conversations: [StoredConversation]) throws {
        stored = conversations
        savedCalls.append(conversations)
    }
}

/// In-memory `DraftStoring` mock. Stores drafts in
/// a `Dictionary<UUID, String>`.
final class MockDraftStore: DraftStoring {
    private var drafts: [UUID: String] = [:]

    func loadDraft(conversationID: UUID) throws -> String? { drafts[conversationID] }
    func saveDraft(_ draft: String, conversationID: UUID) throws {
        drafts[conversationID] = draft
    }
    func deleteDraft(conversationID: UUID) throws {
        drafts.removeValue(forKey: conversationID)
    }
    func migrateLegacyDraftIfNeeded(
        conversationID: UUID,
        legacyValue: String?
    ) throws -> String? {
        drafts[conversationID] ?? legacyValue
    }
}

/// In-memory `PeerTrustStoring` mock.
final class MockPeerTrustStore: PeerTrustStoring {
    private var peers: [TrustedPeer]
    var saveCalls: [[TrustedPeer]] = []

    init(seed: [TrustedPeer] = []) {
        self.peers = seed
    }

    func loadPeers() throws -> [TrustedPeer] { peers }
    func savePeers(_ peers: [TrustedPeer]) throws {
        self.peers = peers
        saveCalls.append(peers)
    }
}

/// In-memory `SecuritySettingsStoring` mock with a
/// fixed default.
final class MockSecuritySettingsStore: SecuritySettingsStoring {
    private var state: AppSecurityState
    var saveCalls: [AppSecurityState] = []

    init(seed: AppSecurityState = .secureDefault) {
        self.state = seed
    }

    func load() throws -> AppSecurityState { state }
    func save(_ state: AppSecurityState) throws {
        self.state = state
        saveCalls.append(state)
    }
}

/// In-memory `RelayPacketLedgerStoring` mock.
final class MockRelayPacketLedgerStore: RelayPacketLedgerStoring {
    private var ledger: RelayPacketLedger
    var saveCalls: [RelayPacketLedger] = []

    init(seed: RelayPacketLedger = .empty) {
        self.ledger = seed
    }

    func load() throws -> RelayPacketLedger { ledger }
    func save(_ ledger: RelayPacketLedger) throws {
        self.ledger = ledger
        saveCalls.append(ledger)
    }
}

/// Crypto operations mock that delegates the v2
/// envelope path (Ratchet AEAD) to the
/// `DoubleRatchetSession` directly; the v1 path
/// (`encrypt` / `decrypt`) is implemented as a
/// minimal pass-through that returns the
/// plaintext unchanged so existing v1 tests
/// keep working.
///
/// Tests that need the full v1 envelope should
/// use a `CryptoService` instance directly (see
/// `CryptoServiceTests`).
final class StubCryptoService: CryptoServicing {
    func makeSymmetricKey() throws -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    func encrypt(_ plaintext: Data, key: SymmetricKey, aad: Data) throws -> Data {
        // Minimal AES.GCM seal; the v2 envelope
        // path does not use this method.
        try AES.GCM.seal(plaintext, using: key, authenticating: aad).combined ?? Data()
    }

    func decrypt(_ sealedCombinedData: Data, key: SymmetricKey, aad: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: sealedCombinedData)
        return try AES.GCM.open(box, using: key, authenticating: aad)
    }

    func derivePairwiseKey(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        peerPublicKey: Curve25519.KeyAgreement.PublicKey,
        context: Data
    ) throws -> SymmetricKey {
        try privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
            .hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: context,
                sharedInfo: Data(),
                outputByteCount: 32
            )
    }

    func peerID(publicKeyData: Data) -> String {
        // Same scheme the production code uses:
        // first 8 bytes hex-encoded.
        let prefix = publicKeyData.prefix(8)
        return prefix.map { String(format: "%02x", $0) }.joined()
    }

    func safetyNumber(peerID: String) -> String {
        // Static placeholder for tests; the
        // production code uses a 12-digit
        // fingerprint.
        String(peerID.prefix(12))
    }

    func sign(_ data: Data, privateKey: Curve25519.Signing.PrivateKey) throws -> Data {
        try privateKey.signature(for: data)
    }

    func verify(signature: Data, data: Data, publicKey: Curve25519.Signing.PublicKey) -> Bool {
        publicKey.isValidSignature(signature, for: data)
    }

    /// Sprint 27 (2026-06-24): the test stub
    /// delegates to the real implementation so
    /// enrollment flow tests exercise the same
    /// PEM-export the production app uses.
    func pemEncodedSigningPublicKey(_ publicKey: Curve25519.Signing.PublicKey) -> String {
        CryptoService().pemEncodedSigningPublicKey(publicKey)
    }
}

/// Identity manager mock that returns a fixed
/// local identity and lets tests pre-seed
/// trusted peers.
final class MockIdentityManager: IdentityManaging {
    let localIdentity: LocalIdentity
    private var peers: [String: TrustedPeer]

    init(localIdentity: LocalIdentity, seedPeers: [TrustedPeer] = []) {
        self.localIdentity = localIdentity
        self.peers = Dictionary(uniqueKeysWithValues: seedPeers.map { ($0.id, $0) })
    }

    func loadOrCreateLocalIdentity(displayName: String) throws -> LocalIdentity {
        // displayName is a `let` on LocalIdentity;
        // we ignore the requested value and
        // return the seeded identity verbatim.
        // Tests that need a different displayName
        // must seed it via the init.
        localIdentity
    }

    func updateDisplayName(_ displayName: String, identity: LocalIdentity) throws -> LocalIdentity {
        // Same constraint: displayName is a `let`
        // and cannot be mutated. Return the
        // identity unchanged so existing call
        // sites that call this method on a mock
        // still type-check.
        identity
    }

    func exportPairingPayload(identity: LocalIdentity) throws -> String {
        // Not used by the v2 path; tests that
        // exercise pairing import use the
        // production `IdentityManager`.
        ""
    }

    func importPairingPayload(_ encodedPayload: String) throws -> TrustedPeer {
        // Not used by the v2 path; tests that
        // exercise pairing import use the
        // production `IdentityManager`.
        throw PrivateChatError.invalidPairingPayload
    }
}

/// Transport coordinator mock that captures sent
/// packets and returns a pre-seeded relay inbox
/// on `fetchRelayInbox(...)`. Used by Sprint 11A
/// to drive `syncRelayInbox(...)` with a
/// controlled v2 packet list.
final class MockTransportCoordinator: TransportCoordinating {
    private(set) var sentPackets: [OutboundTransportPacket] = []
    private let inbox: [OutboundTransportPacket]
    private let inboxDelete: Bool
    private let inboxPurge: RelayPurgeResponse
    private let health: RelayHealthStatus
    private let stats: RelayStatsResponse

    init(
        inbox: [OutboundTransportPacket] = [],
        inboxDelete: Bool = true,
        inboxPurge: RelayPurgeResponse = RelayPurgeResponse(deletedCount: 0, recipientID: "test"),
        health: RelayHealthStatus = .init(
            status: "ok",
            store: nil,
            authRequired: nil,
            adminAuthRequired: nil,
            productionMode: nil,
            httpsRequired: nil,
            clientPurgeEnabled: nil,
            maxPacketBytes: nil,
            maxTTLSeconds: nil,
            maxClockSkewSeconds: nil,
            maxTotalPackets: nil,
            maxPacketsPerRecipient: nil
        ),
        stats: RelayStatsResponse = RelayStatsResponse(
            storedPackets: 0,
            activeRecipients: 0,
            acknowledgedPacketTombstones: 0,
            v1EnvelopeRequests: 0,
            v2EnvelopeRequests: 0,
            firstV2RequestAt: nil,
            lastV2RequestAt: nil
        )
    ) {
        self.inbox = inbox
        self.inboxDelete = inboxDelete
        self.inboxPurge = inboxPurge
        self.health = health
        self.stats = stats
    }

    func send(_ packet: OutboundTransportPacket, mode: TransportMode, relayConfiguration: RelayConfiguration) async throws {
        sentPackets.append(packet)
    }

    func fetchRelayInbox(recipientID: String, relayConfiguration: RelayConfiguration) async throws -> [OutboundTransportPacket] {
        inbox
    }

    func deleteRelayPacket(packetID: UUID, relayConfiguration: RelayConfiguration) async throws -> Bool {
        inboxDelete
    }

    func checkRelayHealth(relayConfiguration: RelayConfiguration) async throws -> RelayHealthStatus {
        health
    }

    func fetchRelayStats(relayConfiguration: RelayConfiguration) async throws -> RelayStatsResponse {
        stats
    }

    func purgeRelayInbox(recipientID: String, relayConfiguration: RelayConfiguration) async throws -> RelayPurgeResponse {
        inboxPurge
    }

    /// Sprint 27 (2026-06-24): enrollment
    /// stub. Tests that exercise the
    /// enrollment flow set `nextEnrollment`
    /// before calling
    /// `ConversationService.enrollLocalPeerIfNeeded`.
    /// Tests that do not care about enrollment
    /// get a default `RelayEnrollmentResponse`.
    var nextEnrollmentResult: Result<RelayEnrollmentResponse, Error> = .success(
        RelayEnrollmentResponse(peerID: "stub", registeredAt: 0, registrySize: 1)
    )

    func enrollLocalPeer(_ identity: LocalIdentity, relayConfiguration: RelayConfiguration) async throws -> RelayEnrollmentResponse {
        try nextEnrollmentResult.get()
    }
}
