import Foundation

/// Agreed limits of the hosted relay; ciphertext includes the 28-byte GCM overhead.
enum RelayWireCoding {
    static let maximumHTTPBodyBytes = 256 * 1_024
    static let maximumSealedPayloadBytes = 128 * 1_024
    // Forty maximally sized Base64 envelopes fit the 8 MiB response reader.
    static let maximumInboxBatch = 40

    static func makeEncoder() -> JSONEncoder {
        let encoder = DateCoding.makeEncoder()
        encoder.outputFormatting.insert(.withoutEscapingSlashes)
        return encoder
    }

    static func hasUnsupportedTextControls(_ value: String) -> Bool {
        value.unicodeScalars.contains { $0.value < 32 && ![9, 10, 13].contains($0.value) }
    }
}
