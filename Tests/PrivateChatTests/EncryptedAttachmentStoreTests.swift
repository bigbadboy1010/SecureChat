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
        let chunkSize = 64 * 1_024
        let chunks = stride(from: 0, to: completeData.count, by: chunkSize).map { start in
            completeData.subdata(in: start..<min(start + chunkSize, completeData.count))
        }

        for index in [2, 0] {
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

    func testGlobalPendingTransferQuotaRejectsWithoutWritingNewFiles() throws {
        let directory = try TestDirectoryFactory.make()
        let store = try EncryptedAttachmentStore(
            keychain: MockKeychainStore(), crypto: CryptoService(), storageDirectoryURL: directory,
            maximumPendingTransfers: 2
        )
        let chunk = Data(repeating: 7, count: 65_536)
        for _ in 0..<2 {
            XCTAssertFalse(try partial(store, id: UUID(), chunk: chunk))
        }
        let filesBefore = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertThrowsError(try partial(store, id: UUID(), chunk: chunk)) { error in
            guard let error = error as? PrivateChatError, case .persistenceFailed = error else {
                return XCTFail("Expected recoverable quota error")
            }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), filesBefore)
    }

    func testGlobalPendingByteQuotaIncludesManifestAndCiphertextOverhead() throws {
        let directory = try TestDirectoryFactory.make()
        let store = try EncryptedAttachmentStore(
            keychain: MockKeychainStore(), crypto: CryptoService(), storageDirectoryURL: directory,
            maximumPendingBytes: 70_000
        )
        let chunk = Data(repeating: 9, count: 65_536)
        XCTAssertFalse(try partial(store, id: UUID(), chunk: chunk))
        let filesBefore = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertThrowsError(try partial(store, id: UUID(), chunk: chunk))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), filesBefore)
        let storedBytes = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            .reduce(0) { result, url in result + (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        XCTAssertLessThanOrEqual(storedBytes, 70_000)
        XCTAssertGreaterThan(storedBytes, chunk.count + 28)
    }

    func testPinnedTransferContextAndMetadataRejectMixingButValidTransferCompletes() throws {
        let directory = try TestDirectoryFactory.make()
        let keychain = MockKeychainStore()
        let id = UUID()
        let complete = Data(repeating: 5, count: 131_072)
        let digest = RequestSigner.sha256Hex(complete)
        let first = complete.prefix(65_536)
        let last = complete.suffix(65_536)
        let store = try EncryptedAttachmentStore(keychain: keychain, crypto: CryptoService(), storageDirectoryURL: directory)
        XCTAssertFalse(try store.storeIncomingChunk(
            attachmentID: id, index: 0, totalChunks: 2, data: Data(first),
            expectedByteCount: complete.count, expectedSHA256: digest, transferContext: "alice|conversation|message"
        ))
        XCTAssertThrowsError(try store.storeIncomingChunk(
            attachmentID: id, index: 1, totalChunks: 2, data: Data(last),
            expectedByteCount: complete.count, expectedSHA256: digest, transferContext: "bob|conversation|message"
        ))
        XCTAssertThrowsError(try store.storeIncomingChunk(
            attachmentID: id, index: 1, totalChunks: 2, data: Data(last),
            expectedByteCount: complete.count, expectedSHA256: String(repeating: "0", count: 64),
            transferContext: "alice|conversation|message"
        ))
        let reloaded = try EncryptedAttachmentStore(keychain: keychain, crypto: CryptoService(), storageDirectoryURL: directory)
        XCTAssertTrue(try reloaded.storeIncomingChunk(
            attachmentID: id, index: 1, totalChunks: 2, data: Data(last),
            expectedByteCount: complete.count, expectedSHA256: digest, transferContext: "alice|conversation|message"
        ))
        XCTAssertEqual(try reloaded.loadAttachment(id: id), complete)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasSuffix(".pending") || $0.hasSuffix(".chunk") })
    }

    func testContradictoryChunkDoesNotOverwriteAuthenticatedPartial() throws {
        let directory = try TestDirectoryFactory.make()
        let store = try EncryptedAttachmentStore(keychain: MockKeychainStore(), crypto: CryptoService(), storageDirectoryURL: directory)
        let id = UUID()
        let chunk = Data(repeating: 1, count: 65_536)
        XCTAssertFalse(try partial(store, id: id, chunk: chunk))
        let chunkURL = directory.appendingPathComponent("\(id.uuidString.lowercased()).0.chunk")
        let originalCiphertext = try Data(contentsOf: chunkURL)
        XCTAssertThrowsError(try partial(store, id: id, chunk: Data(repeating: 2, count: 65_536)))
        XCTAssertEqual(try Data(contentsOf: chunkURL), originalCiphertext)
        XCTAssertFalse(try partial(store, id: id, chunk: chunk))
        XCTAssertEqual(try Data(contentsOf: chunkURL), originalCiphertext, "Idempotent retry must not rewrite nonce or lifetime")
    }

    func testPendingManifestTamperingFailsBeforeAnotherTransferIsStored() throws {
        let directory = try TestDirectoryFactory.make()
        let store = try EncryptedAttachmentStore(keychain: MockKeychainStore(), crypto: CryptoService(), storageDirectoryURL: directory)
        let id = UUID()
        XCTAssertFalse(try partial(store, id: id, chunk: Data(repeating: 3, count: 65_536)))
        let manifestURL = directory.appendingPathComponent("\(id.uuidString.lowercased()).pending")
        var bytes = try Data(contentsOf: manifestURL)
        bytes[bytes.count - 1] ^= 1
        try bytes.write(to: manifestURL)
        let filesBefore = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertThrowsError(try partial(store, id: UUID(), chunk: Data(repeating: 3, count: 65_536)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), filesBefore)
    }

    func testExpiryFreesPendingQuotaAndPreservesFinishedAttachments() throws {
        let directory = try TestDirectoryFactory.make()
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try EncryptedAttachmentStore(
            keychain: MockKeychainStore(), crypto: CryptoService(), storageDirectoryURL: directory,
            now: { clock }, maximumPendingTransfers: 1
        )
        let finishedID = UUID()
        let finished = Data("already-owned-finished-document".utf8)
        try store.saveAttachment(id: finishedID, data: finished)
        let expiredID = UUID()
        let chunk = Data(repeating: 4, count: 65_536)
        XCTAssertFalse(try partial(store, id: expiredID, chunk: chunk))
        clock = clock.addingTimeInterval(86_390)
        XCTAssertFalse(try partial(store, id: expiredID, chunk: chunk))
        clock = clock.addingTimeInterval(11)
        XCTAssertFalse(try partial(store, id: UUID(), chunk: chunk))
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(files.contains { $0.hasPrefix(expiredID.uuidString.lowercased() + ".") })
        XCTAssertEqual(try store.loadAttachment(id: finishedID), finished)
    }

    func testIncomingUUIDCollisionCannotOverwriteFinishedAttachment() throws {
        let directory = try TestDirectoryFactory.make()
        let store = try EncryptedAttachmentStore(keychain: MockKeychainStore(), crypto: CryptoService(), storageDirectoryURL: directory)
        let id = UUID()
        let owned = Data("owned-photo".utf8)
        try store.saveAttachment(id: id, data: owned)
        let url = directory.appendingPathComponent("\(id.uuidString.lowercased()).attachment")
        let ciphertext = try Data(contentsOf: url)
        let malicious = Data("other-photo".utf8)
        XCTAssertThrowsError(try store.storeIncomingChunk(
            attachmentID: id, index: 0, totalChunks: 1, data: malicious,
            expectedByteCount: malicious.count, expectedSHA256: RequestSigner.sha256Hex(malicious), transferContext: "other-peer"
        ))
        XCTAssertEqual(try Data(contentsOf: url), ciphertext)
        XCTAssertEqual(try store.loadAttachment(id: id), owned)
        XCTAssertTrue(try store.storeIncomingChunk(
            attachmentID: id, index: 0, totalChunks: 1, data: owned,
            expectedByteCount: owned.count, expectedSHA256: RequestSigner.sha256Hex(owned), transferContext: "original-peer"
        ))
        XCTAssertEqual(try Data(contentsOf: url), ciphertext)
    }

    func testMissingKeyForExistingEncryptedAttachmentDoesNotGenerateReplacement() throws {
        let directory = try TestDirectoryFactory.make()
        let keychain = MockKeychainStore()
        let store = try EncryptedAttachmentStore(keychain: keychain, crypto: CryptoService(), storageDirectoryURL: directory)
        let id = UUID()
        try store.saveAttachment(id: id, data: Data("recovery-sensitive-test-data".utf8))
        let url = directory.appendingPathComponent("\(id.uuidString.lowercased()).attachment")
        let ciphertext = try Data(contentsOf: url)
        try keychain.deleteData(account: "local.encryptedAttachmentStore.key.v1")
        XCTAssertThrowsError(try store.loadAttachment(id: id)) { error in
            XCTAssertEqual(error as? PrivateChatError, .invalidKeyMaterial)
        }
        XCTAssertNil(try keychain.readData(account: "local.encryptedAttachmentStore.key.v1"))
        XCTAssertEqual(try Data(contentsOf: url), ciphertext)
    }

    func testMalformedShortChunkAndOversizedContextLeaveStorageEmpty() throws {
        let directory = try TestDirectoryFactory.make()
        let store = try EncryptedAttachmentStore(keychain: MockKeychainStore(), crypto: CryptoService(), storageDirectoryURL: directory)
        XCTAssertThrowsError(try partial(store, id: UUID(), chunk: Data([1])))
        XCTAssertThrowsError(try store.storeIncomingChunk(
            attachmentID: UUID(), index: 0, totalChunks: 2, data: Data(repeating: 1, count: 65_536),
            expectedByteCount: 131_072, expectedSHA256: String(repeating: "0", count: 64), transferContext: String(repeating: "A", count: 513)
        ))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    private func partial(_ store: EncryptedAttachmentStore, id: UUID, chunk: Data) throws -> Bool {
        try store.storeIncomingChunk(
            attachmentID: id, index: 0, totalChunks: 2, data: chunk,
            expectedByteCount: 131_072, expectedSHA256: String(repeating: "0", count: 64), transferContext: "test-peer|conversation|message"
        )
    }
}
