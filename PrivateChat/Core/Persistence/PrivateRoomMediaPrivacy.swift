import Foundation
import ImageIO
import UIKit

/// Bounds decoded pixels as well as compressed bytes. The original image is
/// never decoded at full resolution merely to display a chat thumbnail.
enum PrivateRoomImageDecoder {
    static let maximumPixelDimension: Int64 = 16_384
    static let maximumPixelCount: Int64 = 64_000_000 // Includes normal 48 MP camera images.
    static let maximumEncodedBytes = 32 * 1_048_576

    static func thumbnail(from data: Data, maximumDimension: Int = 2_048) throws -> UIImage {
        guard !data.isEmpty, data.count <= maximumEncodedBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.int64Value,
              let height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.int64Value,
              width > 0, height > 0 else {
            throw PrivateChatError.unsupportedAttachment
        }
        try validateDimensions(width: width, height: height)
        let limit = min(4_096, max(1, maximumDimension))
        let options: [String: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways as String: true,
            kCGImageSourceCreateThumbnailWithTransform as String: true,
            kCGImageSourceThumbnailMaxPixelSize as String: limit,
            kCGImageSourceShouldCacheImmediately as String: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              image.width <= limit, image.height <= limit else {
            throw PrivateChatError.unsupportedAttachment
        }
        return UIImage(cgImage: image)
    }

    static func validateDimensions(width: Int64, height: Int64) throws {
        guard width > 0, height > 0,
              width <= maximumPixelDimension, height <= maximumPixelDimension,
              width * height <= maximumPixelCount else {
            throw PrivateChatError.unsupportedAttachment
        }
    }
}

/// Quick Look needs a temporary plaintext file. Keep it in a protected,
/// backup-excluded directory and reclaim only our exact generated filenames.
enum PrivateRoomPreviewFiles {
    private static var defaultDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PrivateRoomPreviews", isDirectory: true)
    }

    static func write(_ data: Data, fileExtension: String, directory: URL? = nil) throws -> URL {
        let directory = directory ?? defaultDirectory
        let manager = FileManager.default
        #if os(iOS)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.complete])
        #else
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        #endif
        var protectedDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedDirectory.setResourceValues(values)
        let proposedSuffix = fileExtension.lowercased()
        let suffix = proposedSuffix.range(of: "^[a-z0-9]{1,12}$", options: .regularExpression) != nil ? proposedSuffix : "bin"
        let file = directory.appendingPathComponent(UUID().uuidString.lowercased()).appendingPathExtension(suffix)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: file, options: [.atomic])
        #endif
        return file
    }

    static func remove(_ file: URL) {
        guard isOwnedFilename(file.lastPathComponent, prefix: "") else { return }
        try? FileManager.default.removeItem(at: file)
    }

    /// Run on startup and every session lock, including after a preview crash.
    /// Never recurse into user folders or remove unrelated temporary files.
    static func cleanupOwnedFiles(directory: URL? = nil, legacyDirectory: URL? = nil) {
        removeOwnedFiles(in: directory ?? defaultDirectory, prefix: "")
        removeOwnedFiles(in: legacyDirectory ?? FileManager.default.temporaryDirectory, prefix: "PrivateChatPreview-")
    }

    private static func removeOwnedFiles(in directory: URL, prefix: String) {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: []) else { return }
        for file in files where isOwnedFilename(file.lastPathComponent, prefix: prefix) {
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            try? manager.removeItem(at: file)
        }
    }

    private static func isOwnedFilename(_ filename: String, prefix: String) -> Bool {
        guard filename.hasPrefix(prefix) else { return false }
        let remainder = String(filename.dropFirst(prefix.count))
        guard remainder.count >= 36 else { return false }
        let identifier = String(remainder.prefix(36))
        guard UUID(uuidString: identifier)?.uuidString.lowercased() == identifier.lowercased() else { return false }
        let suffix = remainder.dropFirst(36)
        return suffix.isEmpty || (suffix.first == "." && suffix.count > 1)
    }
}
