# PrivateRoom review and integration candidate — 13 October 2026

## Status and scope

This is the public, sanitized record of the 13 October review. Candidate identity: **PrivateRoom 1.5.0 (15)**, existing technical scheme `PrivateChat` and bundle `org.francois.PrivateChat`. Distribution is a **closed owner beta**. Final integrated acceptance is pending; no new Apple upload, TestFlight availability, App Store submission, independent audit or public relay cutover is established by this document.

The review covers the iPhone/iPad client, its pairing, authenticated relay requests, local storage, access lifecycle, consumer interface, public project pages and documentation. Private operator files and raw test artifacts remain separate. A source-level fix must not be described as device-tested or deployed until that specific evidence exists.

## Findings addressed in the candidate

| Finding | Implemented response | Verification boundary |
|---|---|---|
| Contact fingerprints covered signing keys without fully binding encryption identities. | SC3 fingerprints bind both parties' paired Ed25519 and X25519 public keys. Old verification does not carry across the upgrade. | Both peers still need a trusted-channel comparison; pairing signatures alone do not establish human identity. |
| Contact exchange did not authenticate its advertised material adequately. | Version-3 signed contact codes; legacy inputs remain unverified until the full SC3 comparison. | Malicious-input and key-substitution regressions are required. |
| Inactive/background transitions could leave unlocked state or stale authentication work. | Central user-session lock, inactive privacy cover, background invalidation and stale-authentication guards. Sensitive actions are session-bound. | Actual authentication prompts, app switcher, open sheets and delayed callbacks require device acceptance. |
| Local write failures could discard a draft or remove attachment data ahead of durable state. | Local acceptance results preserve the draft on failure; deletion paths preserve persistence ordering and error handling. | Storage fault injection and relaunch tests are required, not only happy-path UI checks. |
| Relay setup exposed operator-token instructions in the consumer interface. | Deliberate canonical-host connection with signed device enrollment; operator credentials are not distributed to ordinary users. Custom configuration stays advanced. | The hardened relay is an isolated canary until the owner accepts a controlled cutover. |
| Network and server response handling exposed unnecessary diagnostic surface. | Authenticated request construction, tighter validation and sanitized error/logging behavior are part of the reviewed candidate. | Client and server negative tests must establish the actual deployed contract. |
| UI remained inconsistent with the PrivateRoom product and hid important workflow consequences. | Consistent room/speech mark, ink/mint/ivory design, accessible animated introduction, actual status, contact-first flow and scoped retry. | Small/large iPhone and iPad, Dynamic Type, Reduce Motion and VoiceOver checks remain necessary. |
| Destructive and plaintext-sharing actions lacked meaningful confirmation. | Local-message/chat/history and technical maintenance confirmations; transcript review; local expiring clipboard actions. | Recipient copies and historical encrypted backups are explicitly outside immediate local deletion. |
| Public copy implied a released, exceptionally secure or metadata-free product. | Closed-beta status, audit limits, static active protocol, backup/recovery limits and pending distribution are explicit. | Website and GitHub publication must reflect the final accepted state, not merely this draft. |

The candidate uses a reproducible original geometric icon rather than a borrowed identity. Its native renderer exported all 28 existing AppIcon slots and the desktop resource with expected dimensions as opaque RGB PNGs. This asset check does not establish app-runtime acceptance.

## Cryptographic boundary

The active protocol is version 2: static X25519 agreement, HKDF-SHA256, AES-GCM authenticated encryption and Ed25519 envelope signatures. Public request signatures also bind the request to its device identity. SC3 covers signing and agreement identities on both devices; its verification is an explicit human trust ceremony.

**There is no forward secrecy or post-compromise security in the active channel.** Compromise of long-term key material can affect confidentiality of captured traffic. Experimental ratchet code is disabled and has not been independently audited. No claim of Signal compatibility, independently audited cryptography, post-quantum protection or guaranteed traffic anonymity is made.

The relay sees ciphertext and delivery metadata, including identifiers, routing and timing. Network connections can expose IP addresses and operational metadata. Endpoint compromise and a recipient's decision to save or share content remain material limits.

## Product boundary

Implemented candidate functions are one-to-one verified-contact messages, encrypted local notes/drafts, bounded encrypted attachments, local search/organization, actual relay/delivery states, local privacy controls and diagnostics reviewed before sharing. The interface separates normal use from advanced connection and maintenance controls.

Still absent as accepted product capabilities: independently audited protocol, reviewed device migration or recovery, production group messaging, calls, reliable background delivery/push, and cross-device history synchronization. Local stores are excluded from cloud backup; losing device-bound keys can lose data. Local deletion is not remote erasure.

## Acceptance record to complete

| Required evidence | Current public status |
|---|---|
| Integrated native build of the frozen candidate | Pending final root-owned result |
| Full client regression run, including crypto, persistence, session and transport failures | Pending final root-owned result |
| Native GUI inspection on iPhone and iPad | Pending complete acceptance |
| Actual two-identity text/attachment roundtrip against the hardened contract | Pending final acceptance |
| Signed enrollment, unauthorized requests, peer isolation and replay rejection | Isolated-canary validation; final deployed acceptance pending |
| Public site and relay cutover with rollback and unrelated-service checks | Not yet claimed |
| Physical owner-device acceptance of camera/pairing, lock and media flows | Not yet claimed for this candidate |
| Apple upload or submission | Not performed as part of this review |
| Independent protocol/application audit | Not completed |

Exact test counts, hashes, timestamps and deployment status must be added only after the corresponding result is observed. Local tests do not imply GitHub Actions passed. Sanitized evidence may be published; private identities, logs, credentials and raw personal content must not accompany it.

## Future protocol work

