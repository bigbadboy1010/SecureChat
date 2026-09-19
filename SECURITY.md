# SecureChat Security Policy

SecureChat is an end-to-end encrypted iOS messenger under active beta
development. The current public client has **not** completed an
independent external security audit.

## Supported client

- Product: SecureChat
- Xcode target / scheme: `PrivateChat`
- Bundle ID: `org.francois.PrivateChat`
- Current TestFlight candidate: 1.4.2 (Build 13)
- Minimum iOS: 16
- Canonical relay: `https://relay.securechat.team`

The relay implementation and deployment configuration are maintained
in a private operator repository. The public client repository must
not claim that secrecy of the relay implementation is a security
boundary: message confidentiality is intended to come from client-side
cryptography, authenticated peer identities and HTTPS transport.

## Current cryptographic posture

The active TestFlight/Release message path uses:

- X25519 pairwise key agreement
- HKDF-SHA256
- AES-GCM authenticated encryption
- Ed25519 transport-envelope signatures
- Keychain-backed long-term identity keys
- SC2 pair-bound Safety Numbers derived from both peers' signing keys

The in-tree Double Ratchet work is experimental and disabled on the
active TestFlight/Release transport path until a dedicated
cryptographic review is complete. Do not report SecureChat as
Signal-protocol compatible or as having an externally reviewed Double
Ratchet.

## Reporting a vulnerability

Do not open a public GitHub issue for a vulnerability.

Email: **security@securechat.team**

Include:

- affected app/build or relay version
- reproduction steps
- expected and observed behavior
- security impact
- proof-of-concept details when appropriate

PGP is not currently advertised as an available reporting mechanism.
Do not publish a fake or placeholder PGP fingerprint.

## Security assumptions

The relay is treated as untrusted with respect to message plaintext.
A malicious client build, compromised unlocked endpoint, stolen
long-term private keys, or a user approving the wrong Safety Number
can break the intended security model.

The client therefore requires out-of-band Safety Number verification
before a peer becomes trusted. Legacy fingerprints are migrated to SC2
and previous verification is invalidated.

## Out of scope for current beta claims

- independently audited security
- anonymous traffic analysis resistance
- metadata-hiding relay guarantees
- reviewed post-compromise security
- production Double Ratchet guarantees
- group sender-key security
- protection of an already unlocked compromised device

Security advisories should be published through GitHub Security
Advisories after coordinated remediation.
