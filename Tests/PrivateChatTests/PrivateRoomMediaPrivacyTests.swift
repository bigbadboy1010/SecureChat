import CryptoKit
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import PrivateChat

final class PrivateRoomMediaPrivacyTests: XCTestCase {
    func testThumbnailBoundsActualDecodedPixels() throws {
        let original = try png(width: 800, height: 400)
        let thumbnail = try PrivateRoomImageDecoder.thumbnail(from: original, maximumDimension: 100)
        XCTAssertEqual(thumbnail.cgImage?.width, 100)
        XCTAssertEqual(thumbnail.cgImage?.height, 50)
        XCTAssertThrowsError(try PrivateRoomImageDecoder.thumbnail(from: Data([1, 2, 3])))
    }

    func testHighlyCompressedOversizedImageIsRejectedBeforeFullDecode() throws {
        let original = try png(width: 16_385, height: 1)
        XCTAssertLessThan(original.count, 8 * 1_048_576, "A compressed byte cap alone cannot enforce pixel dimensions")
        XCTAssertThrowsError(try PrivateRoomImageDecoder.thumbnail(from: original))
    }

    func testNormal48MPCameraDimensionsAreAllowedButExcessivePixelsAndOverflowAreRejected() throws {
        XCTAssertNoThrow(try PrivateRoomImageDecoder.validateDimensions(width: 8_064, height: 6_048))
        XCTAssertThrowsError(try PrivateRoomImageDecoder.validateDimensions(width: 9_000, height: 8_000))
        XCTAssertThrowsError(try PrivateRoomImageDecoder.validateDimensions(width: .max, height: .max))
        XCTAssertThrowsError(try PrivateRoomImageDecoder.validateDimensions(width: 0, height: 1))
    }

    func testPreviewCrashCleanupRemovesOnlyOwnedFilesAndPreservesUserFilesAndSymlinks() throws {
        let directory = try TestDirectoryFactory.make()
        defer { try? FileManager.default.removeItem(at: directory) }
        let previews = directory.appendingPathComponent("protected", isDirectory: true)
        let legacy = directory.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let newPreview = try PrivateRoomPreviewFiles.write(Data("owned fixture".utf8), fileExtension: "../pdf", directory: previews)
        XCTAssertEqual(newPreview.pathExtension, "bin")
        XCTAssertTrue(try previews.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        // The simulator does not implement iOS Data Protection attributes.
        // Actual protection-class verification requires a physical iPhone;
        // simulator coverage still exercises cleanup, paths and backup flags.
        #if os(iOS) && !targetEnvironment(simulator)
        let protection = try FileManager.default.attributesOfItem(atPath: newPreview.path)[.protectionKey]
        XCTAssertEqual((protection as? FileProtectionType)?.rawValue ?? (protection as? String), FileProtectionType.complete.rawValue)
        #endif
        let oldPreview = legacy.appendingPathComponent("PrivateChatPreview-\(UUID().uuidString).pdf")
        let userFile = legacy.appendingPathComponent("important-user-document.pdf")
        let nearMatch = legacy.appendingPathComponent("PrivateChatPreview-not-a-uuid.pdf")
        for file in [oldPreview, userFile, nearMatch] { try Data([1, 2]).write(to: file) }
        let link = previews.appendingPathComponent("\(UUID().uuidString).pdf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: userFile)
        PrivateRoomPreviewFiles.cleanupOwnedFiles(directory: previews, legacyDirectory: legacy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: newPreview.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldPreview.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: userFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: nearMatch.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: link.path))
        PrivateRoomPreviewFiles.cleanupOwnedFiles(directory: previews, legacyDirectory: legacy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: userFile.path))
    }

