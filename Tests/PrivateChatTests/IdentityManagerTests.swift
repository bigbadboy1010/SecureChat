import XCTest
@testable import PrivateChat

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

}
