// SecureChat/BIT/Services/UserVisibleSecurityBanner.swift

import Foundation
import Combine

@MainActor
final class UserVisibleSecurityBanner: ObservableObject {
    static let shared = UserVisibleSecurityBanner()

    struct Banner: Identifiable, Sendable {
        let id = UUID()
        let title: String
        let message: String
        let date: Date
    }

    @Published var current: Banner? = nil

    private init() {}

    func show(title: String, message: String) {
        current = Banner(title: title, message: message, date: Date())
        // Auto-dismiss after 4s
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if let c = current, Date().timeIntervalSince(c.date) >= 3.8 {
                current = nil
            }
        }
    }

    func clear() {
        current = nil
    }
}
