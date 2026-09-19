import XCTest
@testable import PrivateChat

final class EncryptedAttachmentStoreTests: XCTestCase {
    func testSaveLoadRoundTripKeepsPlaintextOutOfStorage() throws {
        let directory = try TestDirectoryFactory.make()
        let keychain = MockKeychainStore()
        let attachmentID = UUID()
        let plaintext = Data("private-photo-payload".utf8)
        let store = try EncryptedAttachmentStore(
            keychain: keychain,
            crypto: CryptoService(),
            storageDirectoryURL: directory
        )

        try store.saveAttachment(id: attachmentID, data: plaintext)

        let storedURL = directory.appendingPathComponent("\(attachmentID.uuidString.lowercased()).attachment")
        let storedBytes = try Data(contentsOf: storedURL)
        XCTAssertNotEqual(storedBytes, plaintext)
        XCTAssertNil(String(data: storedBytes, encoding: .utf8)?.range(of: "private-photo-payload"))
        XCTAssertEqual(try store.loadAttachment(id: attachmentID), plaintext)
    }

    func testIncomingChunksAssembleAcrossStoreInstances() throws {
        let directory = try TestDirectoryFactory.make()
        let keychain = MockKeychainStore()
        let attachmentID = UUID()
        let completeData = Data((0..<150_000).map { UInt8($0 % 251) })
        let digest = RequestSigner.sha256Hex(completeData)
        let chunkSize = 48 * 1_024
        let chunks = stride(from: 0, to: completeData.count, by: chunkSize).map { start in
            completeData.subdata(in: start..<min(start + chunkSize, completeData.count))
        }

        for index in [3, 0, 2] {
            let store = try EncryptedAttachmentStore(
                keychain: keychain,
                crypto: CryptoService(),
                storageDirectoryURL: directory
            )
            XCTAssertFalse(try store.storeIncomingChunk(
                attachmentID: attachmentID,
                index: index,
                totalChunks: chunks.count,
                data: chunks[index],
                expectedByteCount: completeData.count,
                expectedSHA256: digest
            ))
        }

        let finalStore = try EncryptedAttachmentStore(
            keychain: keychain,
            crypto: CryptoService(),
            storageDirectoryURL: directory
        )
        XCTAssertTrue(try finalStore.storeIncomingChunk(
            attachmentID: attachmentID,
            index: 1,
            totalChunks: chunks.count,
            data: chunks[1],
            expectedByteCount: completeData.count,
            expectedSHA256: digest
        ))
        XCTAssertEqual(try finalStore.loadAttachment(id: attachmentID), completeData)
    }

    func testIncomingChunkHashMismatchFailsClosed() throws {
        let store = try EncryptedAttachmentStore(
            keychain: MockKeychainStore(),
            crypto: CryptoService(),
            storageDirectoryURL: try TestDirectoryFactory.make()
        )

        XCTAssertThrowsError(try store.storeIncomingChunk(
            attachmentID: UUID(),
            index: 0,
            totalChunks: 1,
            data: Data("tampered".utf8),
            expectedByteCount: 8,
            expectedSHA256: String(repeating: "0", count: 64)
        )) { error in
            XCTAssertEqual(error as? PrivateChatError, .invalidInboundPacket)
        }
    }
}
