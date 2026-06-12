import Foundation

enum SecurityAIRiskLevel: String, Codable, Equatable, CaseIterable {
    case optimal
    case guarded
    case elevated
    case critical

    var localizedTitle: String {
        switch self {
        case .optimal:
            return "Optimal"
        case .guarded:
            return "Gehärtet"
        case .elevated:
            return "Erhöht"
        case .critical:
            return "Kritisch"
        }
    }
}

struct SecurityAIFinding: Identifiable, Codable, Equatable {
    enum Severity: String, Codable, Equatable, CaseIterable {
        case info
        case warning
        case high
        case critical

        var localizedTitle: String {
            switch self {
            case .info:
                return "Info"
            case .warning:
                return "Warnung"
            case .high:
                return "Hoch"
            case .critical:
                return "Kritisch"
            }
        }
    }

    let id: UUID
    let title: String
    let detail: String
    let severity: Severity
    let recommendation: String

    init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        severity: Severity,
        recommendation: String
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.severity = severity
        self.recommendation = recommendation
    }
}

struct SecurityAISnapshot: Equatable {
    let score: Int
    let riskLevel: SecurityAIRiskLevel
    let summary: String
    let findings: [SecurityAIFinding]
    let generatedAt: Date

    static let empty = SecurityAISnapshot(
        score: 0,
        riskLevel: .elevated,
        summary: "Security Sentinel noch nicht ausgeführt.",
        findings: [],
        generatedAt: Date(timeIntervalSince1970: 0)
    )

    var topFindings: [SecurityAIFinding] {
        findings.sorted { lhs, rhs in
            severityRank(lhs.severity) > severityRank(rhs.severity)
        }
    }

    private func severityRank(_ severity: SecurityAIFinding.Severity) -> Int {
        switch severity {
        case .critical:
            return 4
        case .high:
            return 3
        case .warning:
            return 2
        case .info:
            return 1
        }
    }
}

