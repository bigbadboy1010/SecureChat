import XCTest
import CryptoKit
import Security
@testable import PrivateChat

@MainActor
final class IdentityManagerTests: XCTestCase {
    func testDisplayNamePersistsAndUpdatesPairingPayload() throws {
        let keychain = MockKeychainStore()
        let crypto = CryptoService()
        let manager = IdentityManager(keychain: keychain, crypto: crypto)

        let original = try manager.loadOrCreateLocalIdentity(displayName: "Francois")
        XCTAssertEqual(original.displayName, "Francois")

        let updated = try manager.updateDisplayName("Secure Tester", identity: original)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.displayName, "Secure Tester")

        let reloaded = try manager.loadOrCreateLocalIdentity(displayName: "Ignored Device Name")
        XCTAssertEqual(reloaded.id, original.id)
        XCTAssertEqual(reloaded.displayName, "Secure Tester")

        let importedPeer = try manager.importPairingPayload(try manager.exportPairingPayload(identity: reloaded))
        XCTAssertEqual(importedPeer.displayName, "Secure Tester")
    }

    func testEmptyDisplayNameFallsBackToPrivateChatPeer() throws {
        let manager = IdentityManager(keychain: MockKeychainStore(), crypto: CryptoService())
        let identity = try manager.loadOrCreateLocalIdentity(displayName: "   ")
        XCTAssertEqual(identity.displayName, "PrivateChat Peer")
    }

    func testDisplayNameSanitizesUnsafeCharacters() throws {
        let manager = IdentityManager(keychain: MockKeychainStore(), crypto: CryptoService())
        let identity = try manager.loadOrCreateLocalIdentity(displayName: "  François <script> 💣  ")
        XCTAssertEqual(identity.displayName, "François script")
    }

    func testTwoPeersDeriveTheSameSafetyNumber() throws {
        let aliceManager = IdentityManager(keychain: MockKeychainStore(), crypto: CryptoService())
        let bobManager = IdentityManager(keychain: MockKeychainStore(), crypto: CryptoService())

        let alice = try aliceManager.loadOrCreateLocalIdentity(displayName: "Alice")
        let bob = try bobManager.loadOrCreateLocalIdentity(displayName: "Bob")

        let alicePeerView = try aliceManager.importPairingPayload(
            try bobManager.exportPairingPayload(identity: bob)
        )
        let bobPeerView = try bobManager.importPairingPayload(
            try aliceManager.exportPairingPayload(identity: alice)
        )

        XCTAssertEqual(alicePeerView.safetyNumber, bobPeerView.safetyNumber)
        XCTAssertTrue(alicePeerView.safetyNumber.hasPrefix("SC3 "))
    }

    func testNewPairingExportIsSignedAndBindsBothKeys() throws {
        let manager = IdentityManager(keychain: MockKeychainStore(), crypto: CryptoService())
        let identity = try manager.loadOrCreateLocalIdentity(displayName: "Alice")
        let encoded = try manager.exportPairingPayload(identity: identity)
        XCTAssertTrue(encoded.hasPrefix("privateroom://pairing/"))
        let payload = try decode(encoded)
        XCTAssertEqual(payload.version, 3)
        let signature = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(payload.signatureBase64)))
        XCTAssertTrue(identity.signingPrivateKey.publicKey.isValidSignature(signature, for: payload.authenticatedData))
        XCTAssertEqual(payload.keyAgreementPublicKeyBase64, identity.keyAgreementPublicKeyData.base64EncodedString())
        XCTAssertEqual(try manager.importPairingPayload(encoded).trustState, .unverified)
    }

    func testSignedPairingRejectsAgreementKeySubstitutionWithRealSigningKey() throws {
        let (manager, identity) = try makeManager("Alice")
        let original = try decode(manager.exportPairingPayload(identity: identity))
        let altered = replacing(original, agreementKey: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation)
        XCTAssertThrowsError(try manager.importPairingPayload(encode(altered))) { error in
            XCTAssertEqual(error as? PrivateChatError, .invalidPairingPayload)
        }
    }

    func testSignedPairingRejectsSigningKeySubstitution() throws {
        let (manager, identity) = try makeManager("Alice")
        let original = try decode(manager.exportPairingPayload(identity: identity))
        let altered = replacing(original, signingKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation)
        XCTAssertThrowsError(try manager.importPairingPayload(encode(altered)))
    }

    func testSignedPairingRejectsMetadataTamperingAndMissingSignature() throws {
        let (manager, identity) = try makeManager("Alice")
        let original = try decode(manager.exportPairingPayload(identity: identity))
        let changedName = PairingPayload(
            version: 3, displayName: "Mallory",
            keyAgreementPublicKeyBase64: original.keyAgreementPublicKeyBase64,
            signingPublicKeyBase64: original.signingPublicKeyBase64,
            createdAt: original.createdAt, signatureBase64: original.signatureBase64
        )
        let changedDate = PairingPayload(
            version: 3, displayName: original.displayName,
            keyAgreementPublicKeyBase64: original.keyAgreementPublicKeyBase64,
            signingPublicKeyBase64: original.signingPublicKeyBase64,
            createdAt: original.createdAt.addingTimeInterval(60), signatureBase64: original.signatureBase64
        )
        let unsignedV3 = PairingPayload(
            version: 3, displayName: original.displayName,
            keyAgreementPublicKeyBase64: original.keyAgreementPublicKeyBase64,
            signingPublicKeyBase64: original.signingPublicKeyBase64,
            createdAt: original.createdAt
        )
        for altered in [changedName, changedDate, unsignedV3] {
            XCTAssertThrowsError(try manager.importPairingPayload(encode(altered)))
        }
    }

    func testLegacyPairingRequiresFullKeyFingerprintComparison() throws {
        let (aliceManager, alice) = try makeManager("Alice")
        let (bobManager, bob) = try makeManager("Bob")
        let aliceView = try aliceManager.importPairingPayload(bobManager.exportPairingPayload(identity: bob))
        let bobView = try bobManager.importPairingPayload(aliceManager.exportPairingPayload(identity: alice))
        for version in [1, 2] {
            let legacy = PairingPayload(
                version: version, displayName: "Bob",
                keyAgreementPublicKeyBase64: bob.keyAgreementPublicKeyData.base64EncodedString(),
                signingPublicKeyBase64: bob.signingPublicKeyData.base64EncodedString(),
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
            let peer = try aliceManager.importPairingPayload(encode(legacy))
            XCTAssertEqual(peer.trustState, .unverified)
            XCTAssertEqual(peer.safetyNumber, bobView.safetyNumber)
            let altered = replacing(legacy, agreementKey: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation)
            let tamperedPeer = try aliceManager.importPairingPayload(encode(altered))
            XCTAssertEqual(tamperedPeer.id, peer.id, "True signing identity alone cannot detect agreement-key substitution")
            XCTAssertEqual(tamperedPeer.trustState, .unverified)
            XCTAssertNotEqual(tamperedPeer.safetyNumber, aliceView.safetyNumber)
            XCTAssertNotEqual(tamperedPeer.safetyNumber, bobView.safetyNumber)
        }
    }

    func testPairingRejectsMalformedAndLowOrderPublicKeys() throws {
        let (manager, identity) = try makeManager("Alice")
        let original = PairingPayload(
            version: 2, displayName: "Alice",
            keyAgreementPublicKeyBase64: identity.keyAgreementPublicKeyData.base64EncodedString(),
            signingPublicKeyBase64: identity.signingPublicKeyData.base64EncodedString(), createdAt: Date()
        )
        for length in [0, 1, 31, 33] {
            XCTAssertThrowsError(try manager.importPairingPayload(encode(replacing(original, agreementKey: Data(repeating: 1, count: length)))))
            XCTAssertThrowsError(try manager.importPairingPayload(encode(replacing(original, signingKey: Data(repeating: 1, count: length)))))
        }
        XCTAssertThrowsError(try manager.importPairingPayload(encode(replacing(original, agreementKey: Data(repeating: 0, count: 32)))))
        var lowOrderOne = Data(repeating: 0, count: 32)
        lowOrderOne[0] = 1
        XCTAssertThrowsError(try manager.importPairingPayload(encode(replacing(original, agreementKey: lowOrderOne))))
    }

    func testPairingRejectsOversizedAndNestedURIsWithoutCreatingIdentity() throws {
        let keychain = MockKeychainStore()
        let manager = IdentityManager(keychain: keychain, crypto: CryptoService())
        XCTAssertThrowsError(try manager.importPairingPayload(String(repeating: "A", count: 8_193)))
        XCTAssertThrowsError(try manager.importPairingPayload("privatechat://pairing/privatechat://pairing/ABC"))
        XCTAssertNil(try keychain.readData(account: "identity.signing.private.v1"))
        XCTAssertNil(try keychain.readData(account: "identity.keyAgreement.private.v1"))
    }

    func testPairingAcceptsCompatibleSchemeAliasesAndRawCode() throws {
        let (manager, identity) = try makeManager("Alice")
        let encoded = try manager.exportPairingPayload(identity: identity)
        let raw = String(encoded.dropFirst("privateroom://pairing/".count))
        let original = try manager.importPairingPayload(encoded)
        for value in [raw, "privatechat://pairing/" + raw, "securechat://pairing/" + raw] {
            XCTAssertEqual(try manager.importPairingPayload(value).safetyNumber, original.safetyNumber)
        }
    }

    private func makeManager(_ name: String) throws -> (IdentityManager, LocalIdentity) {
        let manager = IdentityManager(keychain: MockKeychainStore(), crypto: CryptoService())
        return (manager, try manager.loadOrCreateLocalIdentity(displayName: name))
    }

    private func decode(_ encoded: String) throws -> PairingPayload {
        let raw = String(encoded.dropFirst("privateroom://pairing/".count))
        return try DateCoding.makeDecoder().decode(PairingPayload.self, from: try XCTUnwrap(Base64URL.decode(raw)))
    }

    private func encode(_ payload: PairingPayload) throws -> String {
        Base64URL.encode(try DateCoding.makeEncoder().encode(payload))
    }

    private func replacing(_ payload: PairingPayload, agreementKey: Data? = nil, signingKey: Data? = nil) -> PairingPayload {
        PairingPayload(
            version: payload.version, displayName: payload.displayName,
            keyAgreementPublicKeyBase64: agreementKey?.base64EncodedString() ?? payload.keyAgreementPublicKeyBase64,
            signingPublicKeyBase64: signingKey?.base64EncodedString() ?? payload.signingPublicKeyBase64,
            createdAt: payload.createdAt, signatureBase64: payload.signatureBase64
        )
    }
}

