# PrivateChat Phase 12 – Security Sentinel & Crypto-Agility Roadmap

Phase 12 adds a local security-assessment layer without changing the existing end-to-end message format, relay protocol, or crypto payload format.

## Added

- Local Security Sentinel score in `Security → Phase 12 Security Sentinel`.
- Dedicated `SecuritySentinelView` with score, risk level, findings, and recommendations.
- Dashboard card for Security Sentinel score and top finding.
- Diagnostic report now includes Security Sentinel summary and finding count.
- Local rule-based risk scoring over:
  - Runtime hardening state.
  - Relay token and HTTPS readiness.
  - Relay connectivity/backoff state.
  - Privacy settings.
  - Biometric unlock setting.
  - Verified contact state.
  - Failed outbox messages.
  - Relay stats.
- Crypto-agility roadmap section inside the Security Sentinel screen.

## Security model

The Sentinel does **not** inspect chat plaintext and does **not** call an external AI service. It is intentionally local and deterministic, so it can be used in a privacy-critical messenger without leaking sensitive data.

## Not changed

- No new relay protocol.
- No new message payload format.
- No new cryptographic wire format.
- No CoreML model bundled yet.

## Why not a cloud AI model?

A cloud model must never receive private keys, tokens, chat plaintext, safety numbers, or decrypted message metadata. Phase 12 therefore implements a local Sentinel first. A later CoreML model can be added for anomaly detection, but only over sanitized technical counters.
