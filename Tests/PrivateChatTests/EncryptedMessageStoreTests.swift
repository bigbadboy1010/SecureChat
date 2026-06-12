import XCTest
@testable import PrivateChat

final class EncryptedMessageStoreTests: XCTestCase {
    func testSaveLoadRoundTripPersistsEncryptedConversation() throws {
        let storageURL = try TestDirectoryFactory.make()
        let keychain = MockKeychainStore()
        let crypto = CryptoService()
        let conversationID = UUID()
        let conversation = StoredConversation(
            conversation: Conversation(
                id: conversationID,
                title: "Audit Chat",
                peerID: "peer-1"
            ),
            messages: [
                ChatMessage(
                    conversationID: conversationID,
                    senderID: "alice",
                    recipientID: "bob",
                    body: "Geheimer Inhalt",
                    status: .sent,
                    isIncoming: false
                )
            ]
        )

        let writer = try EncryptedMessageStore(keychain: keychain, crypto: crypto, storageDirectoryURL: storageURL)
        try writer.save([conversation])

        let rawFile = try Data(contentsOf: storageURL.appendingPathComponent("messages.store"))
        XCTAssertFalse(String(data: rawFile, encoding: .utf8)?.contains("Geheimer Inhalt") == true)

        let reader = try EncryptedMessageStore(keychain: keychain, crypto: crypto, storageDirectoryURL: storageURL)
        let loaded = try reader.load()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.conversation.title, "Audit Chat")
        XCTAssertEqual(loaded.first?.messages.first?.body, "Geheimer Inhalt")
        XCTAssertEqual(loaded.first?.messages.first?.status, .sent)
    }

    func testMissingStoreLoadsEmptyList() throws {
        let store = try EncryptedMessageStore(
            keychain: MockKeychainStore(),
            crypto: CryptoService(),
            storageDirectoryURL: try TestDirectoryFactory.make()
        )

        XCTAssertEqual(try store.load(), [])
    }

    func testCorruptedStoreFailsClosed() throws {
        let storageURL = try TestDirectoryFactory.make()
        let fileURL = storageURL.appendingPathComponent("messages.store")
        try Data("not-a-valid-aes-gcm-box".utf8).write(to: fileURL)

        let store = try EncryptedMessageStore(
            keychain: MockKeychainStore(),
            crypto: CryptoService(),
            storageDirectoryURL: storageURL
        )

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? PrivateChatError, .decryptionFailed)
        }
    }
}