final class KeychainStoreAtomicUpdateTests: XCTestCase {
    func testExistingKeyUpdatesWithoutDeleteOrAdd() throws {
        let mock = KeychainSecurityMock()
        mock.values["key"] = Data("old-test-key".utf8)
        let store = KeychainStore(service: "PrivateRoom.Tests", security: mock.api)
        try store.writeData(Data("new-test-key".utf8), account: "key")
        XCTAssertEqual(try store.readData(account: "key"), Data("new-test-key".utf8))
        XCTAssertEqual(mock.updates, 1)
        XCTAssertEqual(mock.additions, 0)
        XCTAssertEqual(mock.deletions, 0)
        XCTAssertEqual(mock.lastAccessibility, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    }

    func testFailedUpdatePreservesExistingIdentityKey() throws {
        let mock = KeychainSecurityMock()
        let original = Data("existing-identity-test-material".utf8)
        mock.values["key"] = original
        mock.updateFailure = errSecInteractionNotAllowed
        let store = KeychainStore(service: "PrivateRoom.Tests", security: mock.api)
        XCTAssertThrowsError(try store.writeData(Data("replacement".utf8), account: "key")) { error in
            XCTAssertEqual(error as? PrivateChatError, .keychainWriteFailed(status: errSecInteractionNotAllowed))
        }
        XCTAssertEqual(try store.readData(account: "key"), original)
        XCTAssertEqual(mock.additions, 0)
        XCTAssertEqual(mock.deletions, 0)
    }

    func testMissingItemAddsOnlyAfterUpdateReportsNotFound() throws {
        let mock = KeychainSecurityMock()
        let store = KeychainStore(service: "PrivateRoom.Tests", security: mock.api)
        try store.writeData(Data("fresh-test-key".utf8), account: "key")
        XCTAssertEqual(try store.readData(account: "key"), Data("fresh-test-key".utf8))
        XCTAssertEqual(mock.updates, 1)
        XCTAssertEqual(mock.additions, 1)
        XCTAssertEqual(mock.deletions, 0)
    }

    func testConcurrentAddRaceRetriesUpdateWithoutDeletingWinner() throws {
        let mock = KeychainSecurityMock()
        mock.insertBeforeAdd = true
        let store = KeychainStore(service: "PrivateRoom.Tests", security: mock.api)
        try store.writeData(Data("desired-test-key".utf8), account: "key")
        XCTAssertEqual(try store.readData(account: "key"), Data("desired-test-key".utf8))
        XCTAssertEqual(mock.updates, 2)
        XCTAssertEqual(mock.additions, 1)
        XCTAssertEqual(mock.deletions, 0)
    }

    func testFailedAddIsPropagatedWithoutDelete() throws {
        let mock = KeychainSecurityMock()
        mock.addFailure = errSecNotAvailable
        let store = KeychainStore(service: "PrivateRoom.Tests", security: mock.api)
        XCTAssertThrowsError(try store.writeData(Data("test-key".utf8), account: "key"))
        XCTAssertNil(try store.readData(account: "key"))
        XCTAssertEqual(mock.deletions, 0)
    }

    func testSuccessfulReadWithWrongValueTypeFailsClosed() throws {
        let api = KeychainSecurityAPI(
            copyMatching: { _ in (errSecSuccess, "not-key-data" as CFString) },
            update: { _, _ in XCTFail("No mutation during read"); return errSecSuccess },
            add: { _ in XCTFail("No mutation during read"); return errSecSuccess },
            delete: { _ in XCTFail("No mutation during read"); return errSecSuccess }
        )
        let store = KeychainStore(service: "PrivateRoom.Tests", security: api)
        XCTAssertThrowsError(try store.readData(account: "key")) { error in
            XCTAssertEqual(error as? PrivateChatError, .keychainReadFailed(status: errSecDecode))
        }
    }
}

private final class KeychainSecurityMock {
    var values: [String: Data] = [:]
    var updates = 0
    var additions = 0
    var deletions = 0
    var updateFailure: OSStatus?
    var addFailure: OSStatus?
    var insertBeforeAdd = false
    var lastAccessibility: String?

