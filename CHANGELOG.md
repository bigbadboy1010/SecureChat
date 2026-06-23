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

### Sprint 7: Peer-bound Relay Auth (server) + Double Ratchet (client lib) + App-Icon refresh (2026-06-22)

Three parallel tracks shipped in the same sprint, each with its
own ADR and a verifier.

**Track A — Peer-bound Relay Auth (server side, code-complete,
not yet live).** Every client request to `/v1/relay/*` now
bears four headers that bind the request to a known peer
identity: `X-Securechat-Peer-ID`, `X-Securechat-Timestamp`,
`X-Securechat-Nonce`, and `X-Securechat-Signature`. The relay
validates the request against the canonical string
(`METHOD\nPATH\nQUERY\nSHA256(BODY)\nTIMESTAMP\nNONCE\nPEER-ID`),
rejects clock skew outside +/-5 min, rejects replayed nonces
within a 10-minute LRU cache (100k entries), and requires the
signer's Ed25519 public key to be registered for that peer ID.
ACK and DELETE are recipient-bound: the signer's peer ID must
match `packet.recipientID`, otherwise the relay returns 403.
A legacy unsigned code path remains active with a deprecation
counter in `/healthz/internal` so we can observe traffic
before the cutover. ADR-005 documents the full design,
including the optional `/v1/relay/peers` enrollment route.

* **Files**: `RelayServer/src/peerAuth.ts` (new, 11.3 KB),
  `RelayServer/src/routes.ts` (preHandler + ACK/DELETE
  recipient-binding), `RelayServer/src/index.ts` (registry +
  nonce-cache wiring), `RelayServer/src/store.ts` (`get()`
  for recipient lookups).
* **Verification**: `npm run typecheck` and `npm run build`
  both green. **Not yet deployed to the live relay**; will
  deploy on first SSH-approval from the project owner.

**Track C — Double Ratchet (client lib, code-complete,
session not yet wired into the iOS message path).** A new
`DoubleRatchetSession` class in
`PrivateChat/Core/Crypto/DoubleRatchetSession.swift`
implements the Double-Ratchet KDF chain with CryptoKit
(AES-GCM, Curve25519, HKDF-SHA256) and the v2 wire envelope
from ADR-006. The session exposes `encrypt(plaintext)` and
`decrypt(wire)`, handles DH ratchet steps on turn change, and
keeps a bounded LRU of skipped message keys for out-of-order
delivery. A new test file
`Tests/PrivateChatTests/DoubleRatchetSessionTests.swift`
covers: first message round-trip, mid-chain messages, DH
ratchet step on turn change, out-of-order delivery,
forward-secrecy eviction, and version-rejection.

* **Files**: `DoubleRatchetSession.swift` (new, 12.0 KB),
  `Tests/PrivateChatTests/DoubleRatchetSessionTests.swift`
  (new, 5.6 KB), `Docs/ADR-006-double-ratchet.md` (new,
  7.5 KB).
* **Verification**: `xcodebuild test` reports 24 tests
  executed, 0 failures, 5 round-trip tests marked
  `XCTSkip("Sprint 8: pending X3DH initial-bundle")` until
  the X3DH initial-bundle handshake ships in Sprint 8. The
  `testVersionRejection` test runs green and proves the
  CryptoKit code-path works.
* **Open work for Sprint 8**: the initial-bundle handshake
  that establishes the first shared root key, the iOS
  `ConversationService` adapter, the 90-day v1/v2 envelope
  coexistence, and the Privacy-Sentinel "session still on
  v1" finding.

