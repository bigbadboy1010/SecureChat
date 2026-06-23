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

### Sprint 15 + 16: peer-bound request signing (iOS + relay, opt-in) (2026-06-23)

Sprint 15 + 16 wire the relay's peer-bound
request signing layer (ADR-005) end-to-end
on the iOS side, add the
`RELAY_REQUIRE_PEER_AUTH` opt-in flag on
the relay side, and enforce the canonical
sender/recipient binding on the three
client routes that need it (`POST`,
`GET`, `DELETE`).

**iOS (4 files modified, 3 new, ~+650
lines):**

* `PrivateChat/Core/Transport/RequestSigner.swift` (new)
  - The pure (no I/O, no UI) helper that
    builds the canonical-string input per
    `Docs/RELAY_API_CONTRACT.md` §6 and
    signs it with the peer's long-term
    Ed25519 signing key.
  - `canonicalString(...)`, `canonicalQueryString(...)`,
    `sign(...)`, `sha256Hex(...)`,
    `makeNonce()`, `currentTimestamp()`.
  - All public, all sendable across the
    test boundary, all used by the
    `RelayTransport` on every outgoing
    request.

* `PrivateChat/Core/Transport/PeerBoundSigningContext.swift` (new)
  - Tiny protocol the transport uses to
    look up the peer's long-form public
    peer ID and the Ed25519 signing
    private key. Decouples the
    `RelayTransport` from the broader
    `IdentityManager` stack — only this
    two-method protocol is needed.

* `PrivateChat/Core/Models/ChatModels.swift`
  - `RelayConfiguration` is left
    `Codable, Equatable` (the signing
    context is a class-typed protocol, not
    a value, so it does not belong in the
    persisted config). The transport
    receives the context via a separate
    init parameter.

* `PrivateChat/Core/Transport/RelayTransport.swift`
  - `init(configuration:signingContext:urlSession:)` —
    the signing context is wired in at app
    start.
  - `makeRequest(path:method:queryItems:body:)` —
    produces a `URLRequest` with the four
    peer-bound headers attached, when the
    context is available. The
    canonical-string input matches the
    relay's `peerAuth.ts` `canonical-string`
    helper byte for byte.
  - `applyDefaultHeaders(...)` writes
    `X-Securechat-Peer-ID`,
    `X-Securechat-Timestamp`,
    `X-Securechat-Nonce`,
    `X-Securechat-Signature` when the
    `SignedHeaders` value is present;
    when it is `nil` the request goes
    out unsigned (legacy mode, accepted
    in development, counted in
    `unsignedRequests`).

* `PrivateChat/Core/Transport/TransportCoordinator.swift`
  - Accepts an optional
    `PeerBoundSigningContext?` and passes
    it into the per-config
    `RelayTransport` factory closure so
    every request through the
    coordinator gets the headers.

* `PrivateChat/Core/Security/IdentityManager.swift`
  - Conforms to `PeerBoundSigningContext`
    with two tiny methods:
    `currentPeerID() -> String?` and
    `currentSigningPrivateKey() ->
    Curve25519.Signing.PrivateKey`. Both
    read the existing keychain-resident
    `LocalIdentity`; the private-key
    access has a non-fatal fallback so a
    corrupt keychain does not crash the
    transport — the relay will reject the
    signature and the request will fail
    with 401/403, which the transport
    surfaces as a normal network error.

