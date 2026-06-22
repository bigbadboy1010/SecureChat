# Changelog

All notable changes to SecureChat (formerly PrivateChat) are
documented in this file. The format is loosely based on
[Keep a Changelog](https://keepachangelog.com/) and the project
adheres to [Semantic Versioning](https://semver.org/).

The per-phase development log lives in [`Docs/PHASE*_CHANGELOG.md`](Docs/);
this file is the **post-public-beta, single-source** history that
release notes, the status page, and the TestFlight "What's New"
field all point at. Drift between those three and this file is a
public-beta trust regression.

## What is in scope

| Artefact          | Source location                                  | Versioned as                  |
| ----------------- | ------------------------------------------------ | ----------------------------- |
| iOS app           | `PrivateChat.xcodeproj`, `PrivateChat/`         | `MARKETING_VERSION` (CFBundle) |
| Relay             | `RelayServer/` (Fastify, Node 22)                | `package.json#version` + git sha |
| Public site       | `RelayServer/site/` (served by Caddy)            | tracks the relay build sha    |
| Public docs       | `docs/CURRENT-ENDPOINTS.md`, `docs/*.md`         | tracks the relay build sha    |

## Unreleased

### Sprint 1: public-beta-ready setup (2026-06-22)

The first release that puts the project on a level comparable to
the Loupe public beta. The cryptography has not changed; the relay
has not changed; the iOS app has not changed. What has changed is
the **surface** around all of them: the public site, the docs, the
healthcheck contract, the deploy scripts, and the consistency of how
the project is presented to the world.

P0 fixes:

* The relay's public `/health` endpoint leaked the full operational
  config (`store`, `maxPacketBytes`, `authRequired`, etc.) to anyone
  who could `curl` it. Replaced with `/healthz` (public, 3 fields:
  `status`, `uptimeSeconds`, `version`) and `/healthz/internal`
  (operator-only, behind `X-Securechat-Ops-Token`). The legacy
  `/health` is retained for internal diagnostics.
* The preHandler hook for `/v1/relay/*` enforced the bearer token on
  every subroute, including the security-policy and stats endpoints
  which are supposed to be public. Added an explicit allowlist for
  `/v1/relay/security/policy` and `/v1/relay/stats` (the relay
  advertises its posture and live counts to anyone who asks).

Relay / infra:

* New `Dockerfile`: multi-stage build (deps -> tsc -> runtime), runs the
  compiled `dist/index.js` (not the `tsx` dev server that the old
  Dockerfile was starting). Accepts `BUILD_VERSION` and `GIT_SHA`
  build-args and surfaces them via `/healthz`.
* New `scripts/deploy-relay.sh`: rsync to the server, build with
  `--no-cache`, restart with `up -d --no-deps` (the Loupe pitfall
  where `up` alone reuses the old image is called out in the
  script's comments). Runs the smoke tests after the restart.
* New `scripts/test-relay.sh`: ~15 assertions covering the public
  healthz, the auth-required internal healthz, the public
  `/v1/relay/security/policy` and `/v1/relay/stats`, the
  unauthenticated POST to `/v1/relay/messages`, and a 200 on every
  public site page. Pass/fail count printed at the end; non-zero
  exit on any failure.

Public site (`RelayServer/site/`):

* `index.html` - marketing site, dark + light, three CTAs
  (TestFlight, Self-host, GitHub). Trust-bar with five privacy
  claims at the top.
* `status.html` - live status, security-posture table (8 controls,
  all `shipped` except the external audit which is `planned`),
  relay-endpoints table, legacy-host decommission section.
* `known-issues.html` - two active items (audit, multi-device
  sync), two recently-resolved items (healthz leak, legacy
  hostname).
* `privacy.html` - what the relay does not receive, what it does
  receive, data retention, server logs, data-deletion path,
  changes policy.
* `imprint.html` - provider, contact, dispute resolution,
  liability.
* `docs/self-host.html` - 6-step VPS guide with production
  checklist and the realistic "20 minutes if DNS and firewall are
  ready" note.
* `docs/architecture.html` - three-layer model, wire-protocol
  schema, four failure modes (relay compromised, phone
  compromised, app backdoored, DNS spoofed).
* `style.css` - own brand (soft cyan on dark + warm), layout
  primitives borrowed from the Loupe site.
* `favicon.svg` - padlock mark.

Documentation:

* `docs/CURRENT-ENDPOINTS.md` - single source of truth for every
  public endpoint, header, file, mailbox, and distribution
  channel. Mirrors the Loupe `docs/CURRENT-ENDPOINTS.md` pattern.
* `docs/ADR-001-three-layer-model.md` - why the relay is a
  stateless packet dropbox and not a "real" messaging server.
* `docs/ADR-002-envelope-and-crypto.md` - the wire format and the
  Curve25519 / AES-GCM construction, with rationale for not using
  signcryption, MLS, or per-peer long-lived symmetric keys in
  v0.1.
* `docs/ADR-003-production-hardening.md` - the fails-fast contract
  for production startup (token length, HTTPS, file store,
  writable data dir), the header set the relay enforces, the
  audit-log policy.
* `docs/iphone-test-acceptance.md` - repeatable end-to-end test for
  any beta tester, with pass/fail criteria and curl recipes.
* `docs/TESTFLIGHT-LISTING-COPY.md` - canonical App-Store-Connect
  strings (App Name, Subtitle, Description, Keywords, URLs) with
  a drift-alert blockquote at the top.
* `SECURITY.md` - supported-versions tables (iOS v0.1.x, relay
  v0.1.x), threat model, reporting workflow, PGP key placeholder,
  out-of-scope list.
* `CHANGELOG.md` (this file) - consolidated from the per-phase
  development log in `Docs/PHASE*_CHANGELOG.md`.

Verified:

* `npm install` clean (58 packages), `npm run typecheck` clean,
  `npm run build` clean.
* `/healthz` (public) returns
  `{"status":"ok","uptimeSeconds":13,"version":"v0.1.0-local+localtest"}`.
* `/healthz/internal` (without token) returns HTTP 401.
* `/healthz/internal` (with `X-Securechat-Ops-Token` matching
  `WAITLIST_ADMIN_TOKEN`) returns HTTP 200 with the full operator
  surface.
* `/v1/relay/security/policy` (public) returns HTTP 200 with
  `encryptedPayloadOnly: true`.
* `/v1/relay/stats` (public) returns HTTP 200 with counts only -
  no peer IDs, no payloads.
* `POST /v1/relay/messages` (no auth) returns HTTP 401.
* iOS test suite: `xcodebuild test` on iPhone 17 simulator -
  18/18 tests passed (`CryptoServiceTests` 6,
  `SecureChatProductionProfileTests` 3, `EncryptedMessageStoreTests`
  3, `IdentityManagerTests` 3, `EncryptedDraftStoreTests` 3).


## Public Beta 2026-06-22

The first release that is fit for use by anyone outside the
developer. The relay is hardened, the iOS app is TestFlight-ready,
and the marketing site is up. The cryptography, threat model, and
operational surface are documented in the public docs.

### Relay (`privatechat-relay-server` v0.1.0)

- **Zero-knowledge relay.** Stores and forwards opaque,
  client-sealed, client-signed envelopes. Cannot read message
  bodies, cannot forge a sender, cannot replay old packets.
- **Production hardening.** Fails fast without
  `NODE_ENV=production`, a `RELAY_AUTH_TOKEN` of at least
  `MIN_AUTH_TOKEN_LENGTH` characters, and HTTPS termination in
  front. See `RelayServer/README_PRODUCTION.md` for the contract.
- **File store as the production store.** `STORE_TYPE=file` is the
  only store that survives restarts; `InMemoryRelayStore` is for
  tests and dev only.
- **Replay protection.** TTL (default 24 h) and clock-skew window
  (default 5 min) are enforced server-side.
- **Per-IP rate limit.** Default 120 req/min.
- **Per-recipient storage cap.** 500 packets per recipient, 10 000
  packets globally.
- **Audit log.** `SECURITY_AUDIT_LOG=true` writes a JSON line per
  relay/admin request via pino, including the request id and
  response status code. Bodies are not logged.
- **Public security policy endpoint.** `GET /v1/relay/security/policy`
  returns the relay's current configuration in a stable, public
  schema.
- **Public stats endpoint.** `GET /v1/relay/stats` returns live
  counts (packets stored, recipients tracked, ack tombstones).
  No peer IDs, no payloads.

### iOS app (`SecureChat` v0.1.0)

- **End-to-end encryption on-device.** Curve25519 key agreement
  (`CryptoKit.Curve25519.KeyAgreement.PrivateKey`), AES-GCM
  message encryption (`CryptoKit.AES.GCM`), Ed25519 envelope
  signatures (`CryptoKit.Curve25519.Signing.PrivateKey`).
- **Identity lives in the iOS Keychain.** `ThisDeviceOnly`
  attribute; the Curve25519 private key never leaves the device.
- **Encrypted local message and draft store.** AES-GCM at rest;
  keys derived from the same Curve25519 identity.
- **Biometric app lock.** Face ID / Touch ID gate on launch.
- **Safety Number verification.** 60-decimal fingerprint
  comparison, out of band. The only defence against a
  key-substitution attack at the relay.
- **Relay polling.** Pulls the relay every N seconds; configurable
  in the iOS app's Settings.
- **Acknowledgement tombstones.** Once a packet is delivered, the
  iOS app POSTs an ack; the relay deletes the packet.
- **Sprint 14.6.2 (TestFlight submission prep)** — onboarding
  flow, error states, accessibility labels, and App Store
  screenshot assets are in place.

### Public site

- **Marketing site** at `https://securechat.team/`. Dark + light
  theme, no third-party scripts, no analytics, no tracking pixels.
- **Status page** at `/status.html`. Lists the security posture,
  the relay endpoints, the legacy-host decommission, and the live
  healthz contract.
- **Known-issues page** at `/known-issues.html`. Active issues
  and recently resolved items, with the canonical pointer to
  `docs/CURRENT-ENDPOINTS.md` for everything.
- **Privacy policy** at `/privacy.html`. Describes what the relay
  does and does not receive, the data-deletion request path, and
  the data-retention window.
- **Imprint** at `/imprint.html`. Legal notice + contact addresses.
- **Self-host guide** at `/docs/self-host.html`. Step-by-step
  instructions for running the relay on a fresh VPS, with a
  production checklist and a "20 minutes if DNS and firewall are
  ready" realistic estimate.
- **Architecture** at `/docs/architecture.html`. The three-layer
  model, the wire protocol, and the four failure modes (relay
  compromised, phone compromised, app backdoored, DNS spoofed).

### Documentation

- **`docs/CURRENT-ENDPOINTS.md`** is the single source of truth
  for public endpoints, headers, files, mailboxes, and
  distribution channels. Every other doc, the Caddy config, the
  TestFlight listing, and the relay's own comments point back to
  this file.
- **`docs/iphone-test-acceptance.md`** is a step-by-step
  end-to-end test that any beta tester can run to confirm the
  public relay is reachable, the iOS app completes a handshake,
  and a round-trip sealed message is delivered.
- **`docs/TESTFLIGHT-LISTING-COPY.md`** is the canonical source
  for the App Store Connect strings (App Name, Subtitle,
  Description, Keywords, URLs, What's New). The drift alert at
  the top of that file names the current drift and the
  reviewer-recommended replacement.
- **`SECURITY.md`** lists the supported versions, the threat
  model, the reporting workflow, the PGP key, and the
  out-of-scope list.

### Operational

- **DNS A record** for `securechat.team` points at the relay's
  Caddy. `chatsecure.ddns.net` was decommissioned on 22 June 2026.
- **Caddy** terminates TLS for `securechat.team` and forwards to
  the relay container. The static site is served by Caddy from
  `RelayServer/site/`.
- **Mailcow** on the same host provides
  `security@securechat.team`, `privacy@securechat.team`,
  `admin@securechat.team`, and `hello@securechat.team`.

## Historical phases

The development history before the public beta is recorded in the
per-phase changelogs in `Docs/`. The condensed history:

- **Phases 1–4.1** — iOS app: identity (Curve25519), local
  encrypted store, basic chat UI, draft store.
- **Phases 5–9** — relay: first prototype, sync stabilisation,
  in-memory store, file store, token auth, rate limit, CORS
  hardening.
- **Phase 10–10.1** — relay transport cleanup, packet
  acknowledgement tombstones.
- **Phase 11** — iOS app hardening: anti-tamper, debugger
  detection, screenshot protection, privacy composer.
- **Phase 12** — security sentinel, crypto-agility roadmap.
- **Phase 13** — relay production hardening. The contract in
  `RelayServer/README_PRODUCTION.md` originates here.
- **Phase 14** — professional UI refresh, SwiftUI rewrite.
- **Phases 14.1–14.5.4** — iOS 17 onChange cleanup, SwiftUI
  update coalescing, app icon, crypto test coverage, Safety
  Number verification UX, App Store / security cleanup.
- **Phases 14.6–14.6.2** — TestFlight UX readiness, onboarding
  compile fix, TestFlight submission prep.

The full per-phase text is in
[`Docs/PHASE*_CHANGELOG.md`](Docs/). They are retained for
historical reference; new development uses the sprint entries at
the top of this file.