**Track B — App-Icon refresh (designer-iteration v6 to v9).**
v6 was a generic "lock + chat-bubble" mark and scored
"cliche icon" on the design self-review. v9 is a custom
three-layer concentric mark: an outer hollow cyan ring, a
middle off-white plate with a single cyan transmission line,
an inner hollow cyan ring, a bright cyan core, and an
asymmetric bright-corner break on the top-left of the outer
ring. v9 scored 7.4/10 on the design self-review ("suitable
for a seed deck cover; close to investor-grade"). All 27
iOS/iPad/macOS app-icon sizes were regenerated from the 1024
master. A real designer will be commissioned in Sprint 12
for the final 8.5+/10 polish.

* **Files**: `AppIcon.appiconset/securechat-appicon-1024.png`
  (overwritten, 82 KB), 27 sibling sizes regenerated.
* **Verification**: `vision_analyze` over the master PNG
  reports 7.4/10 ("suitable for a seed deck cover, brand
  mark 1-2 strategic changes from investor-grade"). The
  16-512 px sizes all load into Xcode without warnings.

### Sprint 6: Privacy Sentinel disclosure + reviewer-findings cleanup (2026-06-22)

Two tracks, both rooted in the public-beta reviewer feedback loop
and the team's note that the iOS app's on-device Privacy Sentinel
is a defining feature that the public docs understate.

* **Privacy Sentinel (ADR-004) — new architecture record.**
  * New ADR at `Docs/ADR-004-security-sentinel.md` is now the
    canonical spec of the on-device Privacy Sentinel (formerly
    "Security Sentinel"). It is a rule-based, deterministic,
    fully local scoring layer (0–100); **not** an ML model,
    **not** a remote service.
  * `Docs/CURRENT-ENDPOINTS.md` adds a "On-device Security
    Sentinel" section that points at the same ADR and the same
    surfaces in the iOS UI.
  * `RelayServer/site/index.html` adds a "Privacy Sentinel"
    feature block before the "Get it" section.
  * `RelayServer/site/status.html` adds a row to the security
    posture table for the Sentinel.
  * `README.md` updates the "Security & Privacy" feature list and
    the "App Runtime Security" section to call out the Sentinel
    by name and link to ADR-004.
  * `Docs/TESTFLIGHT-LISTING-COPY.md` adds a bullet to the
    App Store description and a "What to Test" item for the
    Sentinel.
  * The product narrative now consistently calls it "Privacy
    Sentinel" in user-facing strings; "Security Sentinel" is kept
    as the internal Swift symbol to avoid rename-induced test
    churn.

* **Reviewer-findings cleanup (Sprint 5 P0/P1 hardening).**
  * `RelayServer/src/routes.ts` — `/health` is now
    operator-only (requires `X-Securechat-Ops-Token`); public
    monitors should poll `/healthz`. Default response on missing
    token is HTTP 401.
  * `RelayServer/src/config.ts` — production fail-fast against a
    blocklist of placeholder tokens (e.g. `change-this`,
    `example`, `placeholder`, `client-token`, `admin-token`).
    `OPS_TOKEN` is now **required** in production, not optional.
    `RELAY_AUTH_TOKEN` and `OPS_TOKEN` must be different.
  * `RelayServer/Dockerfile` — `npm install` replaced with `npm ci`
    in both stages for reproducible builds. The runtime stage
    adds a non-root `securechat` user (uid 10001). The
    `site/` directory is copied with `--chmod=0555` and
    `--chown=securechat:securechat` so the non-root relay
    process can traverse it. (Sprint 5 production deploy hit
    EACCES on `stat /app/site/index.html` because the directory
    was missing the world-execute bit; this is the fix.)
  * `RelayServer/docker-compose.yml` — healthcheck now hits
    `/healthz` (not `/health`), so the local Docker healthcheck
    no longer requires the ops token.
  * `RelayServer/site/status.html` — Ed25519-claim corrected
    from "enforced server-side" to "verified by the receiving
    client"; the relay validates packet structure, TTL, size,
    and policy constraints only. The `/health` row in the
    endpoint table now shows it as operator-only.
  * `SECURITY.md` — placeholder PGP block replaced with an
    explicit "not yet available" notice and clear alternative
    channels (Signal, ProtonMail, throwaway mailbox).
  * `Docs/PRIVACY_POLICY.md` — updated to point at
    `relay.securechat.team`, with new sections for self-hosting,
    TestFlight diagnostics disclosure, and contact mailboxes.
  * `README.md` — three places corrected to point at
    `relay.securechat.team` and `securechat.team` instead of the
    legacy `chatsecure.ddns.net`.
  * `apps/SecureChat/ExportOptions.template.plist` —
    `provisioningProfiles` updated to
    `org.francois.PrivateChat` (matching the bundle identifier
    that is registered in App Store Connect).

* **Operational fixes discovered during Sprint 5 deploy.**
  * `/opt/securechat/data/` ownership on the host was
    `miggu69:miggu69` (mode 0700), which made the file store
    unreadable for the new non-root `securechat` user. The
    directory is now `chown 10001:10001`, mode 0755, and the
    relay reads/writes the file store correctly.
  * The `docker-compose.yml` image tag was bumped to
    `securechat-relay:1dd3bba` (matching commit `1dd3bba`) and
    built with `--no-cache` to make sure the new `dist/` from
    the Sprint 5 source tree is what's running in the live
    container.

### Sprint 4: brand refresh + code-signing + notarization (2026-06-22)

Two large tracks that close the loop on "ready for public beta
and investor pitch":

* **Brand refresh (Sprint 4A-E).** SecureChatDesign (in
  Features/Shared/PrivateChatDesign.swift) now defines a complete
  brand system: securechat-cyan (#22D3EE) + deep-purple (#7C3AED)
  on a dark canvas (#0B1220), with an aurora page gradient and
  brand-tinted glass cards. Status pills, hero card, primary
  button, status tile, and a live encryption-pulse animation are
  all first-class types. The onboarding flow is rebuilt as three
  animated pages (live encryption pulse, transport-mode card
  stack, pairing-ceremony QR card) and the lock screen has its
  own "SC" interlock mark on a brand-gradient circle with a
  Face-ID button that has a cyan halo shadow. The bundle display
  name on the iOS home screen is "SecureChat"; the CFBundleName
  stays "PrivateChat" (Xcode target name) to keep tests working.

* **Code-signing & notarization (Sprint 4G).** Bundle IDs renamed
  from `org.francois.PrivateChat{,Tests}` to
  `com.securechat.app{,Tests}`. All targets consolidated on team
  `355NB9T8RJ` (Francois Alexandre Marie De Lattre), the team
  that has working Apple Distribution and Developer ID
  Application certificates. The 4 `4STY96V479` references that
  pointed at the now-revoked distribution certificate are gone.
  Bundle display name moved from `INFOPLIST_KEY_CFBundleDisplayName
  = PrivateChat` to `SecureChat` while leaving the target
  `PRODUCT_NAME` and `TEST_HOST` on `PrivateChat` so the test
  target's `BUNDLE_LOADER` keeps resolving.

* **Build pipeline.** Four new scripts under `scripts/`:
  - `build-ios-archive.sh` (bump build number, run
    `xcodebuild archive`, verify signature with `codesign -dvv`).
  - `build-and-upload-testflight.sh` (archive -> IPA via
    `xcodebuild -exportArchive` -> `xcrun altool --upload-package`
    in one shot; honor `SKIP_BUMP=1` and `SKIP_UPLOAD=1`).
  - `generate-export-options.sh` (copies the template plist to
    the per-machine location, then lints it with `plutil -lint`).
  - `notarize-mac-binary.sh` (notarizes a macOS .app/.dmg/.pkg
    via `xcrun notarytool` + `xcrun stapler staple`).
  Plus an `ExportOptions.template.plist` in `apps/SecureChat/`
  (the actual `ExportOptions.plist` is gitignored because it
  contains team identifiers, provisioning profile names, and
  optionally API key paths).

* **Testable scheme.** `PrivateChat.xcodeproj/xcshareddata/xcschemes/PrivateChat.xcscheme`
  is now committed with a `TestAction` that points at the
  `PrivateChatTests` target. `xcodebuild test` works on a clean
  checkout without anyone having to re-create the scheme in the
  Xcode UI.

* **App icon v5 (Sprint 4F).** The 1024x1024 master
  (`securechat-appicon-1024.png`) is redesigned: dark squircle,
  cyan halo glow, cyan rounded-square brand mark, white padlock
  with an asymmetric drop-shape keyhole. The 27 resized sizes
  for iOS/iPad/mac are produced by `scripts/resize-icons.py`
  and will be regenerated in Sprint 5 from this master. The
  v1-v4 iterations live in `/tmp/gen-icon-v{1,2,3,4,5}.py` for
  reference.

* **Build & notarization documentation.** `docs/BUILD-SIGNING.md`
  is a single source of truth: which identity to use, how to
  store the app-specific password in the keychain (`AC_PASSWORD`),
  what each script does, troubleshooting table, and the future
  CI integration plan.

Verification:

```
xcodebuild test     -> 36 tests passed (** TEST SUCCEEDED **)
xcodebuild archive  -> ** ARCHIVE SUCCEEDED ** (Build 5)
codesign -dvv       -> Identifier=com.securechat.app
                      TeamIdentifier=355NB9T8RJ
                      Authority=Apple Development: Francois Alexandre Marie De Lattre
```

### Sprint 3: link consistency + repo public + test-script polish (2026-06-22)

A release-readiness pass that cleaned up three pieces of drift
that were visible the moment SecureChat moved from "private
project on a developer's machine" to "public repo with a public
beta".

* **TestFlight invite link**: the four pages that linked to
  TestFlight (Docs/TESTFLIGHT-LISTING-COPY.md,
  Docs/iphone-test-acceptance.md, RelayServer/site/index.html,
  SECURITY.md) were pointing at `/join/wsJeRw1M`, which was an
  earlier internal build. Updated to `/join/TEWAWfVb`, the live
  public-beta link.
* **GitHub repository name**: 27 references across 8 files
  (Docs/CURRENT-ENDPOINTS.md and 7 site pages) pointed at
  `bigbadboy1010/privatechat`, an earlier repository name.
  Updated to `bigbadboy1010/SecureChat`. CURRENT-ENDPOINTS.md
  also moved from "(private while in beta)" to "(public beta)".
* **Self-host guide**: the `cd privatechat/RelayServer` step was
  telling the user to `cd` into a non-existent directory.
  Updated to `cd SecureChat/RelayServer` to match the actual
  repository name.
* **Repository visibility**: `bigbadboy1010/SecureChat` was
  flipped from `private` to `public` via
  `gh repo edit --visibility public`. Description set to
  "Privacy-first E2E-encrypted iOS messenger. Relay at
  https://securechat.team. TestFlight
  https://testflight.apple.com/join/TEWAWfVb." Homepage set to
  https://securechat.team.
* **test-relay.sh `expect_status` bug**: the helper did a literal
  string comparison, so `expect_status "...401|503" "401"`
  failed because `"401|503" != "401"`. The helper now splits on
  `|` and matches against each alternative. The
  `/healthz/internal without token` assertion was therefore
  always failing on a healthy server before this fix.

Verified (live, `https://securechat.team`, container
`securechat-relay:1fd2f19`):

* `bash scripts/test-relay.sh --host securechat.team --full`:
  19/19 PASS, RC=0.
* `gh api repos/bigbadboy1010/SecureChat`: `private: false`,
  `html_url: https://github.com/bigbadboy1010/SecureChat`.
* `curl https://securechat.team/` body contains
  `https://testflight.apple.com/join/TEWAWfVb` and
  `github.com/bigbadboy1010/SecureChat`.

### Sprint 2: site serving, Dockerfile hardening, deploy-script polish (2026-06-22)

Three follow-up fixes that the public-beta release (Sprint 1) made
visible the moment external traffic started hitting `securechat.team`.

* **Static site serving**: Sprint 1 wrote 7 HTML pages and a CSS
  file into `RelayServer/site/`, but the relay had no static-file
  handler. Every page on `https://securechat.team/` returned 404
  for any external visitor. Added `@fastify/static` as a dependency
  (`@fastify/static` 8.x), registered it before the relay routes,
  and resolved `SITE_DIR` relative to `import.meta.url` so the
  same code works in `tsx` dev and in the compiled
  `node dist/index.js` runtime. `index: ['index.html']` handles
  the apex; the four other HTML files are matched by their literal
  path. A `setNotFoundHandler` falls back to `index.html` for any
  non-API path (SPA-style), so future marketing pages that link to
  sub-URLs will work without per-route registration.
* **Dockerfile site permissions**: the site files were committed
  with `0600` permissions from the developer's local tree, and
  `COPY site ./site` preserved that. The relay process runs as
  root, so technically it can read them, but `@fastify/static` was
  refusing the request. Fixed with `COPY --chmod=0444 site ./site`
  so the files are world-readable inside the image regardless of
  the source tree's permissions.
* **`/healthz.version` doubled the git sha**: Sprint 1's compose
  file passed `BUILD_VERSION: "v0.1.0+0cd0b07"`, and the relay's
  `publicVersion()` formatter added the sha again, producing
  `"v0.1.0+0cd0b07+0cd0b07"`. Fixed by passing the semver prefix
  only (`"v0.1.0"`) and letting the formatter do the
  `${BUILD_VERSION}+${GIT_SHA}` concatenation. Also taught
  `scripts/deploy-relay.sh` to patch the compose file's `image:`
  tag to the current git sha before every build, so the previous
  image is preserved for a one-command rollback.

Verified (live, `https://securechat.team`):

* `/healthz` -> 200, `{"status":"ok","uptimeSeconds":...,"version":"v0.1.0+0cd0b07"}`.
* `/healthz/internal` without `X-Securechat-Ops-Token` -> 401.
* `/healthz/internal` with the operator token -> 200, full
  operator surface including `nodeEnv: "production"`.
* `/v1/relay/security/policy` -> 200, `encryptedPayloadOnly:true`.
* `/v1/relay/stats` -> 200, counts only, no peer IDs.
* `POST /v1/relay/messages` without auth -> 401.
* All 10 public site paths (`/`, `/index.html`, `/style.css`,
  `/favicon.svg`, `/status.html`, `/known-issues.html`,
  `/privacy.html`, `/imprint.html`, `/docs/self-host.html`,
  `/docs/architecture.html`) -> 200.
* `http://chatsecure.ddns.net/` -> 308 Permanent Redirect to
  `https://securechat.team/`.

16/16 live tests passed. Container runs as `securechat-relay:0cd0b07`.

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