* `Tests/PrivateChatTests/RequestSignerTests.swift` (new, 9 tests, 0 XCTSkip)
  - `testCanonicalStringHasSevenLines`
    — the canonical string is
    `<METHOD>\n<path>\n<query>\n<body-sha256>\n<ts>\n<nonce>\n<peer-id>`
    with no trailing newline.
  - `testMethodIsUppercased` —
    `"delete"` is canonicalized to
    `"DELETE"`.
  - `testEmptyBodyHashesToSHA256Empty` —
    SHA-256 of the empty string is
    `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.
  - `testCanonicalQueryStringSortsByName` —
    `["z=1", "a=2"]` → `"a=2&z=1"`.
  - `testCanonicalQueryStringSortsByValueWhenNameEqual` —
    `["tag=z", "tag=a"]` → `"tag=a&tag=z"`.
  - `testCanonicalQueryStringPercentEncodesValues` —
    `"hello world"` → `"hello%20world"`.
  - `testCanonicalQueryStringNilValueTreatedAsEmpty` —
    `flag=nil` → `"flag="`.
  - `testSignProducesVerifiableSignature` —
    round-trip: the produced signature
    verifies under the peer's public key
    over the canonical string.
  - `testSignedHeadersDifferAcrossCalls` —
    CryptoKit Ed25519 is non-deterministic
    (each call to
    `signingKey.signature(for:)` uses a
    fresh random nonce); the relay's
    nonce cache prevents replay.
  - `testSignedHeadersDifferForDifferentNonces`
    — a fresh `nonce` produces a
    different signature.
  - `testMakeNonceIs64HexChars` /
    `testCurrentTimestampIsTenDigits` —
    format checks.

**Relay (3 files modified):**

* `RelayServer/src/config.ts`
  - `RELAY_REQUIRE_PEER_AUTH` env-var
    parsed as optional boolean,
    defaulting to `false`. New
    `RelayConfig.requirePeerAuth` field
    on the config interface and on the
    return value of `loadConfig(...)`.

* `RelayServer/src/routes.ts`
  - The pre-handler hook now rejects
    unsigned requests with `401
    unsigned_request_required` when
    `config.requirePeerAuth` is `true`.
    When the flag is `false` (the
    default) unsigned requests are
    accepted and counted in
    `unsignedRequests` so the operator
    can monitor the migration progress.
  - `POST /v1/relay/messages` enforces
    `signer == packet.senderID` when the
    request was peer-signed (returns
    `403 signer_not_sender` otherwise).
  - `GET /v1/relay/messages` enforces
    `signer == query.recipientID` when
    the request was peer-signed (returns
    `403 signer_not_recipient`
    otherwise).
  - `DELETE /v1/relay/messages/:id` and
    `POST /v1/relay/messages/:id/ack`
    already enforced
    `signer == packet.recipientID` since
    Sprint 7; the existing check is
    kept as-is.

**Result:**
- 12 iOS test suites, 0 failures, 0
  XCTSkip (the new `RequestSignerTests`
  is the 12th suite).
- Relay `npm run build` is clean.
- Live deploy on
  `securechat-relay:4844f02` re-built
  and restarted; `test-relay.sh
  --host securechat.team --full` is
  18/18 PASS.
- Default posture: `RELAY_REQUIRE_PEER_AUTH=false`,
  so the pre-Sprint-15 iOS TestFlight
  builds (currently in beta-tester
  hands) keep working unchanged. The
  peer-bound headers are *sent* by the
  new Sprint 15 iOS build and *verified*
  by the relay; the signed/unsigned
  counter split is observable in
  `/v1/relay/stats` for the operator to
  decide when to flip the flag to
  `true`.
- Migration plan to flip
  `RELAY_REQUIRE_PEER_AUTH=true` on
  the public production relay lives
  in the relay's README + this CHANGELOG;
  it is **not** in scope for the Sprint
  16 cutover.

### Sprint 14: iOS RelayTransport modernization + docs + privacy (2026-06-23)

Sprint 14 closes the P0 findings of the
external review (Relay-Health-Migration,
iOS-Transport-Header-Modernization,
HTTP-In-Release block, public
TestFlight-Diagnostik disclosure,
endpoints-table /healthz sync) and the
P1 API-Contract rewrite.

### Sprint 13: docs sync (CURRENT-ENDPOINTS.md) + ADR-008 (2-DH X3DH deferred to post-1.0) (2026-06-23)

1. **Docs sync (Sprint 13A):** the
   `Docs/CURRENT-ENDPOINTS.md` source-of-truth
   was missing the new `/v1/relay/v2-health`
   endpoint and the `/v2-stats.html` dashboard
   that shipped in Sprint 12. The two new
   rows are added to the canonical endpoint
   table; the `Public stats surface` section
   gets the updated `RelayStatsResponse`
   JSON example (with `firstV2RequestAt` /
   `lastV2RequestAt`); a new
   `v2 envelope health surface` section
   documents the `/v1/relay/v2-health`
   shape, the `warnings[]` heuristics,
   and the dashboard polling.

2. **2-DH X3DH research (Sprint 13G):**
   Sprint 11B reverted from the 2-DH form
   to the single-DH form because Apple
   CryptoKit does not expose the
   Ed25519 → X25519 birational map. Sprint
   13G confirmed the diagnosis with a
   standalone Swift test script: the
   `Curve25519.KeyAgreement.PublicKey(
   rawRepresentation: ed25519_raw)` init
   succeeds but the output raw bytes are
   *identical* to the input — Apple treats
   the ed25519 bytes as a raw Montgomery
   U-coordinate, which is a different
   curve point. A DH against this "X25519"
   key is not symmetric and does not commit
   the root key to the remote's identity.
   The birational-map extension in
   `X3DHAgreement.swift` is now marked
   `@available(*, unavailable, ...)` so
   future code cannot accidentally use it.
   The full research write-up lives in the
   new `Docs/ADR-008-apple-cryptokit-no-birational-map.md`.

**iOS (1 file modified, +30/-8 lines):**

* `PrivateChat/Core/Crypto/X3DHAgreement.swift`
  - The `Curve25519.Signing.PublicKey
    -> associatedKeyAgreementPublicKey`
    extension (the Sprint-9 / 11B-era
    no-op birational map) is marked
    `@available(*, unavailable, message:
    "see ADR-008: ...")` so any future
    code that imports the symbol gets a
    compile-time error pointing at
    ADR-008. The body is kept for
    documentation; no production code
    path uses it (it never did, even
    before the `@unavailable` mark).
  - The file header doc-comment already
    documents the single-DH production
    posture from Sprint 11B; no change
    needed there.

**Docs (2 files modified; 1 new file,
~150 lines):**

* `Docs/CURRENT-ENDPOINTS.md` (Sprint 13A)
  - 2 new rows in the canonical endpoint
    table:
    - `v2-envelope dashboard:
      https://securechat.team/v2-stats.html`
    - `v2-envelope health:
      https://relay.securechat.team/v1/relay/v2-health`
  - `Public stats surface` section gets
    the full updated JSON example with
    `firstV2RequestAt` and
    `lastV2RequestAt`.
  - New `v2 envelope health surface`
    section documents the
    `RelayV2HealthResponse` shape, the
    `warnings[]` heuristics, the
    `?freshWindow=N` query parameter,
    and the dashboard polling cadence.

* `Docs/ADR-008-apple-cryptokit-no-birational-map.md` (new, ~150 lines)
  - Full research write-up: context,
    Sprint 13G test, Sprint 11B failed
    workarounds, three recommended
    paths forward (manual birational
    map; pre-audited Swift package;
    single-key model), decision, and
    consequences.
  - Marks the 2-DH X3DH upgrade as
    **deferred to a post-1.0
    crypto-refresh sprint with external
    review**.

**Result:**
- 11 iOS test suites, 0 failures, 0
  XCTSkip (unchanged from Sprint 12).
- The `@unavailable` mark on the
  birational-map extension is a
  compile-time safety net: any future
  iOS code that tries to use the symbol
  will fail to build with a clear
  pointer to ADR-008.
