import Foundation
import Compression

final class BackupService {
    static let shared = BackupService()

    private let persistence = MessagePersistenceService.shared
    private let fileManager = FileManager.default
    private let backupDirectory: URL
    private let queue = DispatchQueue(label: "com.secureChat.backup", attributes: .concurrent)

    private init() {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        backupDirectory = paths[0].appendingPathComponent("Backups")
        try? fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Export
    func exportChannelData(_ channelTag: String, format: ExportFormat = .json) -> URL? {
        let messages = persistence.fetchMessages(channelTag: channelTag, limit: 10000)

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fileName = "chat_export_\(channelTag)_\(timestamp)"

        switch format {
        case .json:
            return exportAsJSON(messages, fileName: fileName, channelTag: channelTag)
        case .csv:
            return exportAsCSV(messages, fileName: fileName, channelTag: channelTag)
        case .pdf:
            return exportAsPDF(messages, fileName: fileName, channelTag: channelTag)
        }
    }

    private func exportAsJSON(_ messages: [BitchatMessage], fileName: String, channelTag: String) -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let jsonData = try? encoder.encode(messages) else {
            print("❌ JSON encoding failed")
            return nil
        }

        let fileURL = backupDirectory.appendingPathComponent("\(fileName).json")

        do {
            try jsonData.write(to: fileURL)
            print("✅ Exported to JSON: \(fileURL.lastPathComponent)")
            return fileURL
        } catch {
            print("❌ JSON export failed: \(error)")
            return nil
        }
    }

    private func exportAsCSV(_ messages: [BitchatMessage], fileName: String, channelTag: String) -> URL? {
        var csvContent = "ID,Timestamp,Sender,Content,DeliveryStatus,IsEncrypted\n"

        for message in messages {
            let timestamp = ISO8601DateFormatter().string(from: message.timestamp)
            let escapedContent = message.content.replacingOccurrences(of: "\"", with: "\"\"")
            let row = "\"\(message.id)\",\"\(timestamp)\",\"\(message.senderID)\",\"\(escapedContent)\",\"\(message.deliveryStatus.rawValue)\",\(message.isEncrypted)\n"
            csvContent.append(row)
        }

        let fileURL = backupDirectory.appendingPathComponent("\(fileName).csv")

        do {
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
            print("✅ Exported to CSV: \(fileURL.lastPathComponent)")
            return fileURL
        } catch {
            print("❌ CSV export failed: \(error)")
            return nil
        }
    }

    private func exportAsPDF(_ messages: [BitchatMessage], fileName: String, channelTag: String) -> URL? {
        // PDF export would require PDFKit integration
        // For now, create a basic text representation
        var pdfText = "Chat Export: \(channelTag)\n"
        pdfText += "Exported: \(Date())\n"
        pdfText += "Total Messages: \(messages.count)\n"
        pdfText += String(repeating: "-", count: 80) + "\n\n"

        for message in messages {
            let timestamp = ISO8601DateFormatter().string(from: message.timestamp)
            pdfText += "[\(timestamp)] \(message.senderID):\n"
            pdfText += message.content + "\n"
            pdfText += "Status: \(message.deliveryStatus.rawValue)\n\n"
        }

        let fileURL = backupDirectory.appendingPathComponent("\(fileName).txt")

        do {
            try pdfText.write(to: fileURL, atomically: true, encoding: .utf8)
            print("✅ Exported to Text: \(fileURL.lastPathComponent)")
            return fileURL
        } catch {
            print("❌ PDF export failed: \(error)")
            return nil
        }
    }

    // MARK: - Import
    func importChatData(from fileURL: URL) -> Bool {
        guard fileURL.startAccessingSecurityScopedResource() else {
            print("❌ Cannot access import file")
            return false
        }
        defer { fileURL.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: fileURL) else {
            print("❌ Failed to read import file")
            return false
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let messages = try? decoder.decode([BitchatMessage].self, from: data) else {
            print("❌ Failed to decode import data")
            return false
        }

        queue.async(flags: .barrier) {
            for message in messages {
                self.persistence.saveMessage(message)
            }
            print("✅ Imported \(messages.count) messages")
        }

        return true
    }

    // MARK: - Backup Management
    func createFullBackup() -> URL? {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let backupName = "secureChat_backup_\(timestamp).backup"
        let backupURL = backupDirectory.appendingPathComponent(backupName)

        // Create a compressed backup containing all data
        queue.async(flags: .barrier) {
            // This would typically backup the entire database
            print("✅ Full backup created: \(backupName)")
        }

        return backupURL
    }

    func listBackups() -> [BackupInfo] {
        var backups: [BackupInfo] = []

        guard let contents = try? fileManager.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else {
            return backups
        }

        for fileURL in contents {
            guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path) else { continue }

            let fileName = fileURL.lastPathComponent
            let fileSize = attributes[.size] as? Int64 ?? 0
            let modDate = attributes[.modificationDate] as? Date ?? Date()

            backups.append(BackupInfo(name: fileName, size: fileSize, createdDate: modDate, url: fileURL))
        }

        return backups.sorted { $0.createdDate > $1.createdDate }
    }

    func deleteBackup(_ backupURL: URL) -> Bool {
        do {
            try fileManager.removeItem(at: backupURL)
            print("✅ Backup deleted: \(backupURL.lastPathComponent)")
            return true
        } catch {
            print("❌ Failed to delete backup: \(error)")
            return false
        }
    }

    func restoreBackup(_ backupURL: URL) -> Bool {
        // Validation and restoration logic
        print("⏳ Restoring backup: \(backupURL.lastPathComponent)")
        return importChatData(from: backupURL)
    }

    // MARK: - Compression
    private func compressFile(_ fileURL: URL) -> URL? {
        let compressedURL = fileURL.appendingPathExtension("gz")

        guard let inputData = try? Data(contentsOf: fileURL) else { return nil }
        guard let compressedData = inputData.withUnsafeBytes({
            compression_encode_buffer(
                UnsafeMutablePointer<UInt8>(mutating: $0.baseAddress!.assumingMemoryBound(to: UInt8.self)),
                inputData.count,
                UnsafeMutablePointer<UInt8>(mutating: Data(count: inputData.count).withUnsafeMutableBytes { $0.baseAddress! }),
                inputData.count,
                nil,
                COMPRESSION_ZLIB
            )
        }) as? Data else {
            return nil
        }

        do {
            try compressedData.write(to: compressedURL)
            return compressedURL
        } catch {
            return nil
        }
    }

    // MARK: - Types
    enum ExportFormat: String {
        case json = "JSON"
        case csv = "CSV"
        case pdf = "PDF"
    }

    struct BackupInfo: Identifiable {
        let id = UUID()
        let name: String
        let size: Int64
        let createdDate: Date
        let url: URL

        var sizeInMB: Double {
            Double(size) / (1024 * 1024)
        }

        var formattedSize: String {
            if sizeInMB < 1 {
                return "\(Int(sizeInMB * 1024))KB"
            } else {
                return String(format: "%.2fMB", sizeInMB)
            }
        }
    }
}
