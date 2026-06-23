# CURRENT-ENDPOINTS

Single source of truth for every public endpoint, header, file, mailbox
and distribution channel that the SecureChat project advertises.
Every user-facing doc, release note, support reply, and Caddy block
**must** match this file. Drift between this file and the live site
is a public-beta trust regression.

The status page footer points at the latest commit hash of this file.
When you change a public endpoint, edit this file **first**, then
update everything that referenced the old value, then deploy, then
re-verify the live site.

---

## Canonical public endpoints

The relay has two surfaces:

- `securechat.team` — the user-visible product. Marketing site at the
  apex, app pages under `/docs/`, status at `/status.html`, privacy
  at `/privacy.html`.
- `relay.securechat.team` — the encrypted packet dropbox. This is the
  only host the iOS app talks to.

Caddy terminates TLS for both and reverse-proxies the relay container
on port 8080 for `relay.securechat.team`. The marketing site is
served as static files by Caddy itself (no app process for the
website).

| Purpose              | URL                                              | Auth                 |
| -------------------- | ------------------------------------------------ | -------------------- |
| Marketing site       | `https://securechat.team/`                       | none                 |
| Status page          | `https://securechat.team/status.html`            | none                 |
| Known issues         | `https://securechat.team/known-issues.html`      | none                 |
| Privacy policy       | `https://securechat.team/privacy.html`           | none                 |
| Imprint              | `https://securechat.team/imprint.html`           | none                 |
| Self-host guide      | `https://securechat.team/docs/self-host.html`    | none                 |
| Architecture         | `https://securechat.team/docs/architecture.html` | none                 |
| v2-envelope dashboard| `https://securechat.team/v2-stats.html`          | none                 |
| Public healthz       | `https://securechat.team/healthz`                | none                 |
| Operator healthz     | `https://securechat.team/healthz/internal`      | `X-Securechat-Ops-Token` |
| Relay WebSocket / API| `https://relay.securechat.team/v1/relay/*`       | `Authorization: Bearer $RELAY_AUTH_TOKEN` (and HTTPS) |
| Relay admin          | `https://relay.securechat.team/v1/admin/*`       | `Authorization: Bearer $RELAY_ADMIN_TOKEN` (and HTTPS) |
| Security policy      | `https://relay.securechat.team/v1/relay/security/policy` | none (public — this is the post-deployment posture) |
| Stats (public read)  | `https://relay.securechat.team/v1/relay/stats`   | none — see "Public stats surface" below |
| v2-envelope health   | `https://relay.securechat.team/v1/relay/v2-health` | none — see "v2 envelope health surface" below |

### Public stats surface

`/v1/relay/stats` is unauthenticated on purpose. It returns only the
counters needed to size the relay (live packet count, total packets
served, recipients tracked). It does **not** include message
contents, peer IDs, or any payload that would let an observer
correlate traffic. The same endpoint exists at `/v1/admin/relay/stats`
behind `RELAY_ADMIN_TOKEN` and adds administrative fields (per-peer
counters, last-seen timestamps).

The current stats schema (Sprint 12) is:

```json
{
  "storedPackets": 0,
  "activeRecipients": 0,
  "acknowledgedPacketTombstones": 0,
  "v1EnvelopeRequests": 0,
  "v2EnvelopeRequests": 0,
  "firstV2RequestAt": null,
  "lastV2RequestAt": null
}
```

`firstV2RequestAt` and `lastV2RequestAt` are ISO-8601 UTC strings,
`null` until the first v2 envelope request has been observed by the
relay process. Both fields are optional for backwards compatibility
with pre-12 relay builds.

The current stats schema lives in
[`RelayServer/src/routes.ts`](../RelayServer/src/routes.ts) under
`app.get('/v1/relay/stats', ...)`.

### v2 envelope health surface

`/v1/relay/v2-health` (Sprint 12) is unauthenticated, like
`/v1/relay/stats`. It is a **dedicated v2-envelope rollout
dashboard endpoint**, derived from the same in-process counters as
`/v1/relay/stats` but with a v2-specific shape that external
monitors can scrape and alert on:

```json
{
  "ready": false,
  "v2EnvelopeRequests": 0,
  "v1EnvelopeRequests": 0,
  "totalEnvelopeRequests": 0,
  "v2SharePercent": 0,
  "firstV2RequestAt": null,
  "lastV2RequestAt": null,
  "lastV2RequestAgeSeconds": null,
  "warnings": ["no v2 envelope requests observed yet"]
}
```

`warnings` is a synthesized array of advisory strings. The current
heuristics are:

* `"no v2 envelope requests observed yet"` when `v2EnvelopeRequests
  === 0`.
* `"no v2 envelope requests in the last Ns"` when the last v2
  request is older than the optional `?freshWindow=N` query
  parameter (default 86400 seconds = 1 day).
* `"v2 share is X% (below 1% threshold)"` when at least one
  envelope request has been observed but the v2 share is below 1%.

The endpoint is wired into the public-route allowlist in
`src/routes.ts` (`isPublicRelaySubRoute`) so no auth header is
required. A companion dashboard page at
`https://securechat.team/v2-stats.html` polls `/v1/relay/stats`
every 5 seconds and renders the v1 / v2 counters + v2-share bar.

## Health endpoints

Two endpoints, same shape convention as Loupe. The relay's existing
`/health` endpoint leaks operational knobs (store type, max packet
bytes, auth-required flag, etc.) — fine for an internal healthcheck,
**not** fine for a public endpoint. Sprint 1.1 splits it.

### `/healthz` (public, unauthenticated)

Returns the minimum that an external monitor or a beta user needs to
know that the relay is alive and on the expected build:

