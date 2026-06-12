import XCTest
@testable import PrivateChat

final class EncryptedDraftStoreTests: XCTestCase {
    func testInMemoryDraftStoreRoundTripAndDeletion() throws {
        let conversationID = UUID()
        let store = InMemoryDraftStore()

        try store.saveDraft("Geheimer Entwurf", conversationID: conversationID)
        XCTAssertEqual(try store.loadDraft(conversationID: conversationID), "Geheimer Entwurf")

        try store.deleteDraft(conversationID: conversationID)
        XCTAssertNil(try store.loadDraft(conversationID: conversationID))
    }

    func testLegacyDraftMigratesOnlyWhenEncryptedDraftIsMissing() throws {
        let conversationID = UUID()
        let store = InMemoryDraftStore()

        let migrated = try store.migrateLegacyDraftIfNeeded(conversationID: conversationID, legacyValue: "Alt-Entwurf")
        XCTAssertEqual(migrated, "Alt-Entwurf")
        XCTAssertEqual(try store.loadDraft(conversationID: conversationID), "Alt-Entwurf")

        let second = try store.migrateLegacyDraftIfNeeded(conversationID: conversationID, legacyValue: "Soll nicht überschreiben")
        XCTAssertEqual(second, "Alt-Entwurf")
    }
    func testEncryptedDraftStoreRoundTripPersistsOutsideUserDefaults() throws {
        let storageURL = try TestDirectoryFactory.make()
        let store = try EncryptedDraftStore(
            keychain: MockKeychainStore(),
            crypto: CryptoService(),
            storageDirectoryURL: storageURL
        )
        let conversationID = UUID()

        try store.saveDraft("Verschlüsselter Entwurf", conversationID: conversationID)
        XCTAssertEqual(try store.loadDraft(conversationID: conversationID), "Verschlüsselter Entwurf")

        let rawFile = try Data(contentsOf: storageURL.appendingPathComponent("drafts.store"))
        XCTAssertFalse(String(data: rawFile, encoding: .utf8)?.contains("Verschlüsselter Entwurf") == true)

        try store.deleteDraft(conversationID: conversationID)
        XCTAssertNil(try store.loadDraft(conversationID: conversationID))
    }

}
