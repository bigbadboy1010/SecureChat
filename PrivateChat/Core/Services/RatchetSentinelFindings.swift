import Foundation

/// Privacy-Sentinel findings for v2 / v1 envelope
/// routing. The `ConversationService` collects
/// `RatchetSentinelObservation` rows from
/// `RatchetEnvelopeRouter` calls and passes them
/// to `RatchetSentinelFindings.build(...)`, which
/// turns the observations into a list of
/// `SecurityAIFinding`s the sentinel can surface
/// in the in-app dashboard.
///
/// The findings are **advisory** for Sprint 9C:
/// they are logged in `/healthz/internal` and
/// shown in the Privacy Sentinel view, but the
/// v1 envelope continues to work and the public
/// beta envelope (ADR-002) is not yet affected.
/// Sprint 10 will let the user trigger a
/// "re-pair on v2" action from the finding
/// detail.
enum RatchetSentinelFindings {

    /// Build a list of `SecurityAIFinding`s for
    /// the most recent batch of
    /// `RatchetSentinelObservation`s. The output
    /// always includes the "v1 fallback" finding
    /// when **any** observation has `isV2 ==
    /// false`; it is collapsed into a single
    /// finding (one warning, not N) so the
    /// dashboard does not spam.
    static func build(
        observations: [RatchetSentinelObservation],
        generatedAt: Date = Date()
    ) -> [SecurityAIFinding] {
        guard !observations.isEmpty else {
            return []
        }
        let v1PeerIDs = observations
            .filter { $0.isV2 == false }
            .map { $0.peerID }
        let v2PeerIDs = observations
            .filter { $0.isV2 }
            .map { $0.peerID }
        var findings: [SecurityAIFinding] = []
        if v1PeerIDs.isEmpty == false {
            let listed = v1PeerIDs.sorted().joined(separator: ", ")
            findings.append(
                SecurityAIFinding(
                    title: "Sitzung noch auf v1-Envelope",
                    detail:
                        "Eine oder mehrere Konversationen laufen noch auf dem v1-Envelope (Curve25519+ECDH+AES-GCM, ADR-002). Betroffen: \(listed).",
                    severity: .warning,
                    recommendation:
                        "Beim nächsten Pairing wird automatisch der v2-Double-Ratchet-Envelope registriert. Für bestehende v1-Sitzungen in Sprint 10 eine »Auf v2 aktualisieren«-Aktion aus dem Dashboard auslösen."
                )
            )
        }
        if v2PeerIDs.isEmpty == false {
            let listed = v2PeerIDs.sorted().joined(separator: ", ")
            findings.append(
                SecurityAIFinding(
                    title: "Sitzung auf v2-Envelope (Double Ratchet)",
                    detail:
                        "Diese Konversationen nutzen bereits den v2-Envelope mit X3DH-Initial-Bundle und Double Ratchet (post-compromise security). Konversationen: \(listed).",
                    severity: .info,
                    recommendation:
                        "Keine Aktion notwendig. Vorhandene Schlüsselhistorie wird in der iOS-Keychain persistiert."
                )
            )
        }
        return findings
    }
}