```json
{"status":"ok","uptimeSeconds":42,"version":"v0.4.0+<git-sha>"}
```

Three fields, no operational knobs, no auth.

### `/healthz/internal` (operator-only)

Same three fields, plus a flat dictionary of the relay's current
operational state. The operator must send a header
`X-Securechat-Ops-Token: $OPS_TOKEN`; without it, the response is `401
Unauthorized`. The token value is stored in `/opt/securechat/.../env`
on the server only and is rotated when an operator with access to
that file changes.

The canonical env var is `OPS_TOKEN` (see
[`Docs/ADR-005-peer-bound-relay-auth.md`](ADR-005-peer-bound-relay-auth.md)
and `RelayServer/src/config.ts`); the older `WAITLIST_ADMIN_TOKEN`
alias is still accepted by the relay for backwards compatibility but
new deployments should use `OPS_TOKEN` exclusively.

```json
{
  "status": "ok",
  "uptimeSeconds": 42,
  "version": "v0.4.0+<git-sha>",
  "sessions": 12,
  "peers": 7,
  "packetCount": 318,
  "nodeEnv": "production"
}
```

Field set will grow as the relay's observability surface grows;
the rule is that nothing goes into the public payload that an
external observer would not already be able to infer from the
source code.

## Distribution channels

| Artefact              | Channel                                                  |
| --------------------- | -------------------------------------------------------- |
| iOS app               | TestFlight (Public Beta)                                 |
| iOS source            | GitHub `bigbadboy1010/SecureChat` (public beta)        |
| Relay source          | same GitHub repo, `RelayServer/` subdir                  |
| Marketing site        | this repo, `RelayServer/site/` subdir (served by Caddy)  |
| Docker images         | rebuilt on `main` via `scripts/deploy-relay.sh`          |
| Privacy-respecting    | no analytics, no tracking pixels, no third-party scripts |

The TestFlight invite link is added to `docs/TESTFLIGHT-LISTING-COPY.md`
when the first TestFlight build is uploaded. Until then, the
marketing site links to the self-host guide as the recommended
onboarding path.

## Mailboxes

| Address                      | Purpose                          | Backed by           |
| ---------------------------- | -------------------------------- | ------------------- |
| `security@securechat.team`   | Vulnerability reports (PGP)      | Mailcow on the same server |
| `privacy@securechat.team`    | Privacy / data-deletion requests | Mailcow             |
| `admin@securechat.team`      | Account & abuse reports          | Mailcow             |
| `hello@securechat.team`      | Everything else                  | Mailcow             |

The PGP key for `security@securechat.team` is in `SECURITY.md` and
must be re-exported every 24 months.

## Legacy hosts (decommissioned, do not reintroduce)

The following hostnames were decommissioned during the cutover to
`securechat.team`. They must not appear in user-facing docs, release
notes, or default configurations:

- `chatsecure.ddns.net` — old NoIP free-tier hostname used for the
  pre-public-beta relay. DNS A record was removed at the registrar
  on 22 June 2026; the Caddy block returns `308 Permanent Redirect`
  to `https://securechat.team{uri}` for every request as a
  belt-and-braces measure for cached resolvers. Verified NXDOMAIN
  on 22 June 2026 (8.8.8.8, server's local resolver, build host).

## Decommission of the pre-public-beta `securechat-relay-server` image name

The relay runs in a Docker container called `securechat` (the only
container in the `securechat` Compose project). The image is built
on every `main` deploy via `scripts/deploy-relay.sh`; the image tag
is `node:22-alpine` and the build context is the `RelayServer/`
subdir of this repo. There is no separate "production" image.

## On-device Security Sentinel

The iOS app embeds a **Security Sentinel** (`SecurityAISentinel`
in `PrivateChat/Core/Security/SecurityAISentinel.swift`). It is a
local, deterministic, rule-based assessment layer that scores the
current device posture from 0 to 100 and surfaces a list of
findings with recommendations. It is **not** a machine-learning
model, **not** a remote service, and **not** a substitute for an
external security audit. It is fully inspectable in the source
tree and produces no telemetry.

| What the Sentinel looks at | What it produces |
|---------------------------|------------------|
| Runtime integrity (Debugger / Jailbreak / Injection) | Severity-ranked findings |
| App security settings (biometric, preview, keyboard) | Findings + recommendations |
| Relay configuration (HTTPS, token, production profile) | Findings + recommendations |
| Relay connectivity (healthy / degraded / paused) | Findings + recommendations |
| Trusted peer set (verified vs. unverified) | Findings + recommendations |
| Local identity (length, plausibility) | Findings + recommendations |

| Surface | Where it appears in the app |
|---------|-----------------------------|
| Dashboard | `Features/Chat/DashboardView.swift` — score + risk-level card |
| Detail view | `Features/Settings/SecuritySentinelView.swift` — full findings list |
| Production readiness | `Features/Settings/ProductionReadinessView.swift` — readiness check |
| Settings entry | `Features/Settings/SettingsView.swift` — menu link to the detail view |

The full spec is `Docs/ADR-004-security-sentinel.md`. Drift
between that ADR and the running iOS app is a public-beta trust
regression (the same drift rule that applies to this file).

## How to keep this in sync

When you change a public endpoint:

1. Update this file **first**.
2. Run `rg -n 'securechat\.team|chatsecure\.ddns\.net|relay\.securechat\.team' --type-add 'doc:*.{md,html,yml}' -t doc .`
   and clean up anything that disagrees.
3. Re-deploy the relay container and the static site.
4. Update the live status page footer to point at the new commit of this file.
