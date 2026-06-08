import Foundation
import CryptoKit
import CommonCrypto

final class MediaService {
    static let shared = MediaService()

    private let encryptionService = EncryptionService.shared
    private let persistence = MessagePersistenceService.shared
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let queue = DispatchQueue(label: "com.secureChat.media", attributes: .concurrent)

    // Configuration
    struct Config {
        static let maxFileSizeMB: Int64 = 100
        static let thumbnailSize: CGSize = CGSize(width: 320, height: 320)
        static let supportedImageTypes = ["jpg", "jpeg", "png", "gif", "webp"]
        static let supportedVideoTypes = ["mp4", "mov", "m4v", "3gp"]
        static let supportedAudioTypes = ["m4a", "aac", "mp3", "wav", "flac"]
        static let supportedDocTypes = ["pdf", "doc", "docx", "txt", "xlsx", "xls"]
    }

    private init() {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("SecureChat/Media")

        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Upload & Encryption
    func encryptAndUploadMedia(
        fileURL: URL,
        mediaType: MediaAttachment.MediaType,
        recipientCount: Int = 1
    ) -> MediaAttachment? {
        guard fileURL.startAccessingSecurityScopedResource() else {
            print("❌ Cannot access file: \(fileURL.lastPathComponent)")
            return nil
        }
        defer { fileURL.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: fileURL) else {
            print("❌ Failed to read file")
            return nil
        }

        guard data.count <= Config.maxFileSizeMB * 1024 * 1024 else {
            print("❌ File too large: \(data.count / (1024 * 1024))MB exceeds \(Config.maxFileSizeMB)MB")
            return nil
        }

        // Validate media type
        let fileExtension = fileURL.pathExtension.lowercased()
        guard validateMediaType(mediaType, fileExtension: fileExtension) else {
            print("❌ Invalid file type for media type: \(mediaType)")
            return nil
        }

        // Generate encryption key
        let encryptionKey = SymmetricKey(size: .bits256)
        let keyB64 = encryptionKey.withUnsafeBytes { Data($0).base64EncodedString() }

        // Encrypt file using AES-GCM
        guard let encryptedData = encryptFileData(data, using: encryptionKey) else {
            print("❌ Encryption failed")
            return nil
        }

        // Generate thumbnail for images/videos
        var thumbnailB64: String?
        if mediaType == .image || mediaType == .video {
            thumbnailB64 = generateThumbnail(from: fileURL, mediaType: mediaType)
        }

        let attachment = MediaAttachment(
            type: mediaType,
            fileName: fileURL.lastPathComponent,
            fileSize: Int64(data.count),
            mimeType: getMimeType(fileExtension),
            encryptedData: encryptedData,
            encryptionKey: keyB64,
            thumbnailBase64: thumbnailB64
        )

        // Store encrypted file in cache
        storeEncryptedMedia(attachment)

        print("✅ Media encrypted & stored: \(attachment.fileName)")
        return attachment
    }

    // MARK: - Download & Decryption
    func decryptAndDownloadMedia(_ attachment: MediaAttachment) -> URL? {
        guard let keyData = Data(base64Encoded: attachment.encryptionKey) else {
            print("❌ Invalid encryption key")
            return nil
        }

        let symmetricKey = SymmetricKey(data: keyData)

        guard let decryptedData = decryptFileData(attachment.encryptedData, using: symmetricKey) else {
            print("❌ Decryption failed")
            return nil
        }

        let fileURL = cacheDirectory.appendingPathComponent(attachment.fileName)

        do {
            try decryptedData.write(to: fileURL)
            print("✅ Media decrypted: \(attachment.fileName)")
            return fileURL
        } catch {
            print("❌ Failed to write decrypted file: \(error)")
            return nil
        }
    }

    // MARK: - Thumbnail Generation
    private func generateThumbnail(from fileURL: URL, mediaType: MediaAttachment.MediaType) -> String? {
        #if os(iOS)
        import UIKit

        if mediaType == .image {
            guard let image = UIImage(contentsOfFile: fileURL.path) else { return nil }
            let thumbnailImage = resizeImage(image, targetSize: Config.thumbnailSize)

            if let jpegData = thumbnailImage.jpegData(compressionQuality: 0.7) {
                return jpegData.base64EncodedString()
            }
        } else if mediaType == .video {
            // Use AVAsset to extract first frame
            guard let thumbnail = extractVideoThumbnail(fileURL) else { return nil }
            if let jpegData = thumbnail.jpegData(compressionQuality: 0.7) {
                return jpegData.base64EncodedString()
            }
        }

        return nil
        #else
        return nil
        #endif
    }

    #if os(iOS)
    private func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func extractVideoThumbnail(_ fileURL: URL) -> UIImage? {
        import AVFoundation

        let asset = AVAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        do {
            let cgImage = try generator.copyCGImage(at: CMTime.zero, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            print("❌ Failed to extract video thumbnail: \(error)")
            return nil
        }
    }
    #endif

    // MARK: - Encryption/Decryption
    private func encryptFileData(_ data: Data, using key: SymmetricKey) -> Data? {
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            var encryptedData = sealedBox.nonce.withUnsafeBytes { Data($0) }
            encryptedData.append(sealedBox.ciphertext)
            encryptedData.append(sealedBox.tag)
            return encryptedData
        } catch {
            print("❌ Encryption error: \(error)")
            return nil
        }
    }

    private func decryptFileData(_ encryptedData: Data, using key: SymmetricKey) -> Data? {
        do {
            let nonceSize = 12 // AES-GCM nonce size
            let tagSize = 16 // GCM tag size

            guard encryptedData.count > nonceSize + tagSize else {
                print("❌ Invalid encrypted data size")
                return nil
            }

            let nonce = try AES.GCM.Nonce(data: encryptedData.subdata(in: 0..<nonceSize))
            let ciphertext = encryptedData.subdata(in: nonceSize..<(encryptedData.count - tagSize))
            let tag = encryptedData.subdata(in: (encryptedData.count - tagSize)..<encryptedData.count)

            let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            print("❌ Decryption error: \(error)")
            return nil
        }
    }

    // MARK: - Storage
    private func storeEncryptedMedia(_ attachment: MediaAttachment) {
        let fileURL = cacheDirectory.appendingPathComponent(attachment.id)

        do {
            try attachment.encryptedData.write(to: fileURL)
        } catch {
            print("❌ Failed to store encrypted media: \(error)")
        }
    }

    // MARK: - Validation & Helpers
    private func validateMediaType(_ mediaType: MediaAttachment.MediaType, fileExtension: String) -> Bool {
        switch mediaType {
        case .image:
            return Config.supportedImageTypes.contains(fileExtension)
        case .video:
            return Config.supportedVideoTypes.contains(fileExtension)
        case .audio:
            return Config.supportedAudioTypes.contains(fileExtension)
        case .document:
            return Config.supportedDocTypes.contains(fileExtension)
        case .file:
            return true // Accept any file type
        }
    }

    private func getMimeType(_ fileExtension: String) -> String {
        let mimeTypes: [String: String] = [
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "png": "image/png",
            "gif": "image/gif",
            "webp": "image/webp",
            "mp4": "video/mp4",
            "mov": "video/quicktime",
            "m4v": "video/x-m4v",
            "3gp": "video/3gpp",
            "m4a": "audio/mp4",
            "aac": "audio/aac",
            "mp3": "audio/mpeg",
            "wav": "audio/wav",
            "flac": "audio/flac",
            "pdf": "application/pdf",
            "doc": "application/msword",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "txt": "text/plain",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "xls": "application/vnd.ms-excel",
        ]

        return mimeTypes[fileExtension] ?? "application/octet-stream"
    }

    // MARK: - Cleanup
    func cleanupExpiredMedia(olderThan days: Int) {
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(days * 86400))

        queue.async(flags: .barrier) {
            guard let contents = try? self.fileManager.contentsOfDirectory(
                at: self.cacheDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { return }

            for fileURL in contents {
                guard let attributes = try? self.fileManager.attributesOfItem(atPath: fileURL.path),
                      let modDate = attributes[.modificationDate] as? Date else { continue }

                if modDate < cutoffDate {
                    try? self.fileManager.removeItem(at: fileURL)
                }
            }

            print("✅ Expired media cleaned up")
        }
    }

    func getCacheSize() -> Int64 {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        return contents.reduce(0) { total, url in
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let fileSize = attributes[.size] as? Int64 else { return total }
            return total + fileSize
        }
    }
}
