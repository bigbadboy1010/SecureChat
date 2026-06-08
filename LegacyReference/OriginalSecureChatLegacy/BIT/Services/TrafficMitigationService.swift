// SecureChat/BIT/Services/TrafficMitigationService.swift

import Foundation
import Combine

/// Adaptive rate-limits and auto-quarantine based on metadata + local abuse classifier.
/// - No network calls
/// - No content export
final class TrafficMitigationService: ObservableObject {
    static let shared = TrafficMitigationService()

    @Published var enableMitigation: Bool {
        didSet { UserDefaults.standard.set(enableMitigation, forKey: Keys.enableMitigation) }
    }
    @Published var enableSpamFilter: Bool {
        didSet { UserDefaults.standard.set(enableSpamFilter, forKey: Keys.enableSpamFilter) }
    }
    @Published var enableAutoQuarantine: Bool {
        didSet { UserDefaults.standard.set(enableAutoQuarantine, forKey: Keys.enableAutoQuarantine) }
    }

    /// messages per minute per peer (incoming)
    @Published var incomingPeerLimitPerMinute: Int {
        didSet { UserDefaults.standard.set(incomingPeerLimitPerMinute, forKey: Keys.incomingPeerLimitPerMinute) }
    }

    /// burst limit for rapid sends in a short window
    @Published var burstLimit10s: Int {
        didSet { UserDefaults.standard.set(burstLimit10s, forKey: Keys.burstLimit10s) }
    }

    /// Comma-separated trusted peer IDs (bypass filters/limits)
    @Published var trustedPeersCsv: String {
        didSet { UserDefaults.standard.set(trustedPeersCsv, forKey: Keys.trustedPeersCsv) }
    }

    /// quarantine duration in seconds
    @Published var persistQuarantine: Bool {
        didSet {
            UserDefaults.standard.set(persistQuarantine, forKey: Keys.persistQuarantine)
            if persistQuarantine {
                persistQuarantineState()
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.persistQuarantine)
                UserDefaults.standard.removeObject(forKey: "bit.quarantineMapV1")
            }
        }
    }

    @Published var quarantineSeconds: Int {
        didSet { UserDefaults.standard.set(quarantineSeconds, forKey: Keys.quarantineSeconds) }
    }

    private struct Keys {
        static let enableMitigation = "bit.aiMitigationV1"
        static let enableSpamFilter = "bit.aiSpamFilterV1"
        static let enableAutoQuarantine = "bit.aiAutoQuarantineV1"
        static let incomingPeerLimitPerMinute = "bit.aiIncomingPeerLimitPerMinuteV1"
        static let burstLimit10s = "bit.aiBurstLimit10sV1"
        static let quarantineSeconds = "bit.aiQuarantineSecondsV1"
        static let trustedPeersCsv = "bit.trustedPeersV1"
        static let persistQuarantine = "bit.persistQuarantineV1"
    }

    private struct Bucket {
        var tokens: Double
        var lastRefill: Date
        let capacity: Double
        let refillPerSecond: Double

        mutating func allow(now: Date, cost: Double = 1.0) -> Bool {
            refill(now: now)
            if tokens >= cost {
                tokens -= cost
                return true
            }
            return false
        }

        mutating func refill(now: Date) {
            let dt = max(0.0, now.timeIntervalSince(lastRefill))
            if dt > 0 {
                tokens = min(capacity, tokens + dt * refillPerSecond)
                lastRefill = now
            }
        }
    }

    private var peerMinuteBuckets: [String: Bucket] = [:]
    private var peerBurstBuckets: [String: Bucket] = [:]

private let quarantineMapKey = "bit.quarantineMapV1"

private func trustedPeerSet() -> Set<String> {
    let parts = trustedPeersCsv
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    return Set(parts)
}

private func persistQuarantineState() {
    guard persistQuarantine else { return }
    lock.lock()
    let snapshot = quarantinedPeers.mapValues { $0.timeIntervalSince1970 }
    lock.unlock()
    if let data = try? JSONSerialization.data(withJSONObject: snapshot, options: []) {
        UserDefaults.standard.set(data, forKey: quarantineMapKey)
    }
}