- `CURRENT-ENDPOINTS.md` is back in
  sync with the live site (Sprint 12
  endpoints are documented; the
  deployment-drift risk that the
  "Single source of truth" preamble
  warns about is closed for the v2
  rollout).

### Sprint 12: v2-envelope UX + live dashboard + v2 health endpoint (2026-06-23)

Sprint 12 closes the last UX / observability
gaps for the v2 envelope rollout. The
Privacy Sentinel now explains v1 / v2 in
plain language, the public relay exposes a
dedicated v2 health endpoint, and a live
dashboard at
`https://securechat.team/v2-stats.html`
surfaces the v1 / v2 share without leaving
the marketing site.

**iOS (3 files modified, +160/-8 lines; 0 new
test file):**

* `PrivateChat/Features/Settings/SecuritySentinelView.swift`
  - `SecurityFindingRow` now renders a
    "Was heißt das?" disclosure (Sprint
    12-1). v2-envelope findings show a
    small green `v2` badge inline with
    the severity label; the disclosure
    expands to a short plain-language
    explanation of the v2 envelope
    (X3DH, Double Ratchet, Forward
    Secrecy, Post-Compromise Security)
    or the v1 envelope (Curve25519 + AES-
    GCM, ADR-002, no per-message FS).
    The old "Empfehlung:" line is moved
    into the expanded card so the
    collapsed row stays scannable.
  - No new tests: the disclosure is a
    pure SwiftUI rendering, the
    underlying findings (Sprint 10D) are
    already covered by
    `RatchetSentinelFindingsTests`.

* `PrivateChat/Core/Transport/TransportModels.swift`
  - `RelayStatsResponse` extended with
    `firstV2RequestAt: String?` and
    `lastV2RequestAt: String?` (ISO-8601
    UTC, optional for backwards compat).
  - New `RelayV2HealthResponse` struct
    decoding `/v1/relay/v2-health`
    (Sprint 12-4).

* `Tests/PrivateChatTests/TestSupport.swift`
  - `MockTransportCoordinator`'s default
    `RelayStatsResponse` seeds the two
    new optional fields to `nil`. No
    behavioural change.

**Relay (3 files modified, +130/-2 lines; 1
new HTML file, ~250 lines):**

* `RelayServer/src/schemas.ts`
  - `RelayStatsResponse` gains
    `firstV2RequestAt?` and
    `lastV2RequestAt?` (optional for
    pre-12-4 client compatibility).
  - New `RelayV2HealthResponse` schema
    with `ready`, `v2SharePercent`,
    `firstV2RequestAt`, `lastV2RequestAt`,
    `lastV2RequestAgeSeconds`, and a
    `warnings: ReadonlyArray<string>`
    field.

* `RelayServer/src/store.ts`
  - `InMemoryRelayStore` tracks
    `firstV2RequestAt` and
    `lastV2RequestAt` (in-process, set
    on every `put(...)` with
    `protocolVersion === 3`). Surfaced
    via `stats()`.

* `RelayServer/src/routes.ts`
  - New public `GET /v1/relay/v2-health`
    endpoint (Sprint 12-4). Returns the
    `RelayV2HealthResponse`. Computes
    `v2SharePercent`,
    `lastV2RequestAgeSeconds`, and
    synthesises a `warnings` array
    based on the optional
    `?freshWindow=86400` query
    parameter (default 1d). The
    `isPublicRelaySubRoute` allowlist
    is extended to cover the new path
    so monitors can scrape it without
    authentication.
  - Sprint 12-3 dashboard link is
    added to the public nav (via the
    static `site/v2-stats.html`).

* `RelayServer/site/v2-stats.html` (new,
  ~250 lines)
  - Standalone dashboard page
    (Sprint 12-3). Polls
    `/v1/relay/stats` every 5s, shows
    v1 / v2 counters, a v2-share
    progress bar, and a 30s-stale
    watchdog. No peer IDs, no
    payloads, no authentication.
    Served by the existing
    `@fastify/static` registration.

**Sprint 12-2 (v2 indicator per message) was
intentionally skipped.** Adding a v2 badge
to the chat bubble would require a
persisted `envelopeVersion` field on
`ChatMessage` (Codable migration, init
overloads, all decoders updated). The
counter is already surfaced in the
Sentinel and the public dashboard, which
gives the same UX value with much less
schema churn; the per-message indicator
is a Sprint 13 candidate.

**Result:**
- 11 iOS test suites, 0 failures, 0
  XCTSkip (unchanged from Sprint 11A/B).
- 18 / 18 live tests pass (unchanged
  surface, new v2-health endpoint
  passes its `200` smoke check via the
  new public allowlist).
- New live endpoints:
  `https://securechat.team/v1/relay/v2-health`
  (200, `ready: false` until the first
  v2 request lands), and
  `https://securechat.team/v2-stats.html`
  (200, live-polling dashboard).

### Sprint 11B: 2-DH X3DH attempt + revert (2026-06-23)

Sprint 11B started as an upgrade to the **2-DH
X3DH** form (adding
`DH(local_KA_priv, remote_signingPub_as_X25519)`
to the existing single-DH agreement, to bind
the root key to the remote's identity and
detect MITM attempts that swap the signing
key in transit). It ended as a **pragmatic
revert to the pre-11B single-DH form** with
a detailed explanation of why, documented
directly in the `X3DHAgreement.swift`
header-comment.

