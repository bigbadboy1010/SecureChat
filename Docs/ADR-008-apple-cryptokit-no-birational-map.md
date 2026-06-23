# ADR-008: Apple CryptoKit has no Ed25519 → X25519 birational map (2026-06-23)

## Status

**Open / post-1.0.** Sprint 11B attempted the
2-DH X3DH form (adding
`DH(local_KA_priv, remote_signingPub_as_X25519)`
to the existing single-DH agreement). The
attempt failed because Apple CryptoKit does
**not** expose the Ed25519 → X25519 birational
map. This ADR records the research, the
two failed workarounds, and the recommended
path forward.

## Context

X3DH (Signal's "Extended Triple Diffie-
Hellman") specifies that the initial-bundle
key agreement runs **two or three** DH
agreements, including one DH that uses the
**signing** public key of the remote as if it
were an **X25519 key-agreement** public key.
This binds the resulting root key to the
remote's identity (the signing key), so a
MITM who swaps the signing key in transit
produces a different root key on both sides.

The Ed25519 signing curve and the X25519
key-agreement curve are **birationally
equivalent** — the same scalar `a` produces
the same shared secret on both curves, but
the 32-byte wire format is **not** the same:

* Ed25519 stores a *compressed Edwards
  point*: `(Y, sign(X))` packed into 32
  bytes.
* X25519 expects a *Montgomery
  U-coordinate*: 32 bytes that are the
  u-coordinate of the equivalent point on
  the Montgomery curve.

A correct X3DH implementation must apply
the birational map `u = (1 + y) / (1 - y)
mod p` (and the inverse for the private key)
before using the bytes as X25519 inputs.

## Sprint 13G research

We tested `Curve25519.KeyAgreement.PublicKey(
rawRepresentation: ed25519_pub_raw)` in
Apple CryptoKit (Sprint 13G test script
`/tmp/sprint13g-test3.swift`).

**Result:** the init **succeeds**, but the
output raw bytes are **identical** to the
input ed25519 raw bytes:

```
ed25519 pub:    a6804c36c087c5dcfa743025a6dd80549a218333d4bbf62b271f3f4efc7179f8
x25519 (from ed25519) pub: a6804c36c087c5dcfa743025a6dd80549a218333d4bbf62b271f3f4efc7179f8
```

Apple CryptoKit treats the ed25519 raw bytes
as a *raw Montgomery U-coordinate* — i.e. it
**does not** apply the birational map. The
resulting "X25519 public key" is a *different
point* on the curve than what the birational
map would produce. A DH agreement against
this point:

* is not symmetric with the DH agreement
  the remote party would compute (because
  the remote party's ed25519 bytes also pass
  through the same no-op, but the *intended*
  symmetric map is not applied on either
  side);
* does not commit the root key to the
  remote's identity (the signing key has
  no influence on the DH output beyond
  being 32 arbitrary bytes).

This is exactly the bug that broke the
Sprint 11B `RatchetChannelTests` and
`DoubleRatchetSessionTests` symmetry
assertions.

## Sprint 11B failed workarounds

Sprint 11B tried two workarounds before
reverting to single-DH:

1. **2-DH with `force_try` birational
   map.** The first attempt was to wrap
   `Curve25519.KeyAgreement.PublicKey(
   rawRepresentation: ed25519_pub_raw)` in
   a `force_try`. As Sprint 13G confirmed,
   the init succeeds but the output is the
   raw bytes unchanged, so the resulting
   "X25519" point is cryptographically
   meaningless.

2. **1.5-DH with HMAC over the remote
   signing public key.** The second attempt
   was to keep the canonical X25519 DH
   (`DH(local_KA_priv, remote_KA_pub)`) and
   mix `HMAC-SHA256(DH_output, remote_signingPub_raw)`,
   truncated to 16 bytes, into the HKDF
   info string. The HMAC breaks the X3DH
   symmetry invariant: Alice hashes Bob's
   signing key, Bob hashes Alice's signing
   key, so the two info strings differ and
   the two root keys are no longer equal.
   The `RatchetChannelTests` caught this
   with `XCTAssertEqual(aliceRoot, bobRoot,
   ...)`.

## Recommended path forward

A correct 2-DH X3DH implementation in
SecureChat requires one of:

1. **Manual birational map in Swift.** About
   60 lines of curve-arithmetic code (modular
   inverse, field arithmetic, etc.). The
   code is security-critical: an off-by-one
   or non-constant-time comparison loses
   forward secrecy. **This is not a 1-day
   task** and must be reviewed by an external
   cryptographer.

2. **Swift package with a pre-audited
   birational-map implementation.** No first-
   party Apple package exposes this; third-
   party options (`GopenSSH`, `Krypton`,
   `OpenSSL`-via-`CSwift`) are unmaintained
   or large dependency trees. A pre-1.0
   `swift-birational` package would be a
   real project on its own.

3. **Switch the iOS key model to a single
   Curve25519.KeyAgreement long-term key.**
   Drop the separate Ed25519 signing key and
   use a side-channel HMAC for the
   "signing" property. This is a wire-format
   break (every existing pairing is reset) and
   a sizeable schema migration.

None of the three are appropriate for the
SecureChat Public-Beta track (Sprint 1-12,
9.2/10). The single-DH agreement + v1
envelope signing (Sprint 7) gives the same
MITM-detection property at a known
acceptable cryptographic risk; ADR-007 and
the file header of `X3DHAgreement.swift`
document the trade-off.

## Decision

**Defer the 2-DH X3DH upgrade to a
dedicated crypto-refresh sprint,
post-1.0, with external review.** Mark the
`X3DHAgreement.swift` birational-map
extension as `@available(*, unavailable,
message: "see ADR-008 — use a manual
birational map or switch to single-key
model in a post-1.0 crypto-refresh")` so the
extension is not accidentally used in a
future sprint.

## Consequences

* Public-Beta crypto posture is documented
  as **single-DH X3DH + v1 envelope
  signing**, not full 2-DH X3DH. The
  Privacy Sentinel header (Sprint 12-1) and
  the README "Production Candidate"
  footnote already reflect this.
* The "Production Candidate ⚠️" status in
  the README and the
  "external security audit still
  recommended" sentence stand until a
  proper crypto-audit sprint.
* The pre-11B birational-map extension in
  `X3DHAgreement.swift` is marked
  unavailable; new code paths that try to
  use it will get a compile-time error.
