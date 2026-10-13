# PrivateRoom security policy

PrivateRoom is under active development as a **closed owner beta**. The 13 October 2026 integration candidate is **1.5.0 (15)**. A new Apple upload, TestFlight release or App Store publication has not been established by this review. An independent external protocol/application audit has **not** been completed.

Do not use the beta for high-sensitivity communication. The product does not promise absolute privacy, complete anonymity, forward secrecy, post-compromise recovery or protection of an already compromised endpoint.

## Current client and status

- Public product: PrivateRoom.
- Technical Xcode target/scheme: `PrivateChat`.
- Existing bundle identifier: `org.francois.PrivateChat`.
- iPhone/iPad baseline: iOS 16 or later; build with an appropriate installed Xcode SDK.
- Canonical public host: `https://securechat.team`.
- Hardened relay/site candidate: isolated canary until an accepted controlled public cutover.
- Acceptance and publication record: [13 October review](Docs/PRIVATEROOM-REVIEW-2026-10-13.md).

Source-level implementation, local tests, device acceptance, CI success and public deployment are different claims. Publish the exact scope that has evidence. Older phase/sprint or release notes are historical and do not establish the current security posture.

## Active cryptographic posture

The active protocol-2 channel uses static X25519 identity agreement, HKDF-SHA256, AES-GCM authenticated encryption and Ed25519 envelope signatures. Private keys and local-store keys use device-bound Keychain protection. SC3 fingerprints bind both parties' signing **and** key-agreement public keys. Signed version-3 pairing proves possession of the advertised signing key; it does not establish the real person's identity.

Users must compare SC3 on both devices over a trusted second channel before approving contact messaging. Legacy SC2 verification cannot silently remain trusted after migration, and substituted/changed keys require renewed verification.

The active channel has **no forward secrecy or post-compromise security**. Experimental ratchet work is disabled and has not received a dedicated independent protocol audit. Do not describe PrivateRoom as Signal-protocol compatible, audited Double Ratchet, post-quantum secure or metadata-free.

Using Apple CryptoKit does not audit PrivateRoom's protocol, enrollment, state transitions, persistence or interface. Future OpenMLS evaluation is documented in the [review](Docs/PRIVATEROOM-REVIEW-2026-10-13.md#future-protocol-work); it is not active functionality.

## Access, storage and metadata

The candidate centrally invalidates user sessions on lock/background, covers inactive presentation and rejects stale authentication completion. Sensitive actions and delayed work are bound to the current user session. Open camera/share/preview/system surfaces require separate device verification; code checks alone are not an absolute screen-capture guarantee.

Messages, drafts and attachments are locally encrypted and excluded from cloud backup. Device-bound keys mean recovery after loss, reinstall or device change is not guaranteed. There is no accepted migration/recovery workflow. A transcript export is plaintext, and recipients or external apps can retain copies. PrivateRoom's explicit clipboard-copy actions use local-only, expiring items; external selections and applications have their own behavior.

The relay receives ciphertext and delivery metadata, including routing/peer/packet identifiers, timestamps and acknowledgements. Network connections can expose IP addresses and operational metadata. No anonymous traffic-analysis or metadata-hiding guarantee is made. Local deletion does not remove a recipient's copy or immediately erase existing encrypted server backups.

The new canonical-host beta contract uses signed device enrollment and peer-bound authenticated requests. Ordinary approved devices must not receive an operator's shared secret. Custom-relay credentials, if configured, remain private. The [endpoint contract](Docs/CURRENT-ENDPOINTS.md) distinguishes candidate behavior from completed public deployment.

## Report a vulnerability privately

Supported contact: **miggu69@gmail.com**. The [support page](https://securechat.team/support.html) provides the public contact route. No separate security mailbox, PGP fingerprint or response-time guarantee is advertised here.

Do not open a public GitHub issue containing a vulnerability, live exploit, private key, access token, personal message or identifying production log. Send an initial description with the affected version/commit, expected and observed behavior, impact and minimal reproduction using synthetic data. Ask for an appropriate protected channel before transferring highly sensitive material; ordinary email is not a guaranteed confidential transport.

Do not probe other users' devices or messages, disrupt the production relay, destroy data or send large unsolicited proof-of-concept traffic. Use an isolated fixture or obtain explicit authorization for live testing. This reporting process does not grant permission to attack unrelated services.

After remediation and coordination, publish a sanitized advisory stating affected/fixed versions, practical impact and residual limits. Do not claim an issue is fixed in deployed software until the relevant release/deployment is confirmed.

## Public source and confidential operations

The public client repository may explain algorithms, request formats, data flow and known limitations. Relay-source secrecy is not a confidentiality boundary for messages.

Never commit private keys, access tokens, production environment files, credentials, deployment addresses, real peer/device allowlists or identifiers, private logs, backups or raw personal content. Treat historical Git exposure separately: deleting a current file does not revoke a credential or erase history. Maintain private operational evidence outside the client repository and publish only sanitized summaries.

The existing repository license remains unchanged. This policy is not a certification, completed audit or confirmation of a future distribution agreement.
