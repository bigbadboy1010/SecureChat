# ADR-004: On-device Security Sentinel

## Status

Accepted (Sprint 6, 2026-06-22)

## Context

SecureChat is a privacy-first messenger that runs on iOS. Before a
user can confidently use it for sensitive communication, they need
a way to see — at a glance — whether the device they're using is
in a state that matches SecureChat's threat model:

- Is the runtime clean, or are we in a Debugger / Jailbreak /
  Injection scenario?
- Is the relay configuration sane (HTTPS, production relay, valid
  token), or is it pointing at a leftover dev host or running over
  plain HTTP?
- Are there any failed messages, degraded relay backoff, or a
  suspicious number of stored packets on the relay?
- Have any of the user's safety-relevant settings drifted away from
  the recommended posture (biometric unlock, preview hiding,
  keyboard suggestions, automatic relay blocking on production
  risk)?
- Is the local identity at the expected length, or did something
  collapse it to a stub?

In Sprint 12 (PHASE 12) we added a manual checklist in
`ProductionReadinessView`. The team, the beta-testers, and the
public-beta announcement page kept asking for **one number that
says "is your device SecureChat-ready right now"**, plus a list of
the things that pull that number down.

## Decision

We add an **on-device Security Sentinel** as a deterministic,
local-only assessment layer. It is implemented in
`PrivateChat/Core/Security/SecurityAISentinel.swift` and surfaces
in:

- `Features/Chat/DashboardView.swift` (top-of-screen score + level)
- `Features/Settings/SecuritySentinelView.swift` (full findings list)
- `Features/Settings/ProductionReadinessView.swift` (one of the
  readiness checks; surfaces the sentinel as a named dependency)
- `Features/Settings/SettingsView.swift` (menu entry to the detail
  view)

### What the Sentinel IS

- A **pure, deterministic** function:
  `SecurityAISentinel.assess(...) -> SecurityAISnapshot`.
- Inputs: `AppSecurityState`, `RuntimeSecuritySnapshot`,
  `RelayConnectivityStatus`, conversations, trusted peers,
  optional `RelayStatsSnapshot`, the local `IdentityID`.
- Output: a `SecurityAISnapshot` with a 0-100 score, a
  `SecurityAIRiskLevel` (optimal / guarded / elevated / critical),
  a one-line `summary`, and a list of typed findings
  (`SecurityAIFinding` with `severity`, `detail`, `recommendation`).
- No model weights, no ML inference, no CoreML, no network calls,
  no telemetry. The function is pure and re-evaluated on demand
  in the UI; nothing leaves the device.

### What the Sentinel is NOT

- **Not an LLM, not an ML model.** The "AI" in the name is a
  shorthand for "advanced rule-based assessment" — it is fully
  inspectable, fully deterministic, and fully local.
- **Not a remote service.** It cannot phone home, cannot be
  updated silently, and cannot infer anything about the user that
  isn't already available to the app process.
- **Not a substitute for a real security audit.** The sentinel
  catches configuration and runtime drift. It does not find
  cryptographic bugs, side channels, or novel attack surfaces.

### Privacy posture

Because the sentinel runs entirely on-device and is invoked only
when the user opens the Dashboard or the Sentinel view, it adds
zero new data flow. The score, the findings, and the summary are
stored only in memory unless the user takes a screenshot or shares
them manually. There is no "sentinel log" that is uploaded, no
"telemetry", and no API endpoint that aggregates assessments
across users.

### Threat-model fit

- The sentinel is **resistant to trivial bypass**: a user who
  toggles "hide previews" off and then back on will see the
  score change in real time, with the same finding text each
  time. The function has no hidden state.
- The sentinel is **honest about its limits**: the findings
  list is the audit trail. A user who disagrees with a finding
  can read the rule and decide for themselves.
- The sentinel is **transparent** to the user: every finding
  carries a `recommendation` string, so the next action is
  obvious. We do not collapse this into a vague "your device is
  in a bad state" alert.

## Consequences

- The Dashboard now shows a "Sentinel" card that drives the
  most-actionable finding to the top. Beta testers have used
  this card to find misconfigured relay URLs, expired tokens,
  and accidentally-disabled biometric unlock during the
  closed-beta phase.
- The score is *not* an absolute truth; it is a heuristic over
  a fixed rule set. We document that in the in-app help text.
- The sentinel has a unit-testable surface
  (`SecurityAISnapshot`, `SecurityAIRiskLevel`, the
  `assess(...)` function); we cover the major input shapes in
  `PrivateChatTests/`.
- Future work (Double Ratchet key-state warnings, peer
  fingerprint mismatches) can plug into the same `assess(...)`
  pipeline without changing the public type.

## References

- `PrivateChat/Core/Security/SecurityAISentinel.swift`
- `PrivateChat/Core/Security/RuntimeSecurity.swift`
- `PrivateChat/Features/Settings/SecuritySentinelView.swift`
- `PrivateChat/Features/Settings/ProductionReadinessView.swift`
- `Docs/SECURITY_ROADMAP.md` — companion roadmap
