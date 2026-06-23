import Foundation

/// On-device store for `PersistedRatchetSession`
/// values, one per `peerID`. Backed by the iOS
/// keychain via `KeychainStoring` (production:
/// `KeychainStore`; tests: an in-memory
/// implementation).
///
/// The store is a thin wrapper that owns the JSON
/// encoding and the `account:` keychain naming.
/// The naming convention is:
///
///   "ratchet.<peerID>"
///
/// so a future `EncryptedMessageStore` can list all
/// stored sessions by enumerating keychain items
/// under the same prefix.
protocol DoubleRatchetStoring {
    func save(_ session: PersistedRatchetSession) throws
    func load(peerID: String) throws -> PersistedRatchetSession?
    func delete(peerID: String) throws
    func listPeerIDs() throws -> [String]
}

/// In-memory implementation used by tests and the
/// SwiftUI previews; the production app uses
/// `KeychainDoubleRatchetStore` below.
final class InMemoryDoubleRatchetStore: DoubleRatchetStoring {
    private var sessions: [String: PersistedRatchetSession] = [:]
    private let lock = NSLock()

    init() {}

    func save(_ session: PersistedRatchetSession) throws {
        lock.lock()
        defer { lock.unlock() }
        sessions[session.peerID] = session
    }

    func load(peerID: String) throws -> PersistedRatchetSession? {
        lock.lock()
        defer { lock.unlock() }
        return sessions[peerID]
    }

    func delete(peerID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        sessions.removeValue(forKey: peerID)
    }

    func listPeerIDs() throws -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(sessions.keys).sorted()
    }
}

/// Keychain-backed implementation. JSON-encodes the
/// `PersistedRatchetSession` and stores it under
/// the keychain account `ratchet.<peerID>`.
final class KeychainDoubleRatchetStore: DoubleRatchetStoring {
    private let keychain: KeychainStoring
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        keychain: KeychainStoring = KeychainStore(),
        encoder: JSONEncoder = DoubleRatchetStore.defaultEncoder,
        decoder: JSONDecoder = DoubleRatchetStore.defaultDecoder
    ) {
        self.keychain = keychain
        self.encoder = encoder
        self.decoder = decoder
    }

    func save(_ session: PersistedRatchetSession) throws {
        let data = try encoder.encode(session)
        try keychain.writeData(data, account: account(for: session.peerID))
    }

    func load(peerID: String) throws -> PersistedRatchetSession? {
        guard let data = try keychain.readData(account: account(for: peerID)) else {
            return nil
        }
        return try decoder.decode(PersistedRatchetSession.self, from: data)
    }

    func delete(peerID: String) throws {
        try keychain.deleteData(account: account(for: peerID))
    }

    /// Listing needs the keychain to enumerate
    /// items. The current `KeychainStoring`
    /// protocol does not expose that, so this
    /// implementation returns the empty array and
    /// a warning is logged. Sprint 10 will add a
    /// `list(accountPrefix:)` method to the
    /// protocol and a corresponding
    /// `SecItemCopyMatching` with
    /// `kSecMatchLimitAll`.
    func listPeerIDs() throws -> [String] {
        []
    }

    private func account(for peerID: String) -> String {
        "ratchet.\(peerID)"
    }
}

public enum DoubleRatchetStore {
    /// Shared JSON encoder that preserves the
    /// `createdAt` timestamps as ISO-8601 strings
    /// (the on-device keychain is JSON, not binary).
    public static let defaultEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public static let defaultDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
