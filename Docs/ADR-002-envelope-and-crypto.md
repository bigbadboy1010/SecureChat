# ADR-002: Envelope shape and Curve25519 / AES-GCM construction

**Status:** Accepted
**Date:** 2026-06-22
**Supersedes:** none

## Context

The relay is a public, unauthenticated-on-the-inside service. It
cannot see plaintext. But it also cannot be a black box; the
envelope has to be auditable, the wire format has to be stable
across versions, and the cryptographic construction has to be
verifiable by an external auditor without reading application
source.

## Decision

The wire envelope is:

```json
{
  "protocolVersion": 2,
  "id": "uuid-v4",
  "senderID": "64-hex peer id",
  "recipientID": "64-hex peer id",
  "sealedPayloadBase64": "base64 of AES-GCM ciphertext",
  "signatureBase64": "base64 of Ed25519 signature",
  "createdAt": "RFC 3339 with offset",
  "expiresAt": "RFC 3339 with offset"
}
```

The envelope is built in five steps on the sending side:

1. Generate a per-message symmetric key (`SymmetricKey(size:
   .bits256)`).
2. Encrypt the message body to that key with AES-GCM
   (`AES.GCM.seal`).
3. Encrypt the symmetric key to the recipient's Curve25519 public
   key. We use Apple's `CryptoKit.Curve25519.KeyAgreement` API in
   the iOS app: ECDH yields a shared secret, HKDF-SHA256 derives
   an AEAD key, and the symmetric key is wrapped with AES-GCM.
   This is the same construction as Apple's `combined-seal` API,
   and it is what `sealWithRecipientPublicKey` returns in
   `PrivateChatKit`.
4. Sign the whole envelope (sender, recipient, ciphertext,
   timestamps) with the sender's Ed25519 signing key
   (`Curve25519.Signing`).
5. POST the envelope to the relay at
   `https://relay.securechat.team/v1/relay/messages`.

On the receiving side:

1. Poll the relay at
   `https://relay.securechat.team/v1/relay/messages?recipientID=...`.
2. Open the envelope with the recipient's Curve25519 private key
   (`openSealedBox` in the iOS app's CryptoService).
3. Verify the Ed25519 signature with the sender's Curve25519
   signing public key. Reject the packet on signature failure.
4. Verify the timestamps. Reject the packet on expiry or
   excessive clock skew.
5. Decrypt the body, hand to the chat UI.
6. POST an ack to `/v1/relay/messages/:packetID/ack`. The relay
   deletes the packet.

## Consequences

- The `protocolVersion` field is the forward-compatibility hook.
  When the envelope shape changes in a non-backwards-compatible
  way, the relay rejects the packet with a 400 + a stable error
  code; the iOS app surfaces a "please update" message.
- The relay never holds the recipient's private key, so it cannot
  decrypt the symmetric key, so it cannot decrypt the body. This
  is the property that makes the threat model hold.
- The Ed25519 signature is over the canonical envelope (sender,
  recipient, ciphertext, timestamps). A relay cannot rewrite any
  field without invalidating the signature.
- The TTL + clock-skew window is the only defence against
  replay. A captured-and-resent envelope will pass signature
  verification but will fail the `expiresAt > now > createdAt -
  clockSkew` check. The relay enforces this on the receive side;
  the iOS app enforces it on the open side as a second line of
  defence.
- The 64-hex peer ID is derived from the user's public key by
  hashing. The peer ID is **not** a secret; the relay can see it.
  The threat model accepts that a network observer can correlate
  traffic by peer ID, and the privacy policy reflects that.
- The `sealedPayloadBase64` and `signatureBase64` sizes are bounded
  by `MAX_PACKET_BYTES` (default 128 KiB). The relay enforces
  this on the receive side; the iOS app enforces it on the send
  side.

## Alternatives considered

- **Signcryption.** Considered. A combined sign+encrypt operation
  (like Apple's `combined-seal` API) is a one-pass equivalent of
  what we do in three. We chose the three-step form because it
  is auditable: each step is a well-known primitive, and an
  external reviewer can verify them in isolation.
- **MLS / Message Layer Security.** Considered. MLS is the IETF
  standard for group messaging. It is overkill for the v0.1
  shape (1:1 chat), and it adds a protocol complexity cost that
  we are not yet ready to take on. v0.2 may re-evaluate.
- **NaCl / libsodium.** Considered for the lower-level primitives.
  We use Apple's CryptoKit because it is the iOS-native, audited,
  and zero-dependency option. Cross-platform (Android, desktop)
  builds would use libsodium.
- **Per-peer, long-lived symmetric key instead of Curve25519
  agreement.** Rejected. Long-lived symmetric keys have to be
  stored on the device and rotated manually, which is the
  X3DH-style key-bundle problem. Curve25519 + per-message
  symmetric key is simpler operationally.
