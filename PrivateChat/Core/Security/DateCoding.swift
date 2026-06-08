import Foundation

enum DateCoding {
    static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func makeEncoder(sortedKeys: Bool = true) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if sortedKeys {
            encoder.outputFormatting = [.sortedKeys]
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let stringValue = try? container.decode(String.self),
               let date = iso8601Formatter.date(from: stringValue) {
                return date
            }
            if let doubleValue = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: doubleValue)
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format")
        }
        return decoder
    }

    static func string(from date: Date) -> String {
        iso8601Formatter.string(from: date)
    }
}
