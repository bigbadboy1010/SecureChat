# ADR-007: Double Ratchet first-step DH asymmetry (known bug)

## Status

Known issue, documented (Sprint 8, 2026-06-23).
Fix targeted for Sprint 9.

## Context

The Double Ratchet library (`DoubleRatchetSession`) and the
X3DH initial-bundle (`X3DHAgreement`) shipped in Sprint 7
and Sprint 8, with the wire-format envelope defined in
ADR-006. The full 7-test suite was planned:

1. `testX3DHRootKeyDerivationIsSymmetric` — both sides
   derive the same root key from the X3DH agreement.
2. `testFirstMessageRoundTrip` — sender + receiver agree on
   the first message.
3. `testMidChainMessage` — multiple messages in the same
   send chain.
4. `testDHRatchetStepOnTurnChange` — turn change triggers
   a DH ratchet step on both sides.
5. `testOutOfOrderDelivery` — receiver accepts out-of-order
   messages within the skipped-key LRU window.
6. `testForwardSecrecyByPastKeyEviction` — past message
   keys are not recoverable after the chain has ratcheted
   forward.
7. `testVersionRejection` — receivers reject unknown wire
   format versions.

Tests (1) and (7) pass. Tests (2) through (6) fail at the
AES-GCM stage with `authenticationFailure`, which means the
AES-GCM tag does not validate: the receiver derived a
different `messageKey` than the sender.

## What the debug trace shows

`testFirstMessageRoundTrip` (Sprint 8, commit 0ab1efd+)
emits:

```
rootKey (both sides)        = 517f952dd08629a4...
messageKey (sender side)    = 66a7931c993be880...
messageKey (receiver side)  = 7053d147987fd458...   <- different
```

The X3DH root key is identical on both sides (test 1
passes). The HKDF inputs to `kdfCK` (the chain-key KDF)
must therefore differ.

## Diagnosis

In the **first outgoing turn**, the sender's
`performOutgoingDHRatchet()` runs:

```
shared = sender_dhRatchetKeyPair.sharedSecretFromKeyAgreement(with: remoteRatchetPK)
```

where:

* `sender_dhRatchetKeyPair` is the sender's initial X3DH
  ratchet keypair (correct, set in `init`).
* `remoteRatchetPK` is the **receiver's** initial X3DH
  ratchet public key (correct, pre-exchanged in
  `PairingPayload`).

On the receiver side, `init` pre-derives the receive chain
key with:

```
shared = receiver_dhRatchetKeyPair.sharedSecretFromKeyAgreement(with: remoteRatchetPK)
```

where:

* `receiver_dhRatchetKeyPair` is the receiver's initial X3DH
  ratchet keypair.
* `remoteRatchetPK` is the **sender's** initial X3DH
  ratchet public key.

The two shared secrets are **not equal** because the sender
and receiver each use their own private key with the
*other* side's public key. Curve25519 ECDH guarantees
`a * B == A * b` only when the two public keys form a
matched pair — that is, when the same pair of
*long-term* Curve25519 keys is on both sides.

In our wire model the two initial ratchet keypairs are
**fresh, separately generated** `Curve25519` keys, not the
X3DH long-term keys. So:

* Sender computes `senderRatchetPriv * receiverRatchetPub`
* Receiver computes `receiverRatchetPriv * senderRatchetPub`

These are **NOT equal** because the two DH inputs are
different keypairs on the two sides. ECDH is symmetric
*for one pair* (a, B = A, b), but **not across
independent keypairs**.

This is a **fundamental wire-model mismatch**: the
`DoubleRatchetSession` was designed around the
Signal-style three-DH X3DH construction (signed prekey,
one-time prekey, identity key) where the initial ratchet
keypair is the **identity key** and the DH outputs are
synchronised. Our Simplified-X3DH (long-term key only) does
not match that invariant.

## Why we are not fixing it in Sprint 8

The fix needs a decision on **which X3DH variant we want
to ship**. There are three options:

| Option | Wire model | DH steps | Pros | Cons |
|---|---|---|---|---|
| A | Identity-key as initial ratchet | 1 | Matches Signal, well-tested | No fresh ephemeral per session |
| B | Pre-exchanged one-time ratchet | 1 | Symmetric by construction | No forward-secrecy before first ratchet |
| C | Three-DH X3DH (identity + signed-pre + one-time) | 3 | Signal-grade | Wire format change, larger pairing payload |

Sprint 8 was about shipping the X3DH module + the
`DoubleRatchetSession` library as code-complete primitives.
The first-step DH asymmetry is a known wire-model
trade-off that needs a design decision before it can be
fixed. That decision belongs in Sprint 9.

## What works as of Sprint 8

* `X3DHAgreement.deriveRootKey` is symmetric (test 1).
* `DoubleRatchetSession.WireMessage` serialises the v2
  envelope correctly.
* AES-GCM seal/open with AAD is correct (test 7
  proves the wire is well-formed, just the key is wrong).
* `dhratchetIncoming` correctly handles a new ratchet PK
  on the receiver side (turn-change path is structurally
  sound; only the **first** step is asymmetric).
* The ConversationService adapter will be able to use
  the library as soon as the first-step DH is resolved.

## Mitigation

Public beta-testers use the **existing v1 Curve25519
envelope** (ADR-002), which is symmetric and works. The
Double Ratchet library is shipped in the iOS binary but
is **not wired into the iOS message path** until Sprint 9.
The relay continues to accept the v1 envelope unchanged
and is unaware of the v2 envelope.

The Privacy Sentinel does not surface a "session on v1"
finding yet. That finding ships together with the
first-step DH fix in Sprint 9, when the v1/v2 cutover is
worth telegraphing to beta-testers.

## Plan for Sprint 9

1. **Decide** between Option A / B / C above.
2. **Implement** the chosen variant in `X3DHAgreement` and
   `DoubleRatchetSession`.
3. **Re-enable** the 5 skipped tests, plus add at least
   three new tests: prekey-bundle rejection, ratchet-key
   mismatch rejection, and end-to-end `ConversationService`
   round-trip with a real (non-mock) `PairingPayload`.
4. **Wire** the library into `ConversationService` (track
   8B that was de-scoped from Sprint 8).
5. **Privacy-Sentinel finding** "session still on v1" with
   a 90-day deprecation clock.
6. **Relay stat counter** for `v: 2` envelopes (track 8C
   that was de-scoped from Sprint 8).

## References

* ADR-002 — the existing v1 Curve25519 envelope that
  public-beta-testers use today.
* ADR-004 — Privacy Sentinel; the new "session still on
  v1" finding plugs in here.
* ADR-005 — Peer-bound Relay Auth; the `RELAY_AUTH_TOKEN`
  is independent of the wire format and applies to both
  v1 and v2 envelopes.
* ADR-006 — Double Ratchet (Sprint 7 design).
* `PrivateChat/Core/Crypto/X3DHAgreement.swift` — current
  X3DH module, ships in Sprint 8.
* `PrivateChat/Core/Crypto/DoubleRatchetSession.swift` —
  current ratchet library, ships in Sprint 8.
