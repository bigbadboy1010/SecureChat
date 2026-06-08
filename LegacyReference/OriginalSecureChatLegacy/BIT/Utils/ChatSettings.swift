//
// ChatSettings.swift
// schat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation

enum BandwidthMode: String, CaseIterable, Codable {
    case low
    case normal
    case high

    var displayName: String {
        switch self {
        case .low: return "Low Power"
        case .normal: return "Normal"
        case .high: return "High Throughput"
        }
    }
}

struct ChatSettings: Codable {
    var bandwidthMode: BandwidthMode
    var storeAndForwardEnabled: Bool
    var deliveryReceiptsEnabled: Bool
    var readReceiptsEnabled: Bool

    static let defaults = ChatSettings(
        bandwidthMode: .normal,
        storeAndForwardEnabled: true,
        deliveryReceiptsEnabled: true,
        readReceiptsEnabled: true
    )

    private static let key = "schat.settings.v1"

    static func load() -> ChatSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(ChatSettings.self, from: data) else {
            return .defaults
        }
        return decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