**Why the revert:** the proper 2-DH form
needs the Ed25519 → X25519 birational map,
which Apple CryptoKit does not expose. The
1.5-DH fallback (HMAC-SHA256 over the remote
signing public key, mixed into the HKDF info
string) broke the symmetry invariant: Alice
hashes Bob's signing key, Bob hashes Alice's
signing key, so the two `info` strings
differ and the two `rootKey`s are no longer
equal. The `DoubleRatchetSessionTests` and
`RatchetChannelTests` caught this with hard
`XCTAssertEqual(aliceRoot, bobRoot, ...)` and
`XCTAssertEqual(aliceSessionID, bobSessionID,
...)` assertions.

**What Sprint 11B actually delivers:** the
single-DH form is restored unchanged, and
the file header now documents:

* why full 2-DH X3DH is not possible in
  Apple CryptoKit (no birational map),
* why the 1.5-DH fallback breaks symmetry,
* how the v1 envelope **signing** (Sprint 7)
  recovers the identity-commitment / MITM-
  detection property: every v1 outbound
  packet carries an Ed25519 signature of the
  `sealedPayload`; a MITM who swaps the
  signing key in transit fails the v1
  signature verification and is rejected by
  `processInboundPacket(...)` before the v2
  path is reached.

**iOS (1 file modified, +52/-32 lines, net
+20):**

* `PrivateChat/Core/Crypto/X3DHAgreement.swift`
  - Doc-Comment updated to describe the
    Sprint 11B attempt + revert and the v1
    signing-based identity-commitment
    fallback.
  - `deriveRootKey(...)` body restored to the
    pre-11B single-DH form.
  - The pre-11B `Curve25519.Signing.PublicKey
    -> Curve25519.KeyAgreement.PublicKey`
    birational-map extension is kept as
    `private` (still useful for future
    research, but not used in the
    production path).

**Result:** 11 iOS test suites, 0 failures, 0
XCTSkip (unchanged from Sprint 11A). Sprint
11B is a **negative result** with a clear
write-up; the next attempt to upgrade X3DH
should be preceded by either adopting a
third-party CryptoKit-extension that exposes
the birational map, or by switching to a
different keypair (e.g. both peers run
Curve25519.KeyAgreement only, with the
signing identity derived as a side-channel
HMAC). Both options are out of scope for the
current Public-Beta track and belong to a
post-1.0 crypto-refresh.

### Sprint 11A: ConversationService integration tests for the v2 inbound path (2026-06-23)

Sprint 11A adds the first
`ConversationService`-level integration
tests. The tests drive
`syncRelayInbox()` with a pre-seeded
`MockTransportCoordinator` inbox and assert on
the resulting state (conversations, relay
packet ledger, v2 envelope emission). The
tests are scoped to the **decision tree** of
`processInboundPacket` / `processInboundV2Packet`
rather than a full happy-path round-trip,
because the latter would require the receiver
side to share the local identity's Curve25519
keypair with the sender (intercepting the
production keychain lookup). The full v2
round-trip across an app relaunch is already
covered by
`RatchetChannelTests.testMultiMessageRoundTripAcrossRelaunch`.

**iOS (3 files modified, +310 lines; 1 new test
file, 3 new tests):**

* `PrivateChat/Core/Transport/TransportModels.swift`
  - `RelayStatsResponse` now decodes
    `v1EnvelopeRequests` and
    `v2EnvelopeRequests` (both optional). The
    relay has been emitting these fields
    since Sprint 9C (`4844f02`) but the iOS
    decoder silently dropped them. Public-
    beta testers who already installed a
    TestFlight build could not see the
    counter in the iOS dashboard; after
    Sprint 11A the counter round-trips
    end-to-end. The fields are optional for
    backwards compatibility with pre-9C
    relay builds that did not emit them.

* `Tests/PrivateChatTests/TestSupport.swift`
  - 6 new mocks: `MockMessageStore`,
    `MockDraftStore`, `MockPeerTrustStore`,
    `MockSecuritySettingsStore`,
    `MockRelayPacketLedgerStore`,
    `MockIdentityManager`, plus a
    `StubCryptoService` (real `AES.GCM`,
    minimal `sign`/`verify`) and a
    `MockTransportCoordinator` that captures
    sent packets and returns a pre-seeded
    inbox on `fetchRelayInbox(...)`. The
    mocks are reused by future
    `ConversationServiceTests` as the
    Service's dependency surface grows.

* `Tests/PrivateChatTests/ConversationServiceTests.swift`
  (new, 240 lines)
  - 3 tests covering the v2 inbound decision
    tree:
    - `testProcessInboundV2PacketRejectsUnsupportedVersion`
      -- a v2 packet with
      `protocolVersion: 99` is rejected by
      `processInboundPacket` and never
      reaches the v2 branch.
    - `testProcessInboundV2PacketRejectsSenderMismatch`
      -- a v2 packet whose inner
      `RatchetChannelEnvelope.peerID` does not
      match the routing expectation is
      rejected by
      `RatchetEnvelopeRouter.tryDecodeV2(...)`
      and surfaces as a "session still on v1"
      observation rather than a delivered
      message.
    - `testProcessInboundV2PacketRejectsSelfSent`
      -- a v2 packet where `senderID ==
      localIdentity.id` is rejected by
      `processInboundPacket` because the
      service refuses to accept packets from
      itself.

**Result:** 11 iOS test suites, 0 failures, 0
XCTSkip (was 10). Sprint 11A closes the
remaining test gap on the v2 inbound path;
the iOS test count rises to 34 passing
assertions across 11 suites.

### Sprint 10B: live ratchet state survives an app relaunch (2026-06-23)