private func restoreQuarantineState() {
    guard let data = UserDefaults.standard.data(forKey: quarantineMapKey),
          let obj = try? JSONSerialization.jsonObject(with: data, options: []),
          let map = obj as? [String: Double] else { return }
    let now = Date()
    lock.lock()
    quarantinedPeers.removeAll()
    for (k, ts) in map {
        let until = Date(timeIntervalSince1970: ts)
        if until > now {
            quarantinedPeers[k] = until
        }
    }
    lock.unlock()
}

    private var quarantinedPeers: [String: Date] = [:]

    private let lock = NSLock()

    private init() {
        let ud = UserDefaults.standard
        self.enableMitigation = ud.object(forKey: Keys.enableMitigation) as? Bool ?? true
        self.enableSpamFilter = ud.object(forKey: Keys.enableSpamFilter) as? Bool ?? true
        self.enableAutoQuarantine = ud.object(forKey: Keys.enableAutoQuarantine) as? Bool ?? true
        self.incomingPeerLimitPerMinute = ud.object(forKey: Keys.incomingPeerLimitPerMinute) as? Int ?? 60
        self.burstLimit10s = ud.object(forKey: Keys.burstLimit10s) as? Int ?? 12
        self.quarantineSeconds = ud.object(forKey: Keys.quarantineSeconds) as? Int ?? 600
        self.trustedPeersCsv = ud.object(forKey: Keys.trustedPeersCsv) as? String ?? ""
        self.persistQuarantine = ud.object(forKey: Keys.persistQuarantine) as? Bool ?? true

        if self.persistQuarantine {
            restoreQuarantineState()
        }
    }

    func isPeerQuarantined(_ peerID: String, now: Date = Date()) -> Bool {
        if trustedPeerSet().contains(peerID) { return false }
        lock.lock(); defer { lock.unlock() }
        guard let until = quarantinedPeers[peerID] else { return false }
        if now <= until { return true }
        quarantinedPeers.removeValue(forKey: peerID)
        persistQuarantineState()
        return false
    }

    func quarantinePeer(_ peerID: String, reason: String) {
        guard enableMitigation && enableAutoQuarantine else { return }
        let until = Date().addingTimeInterval(TimeInterval(max(30, quarantineSeconds)))
        lock.lock()
        quarantinedPeers[peerID] = until
        lock.unlock()
        persistQuarantineState()

        SecurityInsightsStore.shared.record(.init(kind: .rateLimited, peerID: peerID, channel: nil, detail: "quarantine:\(reason)"))
    }

    /// Returns false if the incoming message should be dropped due to rate-limits / quarantine.
    func allowIncoming(peerID: String, now: Date = Date()) -> Bool {
        if trustedPeerSet().contains(peerID) { return true }
        guard enableMitigation else { return true }
        if isPeerQuarantined(peerID, now: now) {
            SecurityInsightsStore.shared.record(.init(kind: .rateLimited, peerID: peerID, channel: nil, detail: "quarantined"))
            return false
        }

        lock.lock()
        defer { lock.unlock() }

        // Per-minute bucket
        let perMinute = max(10, incomingPeerLimitPerMinute)
        let refillPerSecond = Double(perMinute) / 60.0
        if peerMinuteBuckets[peerID] == nil {
            peerMinuteBuckets[peerID] = Bucket(tokens: Double(perMinute), lastRefill: now, capacity: Double(perMinute), refillPerSecond: refillPerSecond)
        }
        var minuteBucket = peerMinuteBuckets[peerID]!
        let minuteOk = minuteBucket.allow(now: now)
        peerMinuteBuckets[peerID] = minuteBucket
        if !minuteOk {
            SecurityInsightsStore.shared.record(.init(kind: .rateLimited, peerID: peerID, channel: nil, detail: "rate/min"))
            return false
        }

        // Burst bucket (10 seconds)
        let burst = max(4, burstLimit10s)
        let burstRefillPerSecond = Double(burst) / 10.0
        if peerBurstBuckets[peerID] == nil {
            peerBurstBuckets[peerID] = Bucket(tokens: Double(burst), lastRefill: now, capacity: Double(burst), refillPerSecond: burstRefillPerSecond)
        }
        var burstBucket = peerBurstBuckets[peerID]!
        let burstOk = burstBucket.allow(now: now)
        peerBurstBuckets[peerID] = burstBucket
        if !burstOk {
            SecurityInsightsStore.shared.record(.init(kind: .rateLimited, peerID: peerID, channel: nil, detail: "burst/10s"))
            return false
        }

        return true
    }

    struct ContentDecision: Sendable {
        enum Action: Sendable { case allow, warn, drop, quarantine }
        let action: Action
        let probability: Double
        let reasons: [String]
    }

    /// Classify decrypted content locally. Never called on encrypted payload.
    func evaluateDecryptedContent(_ text: String, peerID: String, channel: String?) -> ContentDecision {
        if trustedPeerSet().contains(peerID) { return .init(action: .allow, probability: 0, reasons: []) }
        guard enableSpamFilter else { return .init(action: .allow, probability: 0, reasons: []) }

        let verdict = MessageAbuseClassifier.classify(text)
        if verdict.isLikelyAbuse {
            SecurityInsightsStore.shared.record(.init(kind: .decryptFailed, peerID: peerID, channel: channel, detail: "abuse:\(String(format: "%.2f", verdict.probability))"))
            if enableAutoQuarantine {
                quarantinePeer(peerID, reason: "abuse:\(String(format: "%.2f", verdict.probability))")
                return .init(action: .quarantine, probability: verdict.probability, reasons: verdict.reasons)
            }
            return .init(action: .drop, probability: verdict.probability, reasons: verdict.reasons)
        }
        if verdict.isSuspicious {
            return .init(action: .warn, probability: verdict.probability, reasons: verdict.reasons)
        }
        return .init(action: .allow, probability: verdict.probability, reasons: verdict.reasons)
    }
}