    private func png(width: Int, height: Int) throws -> Data {
        let pixels = Data(repeating: 0, count: width * height * 4)
        let provider = try XCTUnwrap(CGDataProvider(data: pixels as CFData))
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let encoded = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(encoded as CFMutableData, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return encoded as Data
    }
}

@MainActor
final class PrivateRoomDraftDurabilityTests: XCTestCase {
    func testFailedLegacyMigrationKeepsOriginalUntilEncryptedWriteSucceeds() throws {
        let store = ControlledDraftStore()
        let service = makeService(store: store)
        let id = UUID()
        let suite = "PrivateRoom-Owned-Draft-Test-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "legacy-owned-fixture"
        defaults.set("legacy private draft", forKey: key)
        store.failWrites = true
        let original = service.loadDraft(conversationID: id, legacyUserDefaultsValue: defaults.string(forKey: key)) {
            XCTFail("Failure must not acknowledge a durable migration")
            defaults.removeObject(forKey: key)
        }
        XCTAssertEqual(original, "legacy private draft")
        XCTAssertEqual(defaults.string(forKey: key), original)
        XCTAssertNil(store.values[id])
        store.failWrites = false
        XCTAssertEqual(service.loadDraft(conversationID: id, legacyUserDefaultsValue: original) {
            XCTAssertEqual(store.values[id], original, "The encrypted write must precede plaintext removal")
            defaults.removeObject(forKey: key)
        }, original)
        XCTAssertNil(defaults.string(forKey: key))
    }

    func testFailedDraftSaveAndDeleteCannotReportSuccessOrRemoveDurableContent() {
        let store = ControlledDraftStore()
        let service = makeService(store: store)
        let id = UUID()
        XCTAssertTrue(service.saveDraft("preserved", conversationID: id))
        store.failWrites = true
        XCTAssertFalse(service.saveDraft("replacement", conversationID: id))
        XCTAssertFalse(service.deleteDraft(conversationID: id))
        XCTAssertEqual(store.values[id], "preserved")
        store.failWrites = false
        XCTAssertTrue(service.deleteDraft(conversationID: id))
        XCTAssertNil(store.values[id])
    }

    func testLockedDraftMigrationCannotAcknowledgeDurability() {
        let service = makeService(store: ControlledDraftStore())
        service.endUserSession()
        XCTAssertEqual(service.loadDraft(conversationID: UUID(), legacyUserDefaultsValue: "keep original") {
            XCTFail("A locked session cannot migrate or remove a legacy draft")
        }, "")
        XCTAssertFalse(service.saveDraft("no write", conversationID: UUID()))
        XCTAssertFalse(service.deleteDraft(conversationID: UUID()))
    }

    func testLastEncryptedDraftDeletionPropagatesFilesystemFailure() throws {
        let directory = try TestDirectoryFactory.make()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = try EncryptedDraftStore(keychain: MockKeychainStore(), crypto: CryptoService(), storageDirectoryURL: directory)
        let id = UUID()
        try store.saveDraft("preserved on disk", conversationID: id)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        XCTAssertThrowsError(try store.deleteDraft(conversationID: id))
        XCTAssertEqual(try store.loadDraft(conversationID: id), "preserved on disk")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try store.deleteDraft(conversationID: id)
        XCTAssertNil(try store.loadDraft(conversationID: id))
    }

    private func makeService(store: DraftStoring) -> ConversationService {
        let crypto = CryptoService()
        let signing = Curve25519.Signing.PrivateKey()
        let identity = LocalIdentity(id: crypto.peerID(publicKeyData: signing.publicKey.rawRepresentation), displayName: "Owned test",
                                     keyAgreementPrivateKey: .init(), signingPrivateKey: signing)
        let service = ConversationService(localIdentity: identity, messageStore: MockMessageStore(), draftStore: store,
            peerTrustStore: MockPeerTrustStore(), settingsStore: MockSecuritySettingsStore(),
            relayPacketLedgerStore: MockRelayPacketLedgerStore(), identityManager: MockIdentityManager(localIdentity: identity),
            crypto: crypto, transportCoordinator: MockTransportCoordinator(), forwardSecretStore: InMemoryForwardSecretStore())
        XCTAssertTrue(service.load())
        return service
    }
}

private final class ControlledDraftStore: DraftStoring {
    var values: [UUID: String] = [:]
    var failWrites = false
    func loadDraft(conversationID: UUID) throws -> String? { values[conversationID] }
    func saveDraft(_ draft: String, conversationID: UUID) throws {
        guard !failWrites else { throw PrivateChatError.persistenceFailed("owned fixture") }
        values[conversationID] = draft
    }
    func deleteDraft(conversationID: UUID) throws {
        guard !failWrites else { throw PrivateChatError.persistenceFailed("owned fixture") }
        values.removeValue(forKey: conversationID)
    }
    func migrateLegacyDraftIfNeeded(conversationID: UUID, legacyValue: String?) throws -> String? {
        if let existing = values[conversationID] { return existing }
        guard let legacyValue else { return nil }
        try saveDraft(legacyValue, conversationID: conversationID)
        return legacyValue
    }
}