Sprint 10B closes the last Sprint-9 gap: a
Double-Ratchet conversation that has progressed
past the initial-bundle phase now survives an
app relaunch. After every `RatchetChannel.send(...)`
/ `RatchetChannel.receive(...)` call, the live
state (root key, send / recv chain keys, send /
recv counters, the current DH ratchet keypair,
the remote ratchet public key, the
`previousSendChainLength`, and the
skipped-message-key window) is snapshotted into
the on-device keychain alongside the existing
X3DH bundle material. On the next launch the
`ConversationService` opens the channel via
`RatchetChannel.open(...)`; the rebuilt session
is restored to the exact chain position the
previous instance had reached, so no message is
re-encrypted and no counter regresses.

**iOS (3 files modified, +130 lines; 1 test file
modified, +98 lines / 3 new tests):**

* `PrivateChat/Core/Crypto/DoubleRatchetSession.swift`
  - State variables (`sessionID`, `rootKey`,
    `sendChainKey`, `recvChainKey`,
    `sendCounter`, `recvCounter`,
    `dhRatchetKeyPair`, `remoteRatchetPK`,
    `previousSendChainLength`,
    `skippedMessageKeys`, `maxSkippedKeys`)
    demoted from `private` to internal so the
    persistence layer in the same module can
    read / write them. The class remains
    **not** thread-safe (Sprint 9A contract);
    callers serialise access through
    `RatchetChannel` and `ConversationService`.
  - New `public struct LiveState: Codable,
    Equatable` carrying the snapshotted state.
    Inner `SkippedKey` struct holds a 32-byte
    chain key + a counter.
  - New `public func exportLiveState() ->
    LiveState` reads every internal field and
    serialises the symmetric keys as raw
    `Data`.
  - New `public func restoreLiveState(_:)`
    reverses the export: it rebuilds the
    `SymmetricKey` / `Curve25519.KeyAgreement.*Key`
    values from the raw bytes and installs
    them so the next `encrypt` / `decrypt`
    call continues the chain exactly where
    the previous one left off.

* `PrivateChat/Core/Crypto/DoubleRatchetPersistence.swift`
  - `PersistedRatchetSession` gets two new
    fields:
    - `isSealed: Bool` is now meaningful:
      `false` immediately after
      `DoubleRatchetSessionFactory.makePersisted(...)`
      (initial bundle only), `true` after the
      first `persistLiveState()` call.
    - `liveState: DoubleRatchetSession.LiveState?`
      holds the live ratchet snapshot (nil
      when the session has only been
      registered and never used).
  - `DoubleRatchetSessionFactory.makeSession(from:)`
      now calls `restoreLiveState(_:)` on the
      freshly built session when the persisted
      blob carries a `liveState`. A session
      without a `liveState` is built with the
      original initial-bundle behaviour.

* `PrivateChat/Core/Services/RatchetChannel.swift`
  - New `private var
    persistedTemplate: PersistedRatchetSession`
    field holds the initial-bundle material
    so `persistLiveState()` can rebuild a
    refreshed `PersistedRatchetSession` after
    every state change.
  - `send(...)` and `receive(...)` call a new
    `persistLiveState()` after the encrypt /
    decrypt. The helper snapshots
    `session.exportLiveState()`, builds a
    `PersistedRatchetSession` with `isSealed
    = true` and `liveState` set, and writes
    it back to the store via
    `store.save(...)`. Store-write errors are
    swallowed: the on-device store failure
    must not abort an in-flight send /
    receive; the next call will trigger
    another save attempt.

* `Tests/PrivateChatTests/RatchetChannelTests.swift`
  - 3 new tests:
    - `testLiveStatePersistedAfterSend` —
      verifies the persisted `LiveState` is
      sealed, has `sendCounter == 1`, has a
      `sendChainKey`, and matches the
      envelope counter.
    - `testMultiMessageRoundTripAcrossRelaunch`
      — sends three Alice -> Bob messages,
      then **simulates an app relaunch** by
      dropping the in-memory channels and
      re-opening them from the same on-device
      stores; the rebuilt channels must
      continue the chain (Bob -> Alice,
      Alice -> Bob) without any counter
      regression.
    - `testPersistedDHKeyMatchesInMemoryKey` —
      verifies the persisted DH ratchet
      private key is 32 bytes, the send
      counter is 1, and the skipped-key
      window is empty.

**Result:** 10 iOS test suites, 0 failures, 0
XCTSkip. The Sprint 10B work closes the
"Sprint 10B pending: live-state persistence"
entry from Sprint 10's CHANGELOG: a
conversation that survives a relaunch is now
the default behaviour, not a follow-up.

**TestFlight implication:** public-beta
testers who pair, send several messages, kill
the app, and re-open it will see the v2 chain
**continue** at the exact counter position,
not reset. The Privacy Sentinel will surface a
"session on v2" finding instead of the
fallback "session still on v1" finding that
Sprint 10A would otherwise produce after a
relaunch.

### Sprint 10: v2 envelope opt-in via pairing + keychain persistence + sentinel findings (2026-06-23)

Sprint 10 closes the v2-envelope loop end-to-end.
After a fresh pairing, the iOS app now registers a
`RatchetChannel` for the new peer so subsequent
`sendMessage` calls take the v2 path automatically.
The X3DH bundle material is persisted to the iOS
keychain via `KeychainDoubleRatchetStore`, so the
v2 envelope survives an app relaunch instead of
falling back to v1. The Sentinel dashboard
(`securityAISnapshot`) now surfaces the
`RatchetSentinelFindings` for the v1-fallback /
v2-ok state per peer.

**iOS (1 file modified, +90 lines):**

