import Foundation
import XCTest
@testable import PrivateChat

final class AttachmentImportBoundaryTests: XCTestCase {
    func testActualFileBytesAreBoundedEvenWithoutUsingSizeMetadata() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PrivateRoom-Owned-Import-Test-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("fixture.bin")
        let boundary = Data(repeating: 3, count: 65_536)
        try boundary.write(to: file)
        XCTAssertEqual(try PrivateRoomAttachmentImport.readBounded(file, maximumBytes: boundary.count), boundary)
        try (boundary + Data([4])).write(to: file)
        XCTAssertThrowsError(try PrivateRoomAttachmentImport.readBounded(file, maximumBytes: boundary.count))
    }

    func testEmptyFilesAreRejectedAndReadersCanBeReopened() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("PrivateRoom-Owned-Empty-Test-\(UUID()).bin")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data().write(to: file)
        XCTAssertThrowsError(try PrivateRoomAttachmentImport.readBounded(file, maximumBytes: 10))
        try Data([1, 2]).write(to: file)
        XCTAssertEqual(try PrivateRoomAttachmentImport.readBounded(file, maximumBytes: 10), Data([1, 2]))
    }
}