enum SecurityAISentinel {
    static func assess(
        securityState: AppSecurityState,
        runtimeSnapshot: RuntimeSecuritySnapshot,
        relayConnectivityStatus: RelayConnectivityStatus,
        conversations: [StoredConversation],
        trustedPeers: [TrustedPeer],
        relayStats: RelayStatsSnapshot?,
        localIdentityID: String
    ) -> SecurityAISnapshot {
        var score = 100
        var findings: [SecurityAIFinding] = []

        func add(_ severity: SecurityAIFinding.Severity, _ title: String, _ detail: String, _ recommendation: String, penalty: Int) {
            score -= penalty
            findings.append(
                SecurityAIFinding(
                    title: title,
                    detail: detail,
                    severity: severity,
                    recommendation: recommendation
                )
            )
        }

        switch runtimeSnapshot.riskLevel {
        case .normal:
            findings.append(SecurityAIFinding(title: "Runtime sauber", detail: "Keine kritischen Debugger-, Jailbreak- oder Injection-Indikatoren erkannt.", severity: .info, recommendation: "Regelmäßig neu prüfen, besonders vor Release-Builds."))
        case .development:
            add(.info, "Development-Runtime", "Debug-/Simulator-/Mac-Testumgebung erkannt. Das ist bei Xcode-Tests erwartbar und wird nicht als kompromittierte Production bewertet.", "Für echte Sicherheitsbewertung einen Release/TestFlight-Build auf physischem iPhone testen.", penalty: 1)
        case .elevated:
            add(.high, "Erhöhtes Runtime-Risiko", runtimeSnapshot.localizedSummary, "Debugger/Jailbreak/Injection-Indikatoren prüfen und Relay-Blockierung aktivieren.", penalty: 18)
        case .compromised:
            add(.critical, "Kompromittierte Runtime", runtimeSnapshot.localizedSummary, "Relay-Transport blockieren, lokale Schlüssel nicht exportieren und Gerät nicht als vertrauenswürdig behandeln.", penalty: 35)
        }

        if securityState.transportMode == .relayAllowed {
            let trimmedURL = securityState.relayConfiguration.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasToken = securityState.relayConfiguration.registrationToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            let usesProductionRelay = SecureChatProductionProfile.isConfiguredProductionRelay(trimmedURL)
            let usesPublicHTTPS = SecureChatProductionProfile.isHTTPSProductionCandidate(trimmedURL)

            if usesProductionRelay && hasToken {
                findings.append(SecurityAIFinding(title: "Production Relay konfiguriert", detail: "Die App nutzt https://chatsecure.ddns.net mit gesetztem RELAY_AUTH_TOKEN.", severity: .info, recommendation: "In der App regelmäßig Relay prüfen und bei Tokenwechsel nur RELAY_AUTH_TOKEN aktualisieren."))
            }

            if SecureChatProductionProfile.isObsoleteLocalRelay(trimmedURL) {
                add(.high, "Alte LAN-Relay-URL gespeichert", "Die App hat noch eine lokale Relay-Adresse aus der Entwicklungsphase gespeichert.", "Production Relay aktivieren: https://chatsecure.ddns.net und RELAY_AUTH_TOKEN setzen.", penalty: 14)
            }

            if hasToken == false {
                add(.high, "Relay ohne Token", "Der Relay-Transport ist erlaubt, aber kein Bearer-Token ist gesetzt.", "Für Production RELAY_AUTH_TOKEN setzen und dasselbe Token in der App eintragen.", penalty: 14)
            }

            if trimmedURL.hasPrefix("http://") && isLikelyProductionRelay(trimmedURL) {
                add(.high, "Relay ohne HTTPS", "Die Relay-URL nutzt HTTP außerhalb typischer lokaler Testadressen.", "Production nur mit HTTPS/Caddy oder vergleichbarem Reverse Proxy betreiben.", penalty: 16)
            } else if trimmedURL.hasPrefix("http://") {
                add(.warning, "Lokaler HTTP-Relay", "HTTP ist für lokale Entwicklung ok, aber nicht für öffentliche Production.", "Für externe Nutzung HTTPS erzwingen oder die Production-Vorlage https://chatsecure.ddns.net übernehmen.", penalty: 4)
            } else if usesPublicHTTPS == false && trimmedURL.isEmpty == false {
                add(.warning, "Relay-URL nicht als Production erkannt", "Die Relay-URL ist gesetzt, entspricht aber nicht dem hinterlegten Production-Profil.", "Für den aktuellen Server https://chatsecure.ddns.net verwenden oder die Production-Readiness bewusst manuell prüfen.", penalty: 3)
            }
        } else {
            findings.append(SecurityAIFinding(title: "Relay nicht aktiv", detail: "Transport läuft lokal oder ist deaktiviert.", severity: .info, recommendation: "Für Mehrgerätebetrieb Relay bewusst aktivieren und absichern."))
        }

        if securityState.requireBiometricUnlock == false {
            add(.high, "Biometrie deaktiviert", "PrivateChat kann ohne biometrische Entsperrung geöffnet werden.", "Biometrische Entsperrung aktivieren.", penalty: 12)
        }

        if securityState.hideMessagePreviews == false {
            add(.warning, "Vorschau sichtbar", "Nachrichteninhalte können in Listen sichtbar sein.", "Vorschau-Schutz aktivieren, wenn Shoulder-Surfing oder Screenshots relevant sind.", penalty: 4)
        }

        if securityState.reduceKeyboardSuggestions == false {
            add(.warning, "Keyboard-Schutz aus", "Autokorrektur und TextInput-Funktionen können zusätzliche Systemaktivität erzeugen.", "Keyboard-Vorschläge reduzieren aktivieren.", penalty: 4)
        }

        if securityState.restrictRelayOnRuntimeRisk == false {
            if runtimeSnapshot.isProductionLikeRuntime {
                add(.high, "Relay-Block bei Production-Risiko aus", "Kritische Runtime-Risiken blockieren den Relay-Transport nicht automatisch.", "Relay bei kritischem Runtime-Risiko blockieren aktivieren.", penalty: 10)
            } else {
                add(.warning, "Relay-Block im Dev-Modus optional", "Der automatische Relay-Block ist aus. Im Xcode-/Debug-Testbetrieb ist das nachvollziehbar, für Production sollte er aktiviert werden.", "Vor TestFlight/AppStore aktivieren und auf echter iPhone-Hardware prüfen.", penalty: 3)
            }
        }

        switch relayConnectivityStatus.state {
        case .healthy:
            findings.append(SecurityAIFinding(title: "Relay-Verbindung stabil", detail: "Kein aktiver Backoff oder Fehlerstatus.", severity: .info, recommendation: "Keine Aktion notwendig."))
        case .degraded:
            add(.warning, "Relay instabil", relayConnectivityStatus.lastErrorMessage ?? "Letzter Relay-Fehler ist unbekannt.", "Netzwerk, VPN/utun, Firewall und Relay-Prozess prüfen.", penalty: 8)
        case .paused:
            add(.warning, "Relay im Backoff", relayConnectivityStatus.lastErrorMessage ?? "Auto-Sync wurde nach Fehlern pausiert.", "Health-Check ausführen oder Backoff zurücksetzen, sobald der Relay erreichbar ist.", penalty: 8)
        }

        let verifiedPeerCount = trustedPeers.filter { $0.trustState == .verified }.count
        if verifiedPeerCount == 0 {
            add(.warning, "Keine verifizierten Kontakte", "Es gibt noch keinen verifizierten Peer.", "Mindestens einen Kontakt per QR/Safety-Number verifizieren.", penalty: 6)
        }

        let failedMessages = conversations.reduce(0) { partial, stored in
            partial + stored.messages.filter { $0.status == .failed }.count
        }
        if failedMessages > 0 {
            add(.warning, "Fehlgeschlagene Nachrichten", "Es gibt \(failedMessages) fehlgeschlagene Nachricht(en).", "Outbox erneut senden oder Relay-Status prüfen.", penalty: min(10, failedMessages * 2))
        }

        if let relayStats, relayStats.storedPackets > 100 {
            add(.warning, "Viele Relay-Pakete", "Der Relay hält \(relayStats.storedPackets) Paket(e) vor.", "Inbox abrufen, ACKs prüfen oder Relay-Inbox gezielt bereinigen.", penalty: 5)
        }

        if localIdentityID.count < 32 {
            add(.high, "Kurze lokale Identität", "Die lokale Identity-ID wirkt unerwartet kurz.", "Identity-Erzeugung prüfen und keine produktive Kommunikation starten.", penalty: 15)
        }

        score = max(0, min(score, 100))
        let level: SecurityAIRiskLevel
        switch score {
        case 90...100:
            level = .optimal
        case 75..<90:
            level = .guarded
        case 50..<75:
            level = .elevated
        default:
            level = .critical
        }

        let hardFindingCount = findings.filter { $0.severity == .critical || $0.severity == .high }.count
        let mode = runtimeSnapshot.isDevelopmentRuntime ? "Development-Bewertung" : "Production-Bewertung"
        let summary = "Security Sentinel Score \(score)/100 – \(level.localizedTitle). \(mode), \(hardFindingCount) harte Finding(s)."
        return SecurityAISnapshot(score: score, riskLevel: level, summary: summary, findings: findings, generatedAt: Date())
    }

    private static func isLikelyProductionRelay(_ urlString: String) -> Bool {
        SecureChatProductionProfile.isLocalOrPrivateRelay(urlString) == false
    }
}
