# ADR-006: Double Ratchet for SecureChat

## Status

Designed (Sprint 7, 2026-06-22)
Implementation: deferred to Sprint 8 (see "Open work" below).

## Context

SecureChat's current messaging protocol (ADR-002) uses
**static Curve25519 keypairs per device**. When a peer rotates
its keypair (e.g. on a fresh install, or after a manual
"rotate my key" gesture), the partner's Safety Number flips
without warning, the partner sees a `peerKeyChanged` event,
and the channel is at risk of being silently re-keyed under
an attacker who tricked the user into accepting the new key.

This is acceptable for a public beta where the threat model is
"honest-but-curious relay", but it is **not** the security
posture a privacy messenger should ship with. The protocol
needs **per-message ratcheting** so that a compromise of the
current key state does not reveal past messages
(**forward secrecy**) and so that a compromise of the next
key state does not reveal future messages (**post-compromise
security**, sometimes called "future secrecy").

The canonical construction for these properties is the
**Double Ratchet** algorithm as specified in the Signal
Protocol (libsignal). It combines:

- a **Diffie-Hellman ratchet** that produces a new DH keypair
  per turn (giving post-compromise security), and
- a **symmetric-key ratchet** (a hash chain, HKDF) that
  produces a new message key per send (giving forward
  secrecy).

## Decision

We add a Double Ratchet session layer **on top of** the
existing Curve25519 envelope (ADR-002). The envelope is the
**transport** (each message is one envelope); the Double
Ratchet is the **per-session key derivation** that lives
inside the envelope's encrypted payload.

### Wire format

A Double Ratchet message is a JSON object that is then
serialised as a `SecureChat` envelope's `payload` field:

```json
{
  "v": 2,
  "sessionID": "<hex 32 bytes>",
  "ratchetPK": "<base64 curve25519 public key, 32 bytes>",
  "counter": 42,
  "prevChainLen": 4,
  "ciphertext": "<base64 AES-GCM ciphertext, 16-byte tag>"
}
```

* `v` is the ratchet version; receivers MUST reject unknown
  versions (so a v2 → v3 rollout is a flag day, not silent).
* `ratchetPK` is the **current** DH ratchet public key for the
  sender. Receivers trigger a DH ratchet step on this field's
  change.
* `counter` is the number of messages sent in the **current**
  chain. The receiver uses it to know which message key in
  the chain to use.
* `prevChainLen` is the number of messages in the **previous**
  chain. The receiver uses it to know how many skipped
  message keys to keep around (for out-of-order delivery).
* `ciphertext` is `AES-GCM-encrypt(key, plaintext, AAD)` where
  `AAD = sessionID || ratchetPK || counter` and `key` is the
  per-message key from the symmetric ratchet.

### Session lifecycle

1. **First contact:** the iOS app's existing pairing flow
   exchanges a `X3DH`-style initial bundle: identity key
   (Curve25519), signed prekey (Curve25519, signed by
   identity), ephemeral prekey (Curve25519, one-time). The
   initial bundle becomes the **root key** of the Double
   Ratchet session.

2. **Ratchet step on send:** when the local side sends the
   first message in a new "turn", it generates a fresh DH
   ratchet keypair (`ratchetPK`), performs the DH agreement
   against the remote's previous `ratchetPK`, and ratchets
   the **root key** and the **next chain key** forward. The
   new chain key produces a per-message key.

3. **Ratchet step on receive:** when the remote side sees a
   new `ratchetPK`, it performs the same DH agreement, derives
   the new chain key, and continues.

4. **Out-of-order tolerance:** a receiver keeps skipped
   message keys in a bounded LRU keyed by `(chainKey, counter)`
   so that a 30-message backlog of out-of-order messages
   still decrypts.

5. **Session reset:** the user can manually trigger a "rotate
   session" gesture. This generates a new `sessionID`,
   re-runs the X3DH initial bundle, and discards the old
   session state. It is the privacy-sentinel-approved escape
   hatch from a session that has been open for too long.

### Forward-secrecy + post-compromise-secure guarantees

* **Forward secrecy** comes from the symmetric ratchet: a
  message key is consumed exactly once and then deleted. An
  attacker who steals the current chain key cannot recover
  any past message key, because the past keys were
  discarded.
* **Post-compromise security** comes from the DH ratchet:
  every DH ratchet step (one per turn) mixes in a fresh
  ephemeral key. An attacker who steals the current root
  key can no longer decrypt new messages once a new DH
  ratchet step has happened.

The session is **not** automatically ratcheting on **every**
message, only on **turn changes** (i.e. when the active
sender changes). This is the standard Double Ratchet cadence
and matches the Signal Protocol.

### Key material storage

* Long-term identity key: stays in iOS Keychain (Secure
  Enclave when available, fallback to Keychain with
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`).
* Per-session root key and chain keys: in-memory only, never
  written to disk. A session that is closed (timeout, manual
  reset, app reinstall) cannot be recovered.
* Skipped message keys: in-memory only, capped at 2000 per
  session, evicted FIFO.

## Consequences

* A new `DoubleRatchetSession` Swift class lives at
  `PrivateChat/Core/Crypto/DoubleRatchetSession.swift`. It
  depends only on `CryptoKit` (no third-party crypto).
* `ConversationService` (the iOS message router) gains a
  thin adapter that calls into `DoubleRatchetSession` for
  encrypt-on-send and decrypt-on-receive, and a fallback
  that uses the existing Curve25519 envelope when the
  session is not yet established.
* The **canonical ADR-002 envelope** is **unchanged** on the
  wire: the Double Ratchet message lives inside the existing
  `payload` field. This keeps the relay contract stable and
  the public-beta path unbroken.
* The first public-beta-with-Double-Ratchet build will ship
  with `v: 2` envelopes; legacy `v: 1` envelopes are
  accepted for a 90-day window. The Privacy Sentinel surfaces
  a finding for "session still on v1" so beta-testers can
  see when a peer is on the older protocol.

## Open work (deferred to Sprint 8)

The Double Ratchet header and the iOS session class are
**not yet written** in this ADR. Sprint 8 will:

1. Write `DoubleRatchetSession.swift` with:
   * `init(rootKey:initialChainKey:initialRatchetPK:)`
   * `ratchetOutgoing() -> (newRootKey, newRatchetPK, newChainKey)`
   * `ratchetIncoming(remotePK:) -> (newRootKey, newChainKey)`
   * `messageKey(for counter:) -> SymmetricKey`
   * `skippedKey(for chain:counter:) -> SymmetricKey?` (LRU)
2. Write the JSON wire format above and a serializer in
   `SecureChatEnvelope+Crypto.swift`.
3. Add `DoubleRatchetTests` covering: first message, mid-chain
   message, DH ratchet step, out-of-order delivery,
   session-reset, past-key-eviction.
4. Update the relay **only** to count `v: 2` envelopes in
   the existing `/v1/relay/stats` endpoint (no wire change).

## References

* Signal Protocol — *The Double Ratchet Algorithm* (libsignal
  documentation).
* ADR-002 — current envelope + Curve25519 + AES-GCM.
* ADR-004 — Privacy Sentinel; the new "session still on v1"
  finding plugs into the existing `assess(...)` function.
* `PrivateChat/Core/Crypto/` — where the new
  `DoubleRatchetSession.swift` will live.
