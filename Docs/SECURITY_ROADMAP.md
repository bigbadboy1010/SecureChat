# Security Roadmap

## Phase 1 — Stabilised baseline

Status: implemented in this package.

- One app entry point.
- Correct app identity: `org.francois.PrivateChat` / `PrivateChat`.
- Legacy code outside app target.
- Local encrypted store.
- Keychain-backed identity keys and database key.
- Trust store outside UserDefaults.
- Manual pairing with safety number verification.
- Optional relay transport scaffold.

## Phase 2 — Pairing and identity hardening

- Add QR-code pairing scanner/generator.
- Add signed pairing payloads.
- Add peer key-change blocking UX.
- Add Safety Number compare screen.
- Add deterministic pairwise context derivation tests.

## Phase 3 — Messaging protocol

- Add packet envelope with version, sender, recipient, timestamp, TTL, message ID and payload length.
- Authenticate all envelope metadata via AEAD AAD.
- Add replay protection with monotonic counters per sender.
- Add inbox polling for relay mode.
- Add direct local transport again only after authentication is enforced.

## Phase 4 — Double Ratchet

- Integrate the existing legacy Double Ratchet only after it is isolated behind tests.
- Add skipped-message-key cache limits.
- Add sender/receiver chain persistence encrypted at rest.
- Add test vectors.

## Phase 5 — Groups and channels

- Implement sender keys for groups.
- Never mark group messages as encrypted without a real group crypto path.
- Add member removal rotation.
- Add admin/member signature rules.

## Phase 6 — Production relay

Relay must remain zero-knowledge:

- It stores only opaque encrypted packets.
- It never receives plaintext, private keys, group keys or message bodies.
- It enforces TTL and packet-size limits.
- It should not require a phone number.
- It should support rate limits and abuse controls.