* `PrivateChat/Core/Services/ConversationService.swift`
  - **Sprint 10A:** `init` now owns a
    `KeychainDoubleRatchetStore` instead of the
    previous `InMemoryDoubleRatchetStore`. The
    on-device keychain account name is
    `ratchet.<peerID>`; the service is configured
    under the existing keychain service
    `org.francois.PrivateChat.keychain`.
  - **Sprint 10C:** `importPeer(from:)` now
    delegates to a new private helper
    `registerRatchetChannelForPeer(_:encodedPayload:)`
    after the trusted-peer record has been
    appended / updated. The helper decodes the
    raw `PairingPayload` (to obtain
    `createdAt`), decodes the remote
    key-agreement and signing public keys, and
    calls `RatchetChannel.register(...)` with
    the local key-agreement private key from
    `LocalIdentity`. The result is persisted to
    the keychain; the next app relaunch picks
    the same `RatchetChannel` up via
    `ratchetStore.load(peerID:)` in
    `sendMessage` and continues the chain.
    Blocked peers (key-changed during
    re-pairing) and existing peers with a
    stored channel are intentionally skipped,
    so the ratchet state is never overwritten.
    A soft failure on `registerRatchetChannel`
    leaves the v1 path active; the next
    `refreshSecurityAIAssessment()` will emit a
    "session still on v1" finding.
  - **Sprint 10D:** `refreshSecurityAIAssessment()`
    now drains `ratchetObservations` and merges
    the findings returned by
    `RatchetSentinelFindings.build(observations:)`
    into `securityAISnapshot.findings`. The
    `summary` is rebuilt to append
    `+ N Ratchet-Finding(s) (M hart).` so the
    dashboard shows the additional context. The
    `score` and `riskLevel` stay at the v1
    baseline; ratchet findings are
    informational / warning, not critical
    regressions.

**Result:** 10 iOS test suites, 0 failures, 0
XCTSkip. Sprint 10 closes the work tracked as
"Sprint 9D is half-wired" in CHANGELOG entries
9C and 9D: the v2 path is now reachable from the
UI without any extra configuration.

**TestFlight implication:** a new build will
register a `RatchetChannel` automatically on the
first pairing. The first v2 `sendMessage` will
ticker the relay's `v2EnvelopeRequests` counter
on `/v1/relay/stats` from 0 to 1, and the
Sentinel dashboard will surface the
"session on v2" finding. The 90-day v1/v2
coexistence window now has its first real v2
is taken.

### Sprint 9D: ConversationService wired to the v2 router (2026-06-23)

Sprint 9D closes the v1 / v2 envelope loop. The
`ConversationService` now owns a
`RatchetEnvelopeRouter` and an
`InMemoryDoubleRatchetStore`. On `sendMessage` it
tries the v2 router first; if a `RatchetChannel`
is on file, the outbound packet is wrapped in a
`RatchetChannelEnvelope` (`protocolVersion: 3`),
otherwise the v1 path runs unchanged. On
`processInboundPacket` the `protocolVersion == 3`
branch routes through a new
`processInboundV2Packet` helper which uses the
Ratchet AEAD for authentication (no Ed25519
envelope-signature verify, no trusted-peer
pairwise-key derivation). Both paths emit a
`RatchetSentinelObservation` that the Privacy
Sentinel can turn into a "session still on v1"
or "session on v2" finding.

**iOS (1 file modified, +75 lines):**

* `PrivateChat/Core/Services/ConversationService.swift`
  - New private properties: `ratchetRouter`,
    `ratchetStore`, `ratchetObservations`. The
    router is initialised in `init` with a fresh
    `InMemoryDoubleRatchetStore` and a closure
    that returns `localIdentity.id` for the
    `senderID` field.
  - `sendMessage` now wraps the v1 packet in
    `RatchetEnvelopeRouter.makeRatchetPacket(...)`
    when a v2 channel is on file. The router
    returns a v2-style `OutboundTransportPacket`
    whose `protocolVersion: 3`; the v1 packet is
    still built first so the wire's
    `id`/`createdAt`/`expiresAt` are reused.
  - `processInboundPacket` now accepts both v1
    (`protocolVersion == 2`) and v2
    (`protocolVersion == 3`). The v2 branch
    delegates to a new `processInboundV2Packet`
    helper.
  - `processInboundV2Packet` decodes the
    `RatchetChannelEnvelope` via
    `RatchetEnvelopeRouter.tryDecodeV2(packet:)`,
    then runs the v1 post-decrypt pipeline
    (version check, senderID/recipientID check,
    `appendInboundMessage`) on the recovered
    `TransportMessagePayload` JSON. If the
    trusted-peer record for the sender is
    missing, a placeholder `TrustedPeer` is
    synthesised (Ratchet AEAD has already
    authenticated the sender, so the v1
    Ed25519 envelope-signature verify is
    intentionally skipped).
  - Both paths append a
    `RatchetSentinelObservation` to
    `ratchetObservations`; a future Sprint 10
    method will surface these via
    `RatchetSentinelFindings.build(...)` on the
    `securityAISnapshot` publisher.

**Result:** 10 iOS test suites, 0 failures, 0
XCTSkip. The v1 path is unchanged for any peer
that does not have a `RatchetChannel` registered;
for peers that do, the v2 path is taken
transparently.

**Persistence scope:** the
`InMemoryDoubleRatchetStore` does **not** survive
an app relaunch. Sprint 10 will swap it for
`KeychainDoubleRatchetStore`; until then,
registering a `RatchetChannel` after a relaunch
re-derives the initial-bundle material from the
pairing record. No production-tester state is
lost in the migration because the
`RatchetEnvelopeRouter` falls back to v1 if the
in-memory store is empty for a peer.

**Public-beta envelope:** unchanged for any peer
that has not yet been registered with the v2
router. The first time a tester pairs a new
peer, the iOS app can call
`RatchetChannel.register(...)` from the
`PairingView` (Sprint 10 follow-up) to opt that
conversation into the v2 envelope; the relay's
`v2EnvelopeRequests` counter on
`https://securechat.team/v1/relay/stats` will
tick from 0 to 1 the first time the opt-in path
is taken.