    var api: KeychainSecurityAPI {
        KeychainSecurityAPI(
            copyMatching: { query in
                let account = (query as NSDictionary)[kSecAttrAccount] as! String
                guard let data = self.values[account] else { return (errSecItemNotFound, nil) }
                return (errSecSuccess, data as CFData)
            },
            update: { query, attributes in
                self.updates += 1
                if let failure = self.updateFailure { return failure }
                let account = (query as NSDictionary)[kSecAttrAccount] as! String
                guard self.values[account] != nil else { return errSecItemNotFound }
                let attributes = attributes as NSDictionary
                self.values[account] = attributes[kSecValueData] as? Data
                self.lastAccessibility = attributes[kSecAttrAccessible] as? String
                return errSecSuccess
            },
            add: { query in
                self.additions += 1
                if let failure = self.addFailure { return failure }
                let query = query as NSDictionary
                let account = query[kSecAttrAccount] as! String
                if self.insertBeforeAdd {
                    self.values[account] = Data("racing-test-value".utf8)
                    return errSecDuplicateItem
                }
                self.values[account] = query[kSecValueData] as? Data
                self.lastAccessibility = query[kSecAttrAccessible] as? String
                return errSecSuccess
            },
            delete: { query in
                self.deletions += 1
                let account = (query as NSDictionary)[kSecAttrAccount] as! String
                self.values.removeValue(forKey: account)
                return errSecSuccess
            }
        )
    }
}
