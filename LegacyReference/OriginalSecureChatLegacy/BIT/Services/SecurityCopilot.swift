// SecureChat/BIT/Services/SecurityCopilot.swift

import Foundation

enum SecurityCopilot {

    static func explainQRCodeAndInvite() -> String {
        """
        QR-Invite transportiert nur die minimal notwendigen Metadaten, um einen Peer/Channel zu finden.
        Fuer Passwort-Channels wird der Channel-Key zusaetzlich eingewickelt (Passphrase Wrap), damit ein
        QR alleine nicht ausreicht. Danach gilt: Safety Number / Fingerprint pruefen.
        """
    }

    static func explainFingerprint() -> String {
        """
        Der Fingerprint (Safety Number) ist eine menschenpruefbare Darstellung der Identitaetsschluessel.
        Wenn er sich aendert, kann das ein Geraetewechsel sein - oder ein MITM. Bei Aenderung: neu verifizieren.
        """
    }

    static func explainBiometricLogin() -> String {
        """
        Face ID / Touch ID schuetzt lokal den Zugriff auf die App (Device-Protection). Es ersetzt keine E2E-Krypto,
        verhindert aber, dass jemand mit Zugriff auf dein entsperrtes Geraet deine Chats oeffnet.
        """
    }

    static func explainAutoRelock(seconds: Int) -> String {
        """
        Auto-Relock sperrt die App erneut, wenn sie laenger als \(seconds)s im Hintergrund war.
        Das reduziert Risiko bei App-Switch/Screen-Lock.
        """
    }

    static func maybeAlert(
        for event: SecurityInsightsStore.Event,
        scores: (global: Int, peer: [String:Int], channel: [String:Int], signals: Any)
    ) -> SecurityInsightsStore.Alert? {
        switch event.kind {
        case .decryptFailed:
            return .init(
                id: UUID(),
                date: Date(),
                severity: .warning,
                title: "Decrypt-Fehler",
                message: "Mehrere Decrypt-Fehler koennen auf Protokoll-Mismatch oder Manipulation hinweisen. Pruefe Fingerprint/Safety Number.",
                peerID: event.peerID,
                channel: event.channel
            )
        case .replayDropped:
            return .init(
                id: UUID(),
                date: Date(),
                severity: .warning,
                title: "Replay erkannt",
                message: "Die App hat ein wiederholtes Paket verworfen (Replay Protection). Bei Haeufung: Peer blockieren oder Channel neu erzeugen.",
                peerID: event.peerID,
                channel: event.channel
            )
        case .inviteRejected:
            return .init(
                id: UUID(),
                date: Date(),
                severity: .info,
                title: "Invite abgelehnt",
                message: "Invite wurde verworfen (z.B. Passphrase falsch oder Token bereits genutzt).",
                peerID: event.peerID,
                channel: event.channel
            )
        case .identityChanged:
            return .init(
                id: UUID(),
                date: Date(),
                severity: .critical,
                title: "Safety Number geaendert",
                message: "Identitaetsschluessel haben sich geaendert. Verifiziere den Fingerprint erneut, bevor du weiter schreibst.",
                peerID: event.peerID,
                channel: event.channel
            )
        default:
            // Global high risk hint (low-frequency): if global risk high and event related to messaging
            if scores.global >= 80, event.kind == .messageReceived || event.kind == .messageSent {
                return .init(
                    id: UUID(),
                    date: Date(),
                    severity: .warning,
                    title: "Auffaellige Aktivitaet",
                    message: "Ungewoehnlich hohe Aktivitaet (Flood/Replay/Fehler). Falls unklar: Channel wechseln und Fingerprints verifizieren.",
                    peerID: event.peerID,
                    channel: event.channel
                )
            }
            return nil
        }
    }
}
