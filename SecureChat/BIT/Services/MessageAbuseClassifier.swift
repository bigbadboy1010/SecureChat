// SecureChat/BIT/Services/MessageAbuseClassifier.swift

import Foundation

/// On-device, privacy-preserving abuse/spam classifier.
/// NOTE: Works on already-decrypted text locally. Nothing is sent off-device.
struct MessageAbuseClassifier {

    struct Verdict: Sendable {
        /// 0.0 .. 1.0
        let probability: Double
        let reasons: [String]

        var isLikelyAbuse: Bool { probability >= 0.85 }
        var isSuspicious: Bool { probability >= 0.65 }
    }

    static func classify(_ text: String) -> Verdict {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Verdict(probability: 0.0, reasons: [])
        }

        let length = trimmed.count
        let urlCount = countURLs(in: trimmed)
        let digitRatio = ratioOfDigits(in: trimmed)
        let upperRatio = ratioOfUppercase(in: trimmed)
        let repetition = repetitionScore(in: trimmed)
        let entropy = approximateEntropy(in: trimmed)

        // Heuristic "feature to score" mapping (deterministic, explainable)
        var score = 0.0
        var reasons: [String] = []

        if length > 400 {
            score += 0.12
            reasons.append("Sehr lange Nachricht")
        } else if length > 220 {
            score += 0.08
            reasons.append("Lange Nachricht")
        }

        if urlCount >= 2 {
            score += 0.22
            reasons.append("Mehrere Links")
        } else if urlCount == 1 {
            score += 0.12
            reasons.append("Link enthalten")
        }

        if digitRatio > 0.22 {
            score += 0.12
            reasons.append("Hoher Zahlenanteil")
        }

        if upperRatio > 0.55 && length > 20 {
            score += 0.10
            reasons.append("Viel GROSSSCHRIFT")
        }

        if repetition > 0.55 {
            score += 0.16
            reasons.append("Viele Wiederholungen")
        } else if repetition > 0.40 {
            score += 0.10
            reasons.append("Wiederholungsmuster")
        }

        if entropy < 2.3 && length > 40 {
            score += 0.10
            reasons.append("Niedrige Text-Entropie (Template/Spam)")
        }

        // Keyword hints (keine Sprachexplosion, nur wenige robuste Signale)
        let lower = trimmed.lowercased()
        let keywordHits = [
            "free", "gratis", "gewinn", "giveaway", "bitcoin", "crypto", "wallet",
            "click", "klick", "verify", "verifizieren", "passwort", "login", "konto", "bank",
            "airdrop", "investment", "invest", "bonus"
        ].filter { lower.contains($0) }.count
        if keywordHits >= 3 {
            score += 0.18
            reasons.append("Mehrere Scam/Phishing-Keywords")
        } else if keywordHits == 2 {
            score += 0.10
            reasons.append("Scam/Phishing-Keywords")
        } else if keywordHits == 1 {
            score += 0.05
            reasons.append("Verdächtiges Keyword")
        }

        // Clamp 0..1 with mild sigmoid for smoother behavior
        let p = sigmoid((score - 0.25) * 4.0)
        return Verdict(probability: p, reasons: reasons)
    }

    private static func sigmoid(_ x: Double) -> Double {
        1.0 / (1.0 + Foundation.exp(-x))
    }

    private static func countURLs(in s: String) -> Int {
        // Simple, fast heuristics for URLs; avoids heavy regex.
        let tokens = s.split(whereSeparator: { $0.isWhitespace || $0 == ")" || $0 == "(" || $0 == "[" || $0 == "]" || $0 == "," })
        var c = 0
        for tSub in tokens {
            let t = tSub.lowercased()
            if t.contains("http://") || t.contains("https://") || t.hasPrefix("www.") || t.contains(".com") || t.contains(".net") || t.contains(".ru") || t.contains(".io") || t.contains(".xyz") {
                c += 1
            }
        }
        return c
    }

    private static func ratioOfDigits(in s: String) -> Double {
        guard !s.isEmpty else { return 0 }
        let digits = s.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        return Double(digits) / Double(s.count)
    }

    private static func ratioOfUppercase(in s: String) -> Double {
        guard !s.isEmpty else { return 0 }
        let letters = s.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters > 0 else { return 0 }
        let upper = s.unicodeScalars.filter { CharacterSet.uppercaseLetters.contains($0) }.count
        return Double(upper) / Double(letters)
    }

    private static func repetitionScore(in s: String) -> Double {
        // Measures how much consecutive repetition occurs (e.g. "!!!!!!", "aaaaa", repeated bigrams)
        guard s.count >= 10 else { return 0 }
        let chars = Array(s)
        var repeats = 0
        for i in 1..<chars.count {
            if chars[i] == chars[i-1] { repeats += 1 }
        }
        let charRepeatRatio = Double(repeats) / Double(chars.count - 1)

        // Bigram repetition
        var bigrams: [String: Int] = [:]
        if chars.count >= 4 {
            for i in 0..<(chars.count-1) {
                let bg = String(chars[i]) + String(chars[i+1])
                bigrams[bg, default: 0] += 1
            }
        }
        let maxBg = bigrams.values.max() ?? 1
        let bgRatio = Double(maxBg) / Double(max(1, chars.count-1))

        return max(charRepeatRatio, bgRatio)
    }

    private static func approximateEntropy(in s: String) -> Double {
        // Shannon entropy over characters (approx)
        guard !s.isEmpty else { return 0 }
        var freq: [Character: Int] = [:]
        for ch in s {
            freq[ch, default: 0] += 1
        }
        let n = Double(s.count)
        var h = 0.0
        for (_, f) in freq {
            let p = Double(f) / n
            h -= p * Foundation.log2(p)
        }
        return h
    }
}