A reviewed MLS integration through [OpenMLS](https://github.com/openmls/openmls) is a concrete direction to evaluate, not a completed implementation. MLS is specified in [RFC 9420](https://www.rfc-editor.org/rfc/rfc9420). OpenMLS uses pluggable crypto providers; its upstream README lists the iOS target as built but not tested on its CI. PrivateRoom must therefore establish its own iOS and device acceptance. [Upstream implementation and platform scope](https://github.com/openmls/openmls/blob/main/README.md).

The review boundary must cover the chosen library/version, provider and enabled algorithms, Rust/Swift binding, encrypted storage, randomness, key lifecycle, protocol state updates, membership, crash recovery and downgrade/migration behavior. A provider's audit does not audit the whole app. OpenMLS's security policy distinguishes its main library from application code and external provider/storage integrations. [Upstream security scope](https://github.com/openmls/openmls/blob/main/SECURITY.md).

Before enabling that path, require pinned dependencies and licenses, applicable audit reports and remediation status, interoperability vectors, hostile-input/fuzz coverage, durable state-transition tests, key-update/rejoin behavior, two-device integration and independent review of PrivateRoom's integration. State which exact components and versions were reviewed. Do not invent or imply a blanket audited-provider guarantee.

Until those gates pass, the experimental ratchet remains disabled and the active protocol's limitations remain visible in the product and public copy.

## Documentation and confidentiality

Public: source-level architecture, crypto/protocol formats, threat-model assumptions, capabilities, limits, sanitized acceptance evidence and vulnerability-reporting policy.

Private: real secret keys/tokens, production environment files, deployment credentials and addresses, private allowlists, real peer/device identifiers, logs, backups, raw personal messages and operational recovery material. Removing secrets from the latest tree does not erase earlier Git history; any actual exposure requires a separately assessed revocation/remediation process.

The review does not change the repository license. Older phase/sprint notes are historical, may contain outdated claims and do not supersede this dated status or [SECURITY.md](../SECURITY.md).

## Observed local acceptance

On 13 October, the combined native iOS Simulator runner passed **141 tests with zero failures**. This includes the new full-key pairing, Keychain failure, attachment integrity/quota, user-session lifecycle, storage failure, draft migration, bounded media/import and signed transport checks, plus existing experimental ratchet tests. Passing experimental tests does not enable or validate that disabled protocol for production.

A device-target Release build also passed with signing disabled. This establishes compilation, not physical installation, TestFlight availability or Apple approval. Simulator Data Protection metadata is unavailable; the physical-iPhone protection-class assertion has not run. Native authentication, app-switcher cover, live camera and real two-device acceptance remain to be observed. Later changes to launch color, intro-once namespace and export branding are cosmetic/product presentation; a final simulator build follows them.

The sender and hosted relay agree on a 256 KiB HTTP body and 128 KiB sealed payload limit. Relay JSON avoids unnecessary slash escaping, preventing a valid slash-heavy 64 KiB attachment chunk from exceeding its budget. Captions are capped at 16 KiB and unsupported C0 controls are rejected before queueing. Inbox requests are limited to 40 envelopes to fit the bounded 8 MiB response reader. A request-builder regression exercises a full slash-heavy chunk and maximum caption.

Incoming images are metadata-checked and decoded as bounded ImageIO thumbnails; large compressed images cannot force an unrestricted full-resolution display decode. Temporary plaintext previews use a backup-excluded protected directory and are reclaimed on lock/startup by exact generated filenames. This does not promise crash-proof deletion, eradication from device memory or safe previews on a compromised operating system.

### Privacy declarations for the candidate

The bundled manifest declares linked User ID, Other Usage Data and Other Diagnostic Data solely for app functionality, without tracking. This describes persistent public routing identifiers, message-delivery timing and operational diagnostics, rather than claiming that encrypted transport makes all metadata uncollected. No plaintext message, private identity key, advertisement or analytics SDK is sent by the intended client. Apple collection and final App Store labels must match the actual deployed processing when a release is prepared; no App Store label has been published by this review. [Apple privacy definitions](https://developer.apple.com/app-store/app-privacy-details/).

The request-signing regressions validate an independent known wire signature, generated signature verification and rejection of tampering. They do not require identical generated signature bytes: Apple documents randomized Ed25519 signatures to guard against side-channel attacks. [CryptoKit signing behavior](https://developer.apple.com/documentation/cryptokit/curve25519/signing/privatekey/signature(for:)).

Third-party keyboard extensions are disallowed through the app's UIApplicationDelegate, keeping typed chat text out of that extension path. System keyboard features and consciously used dictation remain under iOS's control; the app does not promise that all operating-system input processing is local. [Apple extension permission API](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/application(_:shouldallowextensionpointidentifier:)). Photos are re-rendered before sending; documents and video may retain their own metadata, and the composer warns the sender about this. Camera-video reads use the same actual-byte limit as other file imports.

The final candidate additionally drops obsolete shared operator tokens when migrating the canonical relay configuration, and never sends an Authorization bearer to that host. Explicit custom relay credentials are preserved. HTTP 429 and server failures trigger bounded backoff; newly accepted messages stay in the encrypted outbox rather than bypassing the pause. These behaviors are covered by the final 141-test run.

### Source-secret review

Gitleaks 8.30.1 scanned all local Git refs and the working tree. The 31 history detections were inspected: Curve25519 type declarations and an explicit historical unit-test literal. Eight working-tree detections consisted of six Swift type declarations and two ignored local fixture-token lines. Protected comparison established that none of that fixture file's three token values matches an old or new production client/operator token. The file is ignored, untracked and absent from Git history. No actual production credential exposure was identified by these scans; this is a bounded tool/manual review, not proof that any scan can detect every secret. Raw reports and operational comparison data remain private.