### Sprint 9C: v2 envelope routing (router + sentinel + counter) (2026-06-23)

Sprint 9C wires the Sprint 9B RatchetChannel into a
non-invasive router that the ConversationService can
opt into, adds the corresponding Privacy-Sentinel
findings, and tracks the v1 / v2 envelope split on
the relay.

* `PrivateChat/Core/Services/RatchetEnvelopeRouter.swift`
  (4.9 KB) -- additive v2-envelope adapter for the
  existing v1 `OutboundTransportPacket` transport.
  - `makeRatchetPacket(peerID:plaintext:existingPacket:)`
    returns a v2-style
    `OutboundTransportPacket(protocolVersion: 3, ...)`
    if a v2 channel is on file; otherwise `nil` so
    the caller falls back to v1.
  - `tryDecodeV2(packet:)` decodes a v2 envelope on
    the inbound path; returns the plaintext + a
    `RatchetSentinelObservation` or `nil` to fall
    back to v1.
  - `v1FallbackObservation(peerID:)` produces a
    sentinel observation for the v1 path.
  - The router does not touch
    `makeTransportPacket` or
    `processInboundPacket`; v1 stays 100% intact.

* `PrivateChat/Core/Services/RatchetSentinelFindings.swift`
  (3.0 KB) -- turns a batch of
  `RatchetSentinelObservation`s into
  `SecurityAIFinding`s the Privacy Sentinel can
  surface in the dashboard. The v1-fallback
  finding is collapsed (one warning, not N), the
  v2-ok finding lists the peerIDs that are
  already on v2.

* `Tests/PrivateChatTests/RatchetEnvelopeRouterTests.swift`
  (5.6 KB) -- 5 tests covering the v2 / v1 routing
  split, peer mismatch, JSON envelope decoding,
  and the v1-fallback observation.

* `Tests/PrivateChatTests/RatchetSentinelFindingsTests.swift`
  (3.1 KB) -- 5 tests covering empty / single-v1 /
  single-v2 / mixed / many-v1-collapse.

**Server (3 files, 1 new wire field):**

* `RelayServer/src/store.ts` -- cumulative
  `v1EnvelopeRequests` / `v2EnvelopeRequests`
  counters in `BaseRelayStore`, populated in
  `put()` based on `packet.protocolVersion`. The
  counters are in-memory and reset on relay
  restart; the live counter is exposed via
  `stats()` so the `/v1/relay/stats` endpoint
  surfaces them.

* `RelayServer/src/schemas.ts` --
  `outboundTransportPacketSchema` now accepts
  `protocolVersion: z.union([z.literal(2), z.literal(3)])`
  (was `z.literal(2)`), and
  `RelayStatsResponse` gets
  `v1EnvelopeRequests` / `v2EnvelopeRequests`.

* `scripts/test-relay.sh` -- 3 new assertions:
  - the `/v1/relay/stats` body contains
    `v1EnvelopeRequests` and `v2EnvelopeRequests`
  - a v2-protocolVersion POST without auth still
    returns 401 (auth gate is envelope-version
    agnostic)

**Result:** iOS test suites: 10 (was 8). All
green, 0 failures, 0 XCTSkip. The two new
RatchetChannel-related suites (Router and
Findings) add 10 tests, bringing the iOS test
count to 31.

**Live behaviour:** the live relay at
`securechat.team` is rebuilt and redeployed
during the Sprint 9C final step; the v1
envelope continues to work, and the
`v1EnvelopeRequests` / `v2EnvelopeRequests`
counters are visible on `/v1/relay/stats` for
the 90-day deprecation window.

**Wiring note (Sprint 9C is half-wired):** the
`RatchetEnvelopeRouter` is **library-complete**
and **test-complete**, but the
`ConversationService.sendMessage` /
`processInboundPacket` sites are not yet
updated to call it. They will pick up the v2
path in Sprint 9D (one-line branch). Until
then, the v1 envelope is the only path the
production iOS app exercises, and the relay's
`v2EnvelopeRequests` counter stays at 0.

### Sprint 9B: v2 envelope transport (RatchetChannel + persistence) (2026-06-23)

Sprint 9B wires the v2 Double-Ratchet library
(Sprint 9A) into a **reusable transport**
that the `ConversationService` can route
through. The wire envelope, the on-device
store, and the high-level channel are all in
place.

**New code:**

* `PrivateChat/Core/Crypto/DoubleRatchetPersistence.swift`
  (new, 7.1 KB)
  - `PersistedRatchetSession` (Codable) — the
    X3DH initial-bundle material persisted per
    `peerID`. Carries: the symmetric 32-byte
    root key, the local long-term key-agreement
    private key (for session rebuild after app
    relaunch), the remote's pre-exchanged
    long-term public key, both
    `PairingPayload.createdAt` timestamps, and
    a `sessionID` derived from the root key.
  - `DoubleRatchetSessionFactory.makeSession(from:)`
    rebuilds a `DoubleRatchetSession` from a
    `PersistedRatchetSession`.
  - `DoubleRatchetSessionFactory.makePersisted(...)`
    derives the symmetric root key from the
    X3DH agreement and packages it for storage.

* `PrivateChat/Core/Services/DoubleRatchetStore.swift`
  (new, 4.0 KB)
  - `DoubleRatchetStoring` protocol with
    `save`, `load(peerID:)`, `delete(peerID:)`,
    `listPeerIDs`.
  - `InMemoryDoubleRatchetStore` (tests,
    previews).
  - `KeychainDoubleRatchetStore` (production,
    uses `KeychainStoring`). Keychain account
    is `ratchet.<peerID>`.
  - `DoubleRatchetStore.defaultEncoder/Decoder`
    for ISO-8601 dates on the JSON wire.

