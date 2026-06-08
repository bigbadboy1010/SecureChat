// SecureChat/BIT/Services/SecurityInsightsStore.swift

import Foundation
import Combine

/// Lightweight "AI-like" security analytics that operates on metadata only.
@MainActor
final class SecurityInsightsStore: ObservableObject {
    static let shared = SecurityInsightsStore()

    struct Event: Identifiable, Codable, Sendable {
        enum Kind: String, Codable, Sendable {
            case messageSent
            case messageReceived
            case decryptFailed
            case replayDropped
            case inviteRejected
            case identityChanged
            case rateLimited
        }

        let id: UUID
        let date: Date
        let kind: Kind
        let peerID: String?
        let channel: String?
        let detail: String?

        init(kind: Kind, peerID: String? = nil, channel: String? = nil, detail: String? = nil, date: Date = Date()) {
            self.id = UUID()
            self.date = date
            self.kind = kind
            self.peerID = peerID
            self.channel = channel
            self.detail = detail
        }
    }

    struct Alert: Identifiable, Codable, Sendable {
        enum Severity: String, Codable, Sendable { case info, warning, critical }
        let id: UUID
        let date: Date
        let severity: Severity
        let title: String
        let message: String
        let peerID: String?
        let channel: String?
    }

    @Published private(set) var recentEvents: [Event] = []
    @Published private(set) var recentAlerts: [Alert] = []

    /// 0..100, higher means more suspicious activity recently.
    @Published private(set) var globalRiskScore: Int = 0
    @Published private(set) var peerRisk: [String: Int] = [:]
    @Published private(set) var channelRisk: [String: Int] = [:]

    @Published var enableInsights: Bool = true

    private let maxEvents = 200
    private let maxAlerts = 50

    private var counters: WindowCounters = .init()
    private var timerCancellable: AnyCancellable?

    private init() {
        timerCancellable = Timer.publish(every: 3.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.decay() }
    }

    func record(_ event: Event) {
        guard enableInsights else { return }

        recentEvents.append(event)
        if recentEvents.count > maxEvents {
            recentEvents.removeFirst(recentEvents.count - maxEvents)
        }

        counters.ingest(event)
        let updates = counters.computeScores()

        globalRiskScore = updates.global
        peerRisk = updates.peer
        channelRisk = updates.channel

        if let alert = SecurityCopilot.maybeAlert(for: event, scores: updates) {
            pushAlert(alert)
        }
    }

    func clearAlerts() {
        recentAlerts.removeAll()
    }

    func clearEvents() {
        recentEvents.removeAll()
        counters = .init()
        globalRiskScore = 0
        peerRisk = [:]
        channelRisk = [:]
    }

    private func pushAlert(_ alert: Alert) {
        recentAlerts.insert(alert, at: 0)
        if recentAlerts.count > maxAlerts {
            recentAlerts.removeLast(recentAlerts.count - maxAlerts)
        }
    }

    private func decay() {
        guard enableInsights else { return }
        counters.decay()
        let updates = counters.computeScores()
        globalRiskScore = updates.global
        peerRisk = updates.peer
        channelRisk = updates.channel
    }

    // MARK: - Internal scoring

    private struct WindowCounters {
        private var global: DecayCounter = .init(halfLifeSeconds: 20)
        private var peers: [String: DecayCounter] = [:]
        private var channels: [String: DecayCounter] = [:]

        private var decryptFail: DecayCounter = .init(halfLifeSeconds: 45)
        private var replayDrop: DecayCounter = .init(halfLifeSeconds: 30)
        private var inviteReject: DecayCounter = .init(halfLifeSeconds: 60)

        mutating func ingest(_ event: Event) {
            global.bump()

            if let p = event.peerID {
                if peers[p] == nil { peers[p] = .init(halfLifeSeconds: 25) }
                peers[p]?.bump()
            }
            if let c = event.channel {
                if channels[c] == nil { channels[c] = .init(halfLifeSeconds: 25) }
                channels[c]?.bump()
            }

            switch event.kind {
            case .decryptFailed:
                decryptFail.bump(weight: 1.5)
            case .replayDropped:
                replayDrop.bump(weight: 1.25)
            case .inviteRejected:
                inviteReject.bump(weight: 1.0)
            case .rateLimited:
                global.bump(weight: 0.75)
            default:
                break
            }
        }

        mutating func decay() {
            global.decay()
            decryptFail.decay()
            replayDrop.decay()
            inviteReject.decay()

            peers = peers.filter { $0.value.value > 0.05 }
            channels = channels.filter { $0.value.value > 0.05 }
            for k in peers.keys { peers[k]?.decay() }
            for k in channels.keys { channels[k]?.decay() }
        }

        struct Signals: Sendable {
            let msgRate: Double
            let decryptFail: Double
            let replayDrop: Double
            let inviteReject: Double
        }

        func computeScores() -> (global: Int, peer: [String: Int], channel: [String: Int], signals: Signals) {
            let signals = Signals(
                msgRate: global.value,
                decryptFail: decryptFail.value,
                replayDrop: replayDrop.value,
                inviteReject: inviteReject.value
            )

            func score(from v: Double, scale: Double) -> Int {
                let s = 100.0 * (1.0 - exp(-max(0, v) / scale))
                return max(0, min(100, Int(round(s))))
            }

            let globalRisk = score(
                from: signals.msgRate * 0.9 + signals.decryptFail * 1.8 + signals.replayDrop * 1.4 + signals.inviteReject * 0.8,
                scale: 6.0
            )

            var peerRisk: [String: Int] = [:]
            for (k,c) in peers {
                peerRisk[k] = score(from: c.value, scale: 4.0)
            }

            var channelRisk: [String: Int] = [:]
            for (k,c) in channels {
                channelRisk[k] = score(from: c.value, scale: 4.0)
            }

            return (globalRisk, peerRisk, channelRisk, signals)
        }

        struct DecayCounter {
            let halfLifeSeconds: Double
            private(set) var value: Double = 0
            private var lastUpdate: TimeInterval = Date().timeIntervalSince1970

            init(halfLifeSeconds: Double) {
                self.halfLifeSeconds = max(1.0, halfLifeSeconds)
            }

            mutating func bump(weight: Double = 1.0) {
                decay()
                value += max(0.0, weight)
            }

            mutating func decay() {
                let now = Date().timeIntervalSince1970
                let dt = max(0.0, now - lastUpdate)
                lastUpdate = now
                if value <= 0 { return }
                let lambda = log(2.0) / halfLifeSeconds
                value = value * exp(-lambda * dt)
            }
        }
    }
}