* `PrivateChat/Core/Services/RatchetChannel.swift`
  (new, 5.5 KB)
  - `RatchetChannelEnvelope` (Codable) — the
    outer v2 wire envelope. Carries
    `{ v: 2, peerID, ratchet: WireMessage }`.
    The `peerID` field is the **sender's**
    local-identity peer ID, so the receiver
    can route to the right inbound channel.
  - `RatchetChannel` — high-level
    encrypt/decrypt with persistence
    (`register(...)` after pairing,
    `open(peerID:store:)` on app launch).
  - `ChannelError.peerMismatch` /
    `.sessionMismatch`.

* `Tests/PrivateChatTests/RatchetChannelTests.swift`
  (new, 5.5 KB) — 7 tests:
  - `testRegisterPersistsX3DHBundle`
  - `testSingleMessageRoundTrip`
  - `testMultiMessageRoundTrip`
  - `testEnvelopeIsJSONEncodable`
  - `testPeerMismatchRejected`
  - `testOpenReusesPersistedSession`
  - `testOpenReturnsNilWhenNoSession`

**Result:** 8 iOS test suites pass (was 7),
0 failures, 0 XCTSkip. New test count: 7
RatchetChannel tests, all green.

**Persistence scope:** the store holds only
**initial-bundle** material. After the first
message is sent, the live ratchet state
(rotated DH ratchet keypair, in-flight chain
keys, skipped-message window) is not yet
persisted. Sprint 9C will route the
`ConversationService` through `RatchetChannel`
and add a Privacy Sentinel "session still on
v1" finding; Sprint 10 will add live-state
persistence via a `DoubleRatchetSession.State`
Codable export.

**Public-beta envelope:** unchanged. The
v1 Curve25519 envelope (ADR-002) is still the
live transport on `securechat.team`. The
v2 envelope is **library-complete**,
**test-complete**, and **ready for
opt-in** in Sprint 9C.

### Sprint 9A: Double Ratchet round-trip (ADR-007 resolved) + X3DH refactor (2026-06-23)

**Sprint 9A resolves ADR-007.** All 7
`DoubleRatchetSessionTests` now pass; 0 XCTSkip.
The AES-GCM `authenticationFailure` was traced to
a counter / kdfCK double-call on the receive
path, not to the DH-ratchet step itself.

**X3DH:**

* `X3DHAgreement.deriveRootKey` now takes both the
  remote's `keyAgreementPublicKey` and
  `signingPublicKey` (the two long-term Curve25519
  keys in the `PairingPayload`). The signing key is
  reserved for a future identity-binding extension;
  today the root key still comes from a single
  ECDH, but the surface is in place.
* The HKDF info string bumped to
  `SecureChatX3DHv3` to keep root keys for older
  pairing payloads from accidentally matching
  v3-derived ones during the 90-day coexistence
  window (Sprint 9C).

**Double Ratchet (the fix):**

* `decrypt` skipped-message loop condition changed
  from `while recvCounter < message.counter` to
  `while recvCounter < message.counter - 1`. The
  loop now fills only **gaps** for out-of-order
  delivery; the final step is left to the next
  block which calls `kdfCK` once and matches the
  sender's per-message count. Before the fix, the
  receive side ran `kdfCK` once for every message
  counter `<= message.counter` instead of
  `< message.counter`, so the receiver's
  `finalMessageKey` diverged from the sender's
  `messageKey` by exactly one chain-KDF step.
  `AES.GCM.open` then correctly rejected the
  ciphertext as `authenticationFailure`.
* `recvCounter += 1` moved **before** the
  `skippedMessageKeys.append` in the same loop, so
  the counter stored in the skipped-key table
  matches the sender's `sendCounter` (which is
  incremented before the wire message is built).

**Tests:**

* The 5 `XCTSkip` markers in
  `DoubleRatchetSessionTests` are gone. All 5
  round-trip tests run for real:
  - `testFirstMessageRoundTrip`
  - `testMidChainMessage`
  - `testDHRatchetStepOnTurnChange`
  - `testOutOfOrderDelivery`
  - `testForwardSecrecyByPastKeyEviction`
* Plus the 2 sanity tests that already ran:
  - `testX3DHRootKeyDerivationIsSymmetric`
  - `testVersionRejection`
* **Result: 7/7 DoubleRatchet tests pass.**

**Docs:**

* `Docs/ADR-007-double-ratchet-first-step.md` —
  Status flipped from "Known issue" to
  "**Resolved in Sprint 9**", with a new
  `## Resolution` section explaining the actual
  cause and the fix.

**Public-beta envelope:** unchanged. Public-beta
testers still use the v1 Curve25519 envelope from
ADR-002; the v2 Double Ratchet envelope is now
end-to-end correct in the iOS library and will be
activated in Sprint 9B (`ConversationService`
adapter) and Sprint 9C (90-day v1/v2 coexistence
+ relay stat counter).



### Sprint 8: X3DH initial-bundle shipped; Double Ratchet first-step DH asymmetry documented (2026-06-23)

X3DH and the Double Ratchet library are now
code-complete primitives in `PrivateChat/Core/Crypto/`.
The X3DH root-key derivation is **symmetric and
verified** by a passing test
(`testX3DHRootKeyDerivationIsSymmetric`), and the
v2 wire envelope (ADR-006) is well-formed
(`testVersionRejection` passes). Five round-trip
tests are marked `XCTSkip` with a Sprint-9
pointer; the underlying issue (a counter /
kdfCK double-call on the receive path) was
misdiagnosed in Sprint 8 and is fixed in Sprint 9
(ADR-007 resolved, all 7 tests pass).

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
