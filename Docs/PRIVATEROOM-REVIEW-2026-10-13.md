# PrivateRoom review and integration candidate — 13 October 2026

## Status and scope

This is the public, sanitized record of the 13 October review. Candidate identity: **PrivateRoom 1.5.0 (16)**, existing technical scheme `PrivateChat` and bundle `org.francois.PrivateChat`. Distribution remains a **closed owner beta**. The hardened approved-owner-beta relay and redesigned project site went live on **13 October 2026 at 12:00:14 UTC**, with deployed backend source fingerprint **`aa3a9ddf9a55`**. The frozen candidate-16 native runner passed **141 tests with zero failures**. The signed candidate was installed and launched on the owner’s iPhone, and its local distribution archive/IPA passed signature/profile checks. The owner confirmed build 15 works; this feedback is not an exhaustive build-16 feature acceptance. The live backend is **0.2.0** with **26 accepted regressions**. Backend **0.2.1** has **39 passing staged regressions** and awaits final host-scoped deployment proof. The exact frozen archive was uploaded once through official Xcode distribution at **15:29:59 CEST on 13 October 2026**, and App Store Connect visibly lists version 1.5.0 / build 16 as **Verarbeitung läuft**. Tester availability and the actual encryption-compliance dialog remain pending. No tester invitations, Apple Review submission, App Store approval or independent audit are claimed.

The review covers the iPhone/iPad client, its pairing, authenticated relay requests, local storage, access lifecycle, consumer interface, public project pages and documentation. Private operator files and raw test artifacts remain separate. A source-level fix must not be described as device-tested or deployed until that specific evidence exists.

## Findings addressed in the candidate

| Finding | Implemented response | Verification boundary |
|---|---|---|
| Contact fingerprints covered signing keys without fully binding encryption identities. | SC3 fingerprints bind both parties' paired Ed25519 and X25519 public keys. Old verification does not carry across the upgrade. | Both peers still need a trusted-channel comparison; pairing signatures alone do not establish human identity. |
| Contact exchange did not authenticate its advertised material adequately. | Version-3 signed contact codes; legacy inputs remain unverified until the full SC3 comparison. | Malicious-input and key-substitution regressions passed; physical pairing and human identity verification remain separate. |
| Inactive/background transitions could leave unlocked state or stale authentication work. | Central user-session lock, inactive privacy cover, background invalidation and stale-authentication guards. Sensitive actions are session-bound. | Session regressions passed; owner-device installation and selected native actions are observed. Comprehensive open-sheet, interrupted-authentication and all-condition coverage is not claimed. |
| Local write failures could discard a draft or remove attachment data ahead of durable state. | Local acceptance results preserve the draft on failure; deletion paths preserve persistence ordering and error handling. | Storage-failure regressions passed; the selected physical protection fixture also passed. Actual locked-file reads and a comprehensive physical-media acceptance are not claimed. |
| Relay setup exposed operator-token instructions in the consumer interface. | Deliberate canonical-host connection with signed device enrollment; no consumer or operator bearer token is sent to the canonical host. Custom configuration stays advanced. | Backend 0.2.0 is live. Signed candidate 16 is installed/launched; actual native relay message exchange remains pending. |
| Network and server response handling exposed unnecessary diagnostic surface. | Authenticated request construction, tighter validation and sanitized relay error/logging behavior are deployed. | Client/server negative regressions passed; shared reverse-proxy global error metadata remains an explicit privacy limit. |
| UI remained inconsistent with the PrivateRoom product and hid important workflow consequences. | Consistent room/speech mark, ink/mint/ivory design, accessible animated introduction, actual status, contact-first flow and scoped retry. | Actual native iPhone/iPad pairing, intro replay, iPad text-size setting 8, Reduce Motion and basic intro VoiceOver activation were checked. This is not a full accessibility audit. |
| Destructive and plaintext-sharing actions lacked meaningful confirmation. | Local-message/chat/history and technical maintenance confirmations; transcript review; local expiring clipboard actions. | Recipient copies and historical encrypted backups are explicitly outside immediate local deletion. |
| Public copy implied a released, exceptionally secure or metadata-free product. | Closed-beta status, audit limits, static active protocol, backup/recovery limits and pending distribution are explicit. | Eleven public HTTPS routes passed and all 15 static source files matched their served bytes. Client device/native observations are recorded separately; staged backend 0.2.1 is not yet claimed deployed. |

The candidate uses a reproducible original geometric icon rather than a borrowed identity. Its native renderer exported all 28 existing AppIcon slots and the desktop resource with expected dimensions as opaque RGB PNGs. This asset check does not establish app-runtime acceptance.

## Cryptographic boundary

The active protocol is version 2: static X25519 agreement, HKDF-SHA256, AES-GCM authenticated encryption and Ed25519 envelope signatures. Public request signatures also bind the request to its device identity. SC3 covers signing and agreement identities on both devices; its verification is an explicit human trust ceremony.

**There is no forward secrecy or post-compromise security in the active channel.** Compromise of long-term key material can affect confidentiality of captured traffic. Experimental ratchet code is disabled and has not been independently audited. No claim of Signal compatibility, independently audited cryptography, post-quantum protection or guaranteed traffic anonymity is made.

The relay sees ciphertext and delivery metadata, including identifiers, routing and timing. Network connections can expose IP addresses and operational metadata. Sanitized relay logging does not eliminate network/routing metadata that can appear in the shared reverse proxy's global error logs. Endpoint compromise and a recipient's decision to save or share content remain material limits.

New routine server backups exclude live message queues, acknowledgement tombstones and nonce state. Historical encrypted backup and recovery copies remain; neither local deletion nor relay expiry immediately erases those historical copies. No metadata-free operation, instantaneous global deletion or fixed lifetime for historical backups is promised.

## Product boundary

Implemented candidate functions are one-to-one verified-contact messages, encrypted local notes/drafts, bounded encrypted attachments, local search/organization, actual relay/delivery states, local privacy controls and diagnostics reviewed before sharing. The interface separates normal use from advanced connection and maintenance controls.

Still absent as accepted product capabilities: independently audited protocol, reviewed device migration or recovery, production group messaging, calls, reliable background delivery/push, and cross-device history synchronization. Local stores are excluded from cloud backup; losing device-bound keys can lose data. Local deletion is not remote erasure.

## Observed acceptance and remaining checks

| Required evidence | Current public status |
|---|---|
| Integrated native build of the frozen candidate | Candidate **1.5.0 (16)** built successfully for simulator/device and distribution. |
| Full client regression run, including crypto, persistence, session and transport failures | Frozen candidate runner: **141 tests, zero failures**. |
| Native interface acceptance on two owned simulators | Version-3 codes imported on both; the same **17 SC3 groups** were actually compared and trusted on both interfaces. Current-16 intro replay passed. |
| Accessibility observations | iPad text-size setting **8**, Reduce Motion and basic intro VoiceOver activation checked; not a full VoiceOver/Dynamic Type/device-matrix audit. |
| Actual native relay message exchange | Pending; code import and SC3 comparison do not prove an actual native message roundtrip. |
| Isolated two-identity Swift text/attachment contract fixture | Full **8 MiB / 128 × 64 KiB** transfer, SHA-256 reassembly and acknowledgements passed under the exact serial/pacing limits below. This is not physical two-device or competing-traffic acceptance. |
| Live signed enrollment, unauthorized requests, peer isolation and replay policy | Isolated contract checks and **26 backend regressions** passed for the live **0.2.0** approved-owner-beta deployment. |
| Staged operator-only device revocation | Backend **0.2.1**, **39 staged regressions passed**; final deployment proof pending. Not claimed live. |
| Public site and relay cutover with rollback and unrelated-service checks | Live **2026-10-13 12:00:14 UTC**; **11 HTTPS routes** passed and **15 static files** matched source bytes. All **89 pre-existing containers** retained their identities, start times and restart counts; central server process IDs were unchanged. Verified rollback/recovery copies preserved on the owner’s Mac and separate backup server. |
| Physical owner-device installation and feedback | Signed build **16** installed and launched. Owner confirmed build **15** works; no exhaustive build-16 camera/pairing/media/lock matrix is asserted. |
| Physical iOS Data Protection metadata fixture | Selected build-15 fixture: **1 passed, 0 skipped**; complete protection class, backup exclusion and selective cleanup checked. Its implementation/test sources are unchanged in build 16. Actual locked-file read behavior was **not** exercised. |
| Local distribution archive and IPA | Candidate **16** exported locally with Apple Distribution signature, distribution profile and debugging entitlement disabled. The frozen **118 build inputs** and privacy manifest remain matched. |
| Apple upload, processing and encryption compliance | One authorized official Xcode upload succeeded at **2026-10-13 15:29:59 CEST**. ASC version 1.5.0 / build 16 visibly **processing**. Actual compliance dialog and tester availability pending; no tester invitation or Apple Review submission. |
| Independent protocol/application audit | Not completed |

The counts, source fingerprint, timestamp and deployment status above record observed results. Local tests do not imply GitHub Actions passed. Sanitized evidence may be published; private identities, logs, credentials and raw personal content must not accompany it.

## Future protocol work

A reviewed MLS integration through [OpenMLS](https://github.com/openmls/openmls) is a concrete direction to evaluate, not a completed implementation. MLS is specified in [RFC 9420](https://www.rfc-editor.org/rfc/rfc9420). OpenMLS uses pluggable crypto providers; its upstream README lists the iOS target as built but not tested on its CI. PrivateRoom must therefore establish its own iOS and device acceptance. [Upstream implementation and platform scope](https://github.com/openmls/openmls/blob/main/README.md).

The review boundary must cover the chosen library/version, provider and enabled algorithms, Rust/Swift binding, encrypted storage, randomness, key lifecycle, protocol state updates, membership, crash recovery and downgrade/migration behavior. A provider's audit does not audit the whole app. OpenMLS's security policy distinguishes its main library from application code and external provider/storage integrations. [Upstream security scope](https://github.com/openmls/openmls/blob/main/SECURITY.md).

Before enabling that path, require pinned dependencies and licenses, applicable audit reports and remediation status, interoperability vectors, hostile-input/fuzz coverage, durable state-transition tests, key-update/rejoin behavior, two-device integration and independent review of PrivateRoom's integration. State which exact components and versions were reviewed. Do not invent or imply a blanket audited-provider guarantee.

Until those gates pass, the experimental ratchet remains disabled and the active protocol's limitations remain visible in the product and public copy.

## Documentation and confidentiality

Public: source-level architecture, crypto/protocol formats, threat-model assumptions, capabilities, limits, sanitized acceptance evidence and vulnerability-reporting policy.

Private: real secret keys/tokens, production environment files, deployment credentials and addresses, private allowlists, real peer/device identifiers, logs, backups, raw personal messages and operational recovery material. Removing secrets from the latest tree does not erase earlier Git history; any actual exposure requires a separately assessed revocation/remediation process.

The review does not change the repository license. Older phase/sprint notes are historical, may contain outdated claims and do not supersede this dated status or [SECURITY.md](../SECURITY.md).

## Observed client and deployed-contract acceptance

On 13 October, the combined native iOS Simulator runner passed **141 tests with zero failures**. This includes the new full-key pairing, Keychain failure, attachment integrity/quota, user-session lifecycle, storage failure, draft migration, bounded media/import and signed transport checks, plus existing experimental ratchet tests. Passing experimental tests does not enable or validate that disabled protocol for production.

The frozen build-16 native run includes the final UI polish: send availability follows actual peer trust, note status is local rather than an external delivery claim, fingerprint groups scale without splitting digits, attachment controls have adequate targets and message bodies retain high contrast. The current-16 introduction replay was actually exercised successfully.

The signed build-16 app was installed and launched on the owner’s iPhone. The owner’s positive build-15 feedback remains explicitly version-scoped. The selected physical build-15 storage fixture passed **1 test with 0 skips**, checking the complete protection class, backup exclusion and selective cleanup. Its implementation/test source is unchanged in build 16. This is physical protection metadata evidence, **not** a test of reading protected files while the device is actually locked, nor an assertion about a compromised operating system.

On two owned native simulators running candidate 16, both signed version-3 codes were imported and all **17 identical SC3 groups** were actually compared and trusted through the interface. iPad text-size setting **8**, Reduce Motion and basic intro VoiceOver activation were checked. Those observations do not establish a full accessibility audit. Actual native relay message exchange remains pending.

The local build-16 distribution archive/IPA passed Apple Distribution signing and profile checks, with debugging disabled and the frozen **118 build inputs** and privacy manifest matched. The exact frozen archive subsequently completed one authorized official Xcode upload at **2026-10-13 15:29:59 CEST**. App Store Connect visibly lists version 1.5.0 / build 16 as **Verarbeitung läuft**. Successful upload and processing do not establish TestFlight tester availability or App Store approval; the actual encryption-compliance dialog remains pending.

The sender and hosted relay agree on a 256 KiB HTTP body and 128 KiB sealed payload limit. Relay JSON avoids unnecessary slash escaping, preventing a valid slash-heavy 64 KiB attachment chunk from exceeding its budget. Captions are capped at 16 KiB and unsupported C0 controls are rejected before queueing. Inbox requests are limited to 40 envelopes to fit the bounded 8 MiB response reader. A request-builder regression exercises a full slash-heavy chunk and maximum caption.

The actual Swift wire fixture completed signed two-identity enrollment, text exchange, a full 8 MiB attachment transfer in 128 × 64 KiB chunks, SHA-256 reassembly and acknowledgements on an isolated instance of the exact deployed contract. Sender and receiver ran **serially**, with **0.65-second** request pacing sharing the same **120-request-per-minute IP budget**. This test did not exercise simultaneously competing traffic and is not a substitute for physical two-device acceptance.

The live **0.2.0** backend’s **26 regressions** passed. The separately staged **0.2.1** backend has **39 passing regressions**; it awaits final host-scoped deployment proof and is not claimed live. Public acceptance verified 11 HTTPS routes and byte equality for all 15 static source files. The controlled cutover preserved all 89 pre-existing container identities, start times and restart counts, and kept central server process IDs unchanged, with verified rollback/recovery copies retained on the owner's Mac and separate backup server. No private runtime credentials, identity allowlists, infrastructure addresses or recovery material accompany this public evidence.

Incoming images are metadata-checked and decoded as bounded ImageIO thumbnails; large compressed images cannot force an unrestricted full-resolution display decode. Temporary plaintext previews use a backup-excluded protected directory and are reclaimed on lock/startup by exact generated filenames. This does not promise crash-proof deletion, eradication from device memory or safe previews on a compromised operating system.

### Privacy declarations for the candidate

The bundled manifest declares linked User ID, Other Usage Data and Other Diagnostic Data solely for app functionality, without tracking. This describes persistent public routing identifiers, message-delivery timing and operational diagnostics, rather than claiming that encrypted transport makes all metadata uncollected. No plaintext message, private identity key, advertisement or analytics SDK is sent by the intended client. Apple collection and final App Store labels must match the actual deployed processing when a release is prepared; no App Store label has been published by this review. [Apple privacy definitions](https://developer.apple.com/app-store/app-privacy-details/).

The request-signing regressions validate an independent known wire signature, generated signature verification and rejection of tampering. They do not require identical generated signature bytes: Apple documents randomized Ed25519 signatures to guard against side-channel attacks. [CryptoKit signing behavior](https://developer.apple.com/documentation/cryptokit/curve25519/signing/privatekey/signature(for:)).

Third-party keyboard extensions are disallowed through the app's UIApplicationDelegate, keeping typed chat text out of that extension path. System keyboard features and consciously used dictation remain under iOS's control; the app does not promise that all operating-system input processing is local. [Apple extension permission API](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/application(_:shouldallowextensionpointidentifier:)). Photos are re-rendered before sending; documents and video may retain their own metadata, and the composer warns the sender about this. Camera-video reads use the same actual-byte limit as other file imports.

The final candidate additionally drops obsolete shared operator tokens when migrating the canonical relay configuration, and never sends an Authorization bearer to that host. Explicit custom relay credentials are preserved. HTTP 429 and server failures trigger bounded backoff; newly accepted messages stay in the encrypted outbox rather than bypassing the pause. These behaviors are covered by the final 141-test run.

### Source-secret review

Gitleaks 8.30.1 scanned all local Git refs and the working tree. The 31 history detections were inspected: Curve25519 type declarations and an explicit historical unit-test literal. Eight working-tree detections consisted of six Swift type declarations and two ignored local fixture-token lines. Protected comparison established that none of that fixture file's three token values matches an old or new production client/operator token. The file is ignored, untracked and absent from Git history. No actual production credential exposure was identified by these scans; this is a bounded tool/manual review, not proof that any scan can detect every secret. Raw reports and operational comparison data remain private.


## Staged backend 0.2.1: operator-only device revocation

This contract is **staged only**; final deployment evidence is pending. It must not be offered as a currently live client capability.

The proposed `POST /v1/admin/relay/peers/:peerID/revoke` is authorized exclusively for the operator; it is not a self-revocation action available to ordinary clients. The placeholder is a public protocol identifier format, not a real approved identity. The operation responds idempotently with `revoked: true` and removes relay admission while retaining the registry and existing message data.

On that staged contract, a registered revoked identity is denied SEND, FETCH, ACK, stats and enrollment with `device_access_revoked`; sending to a revoked recipient is rejected with `recipient_not_admitted`. Already accepted operations can finish before revocation completes. Previously delivered contents and endpoint keys are not recalled. Revocation is access control, not forward secrecy, remote content erasure or post-compromise recovery.

The stage’s **39 regressions** are recorded separately from the live 0.2.0 deployment’s **26**. No operator authentication value, runtime configuration, real peer ID or raw operational log is published here.


## Authorized upload and remaining release gates

The owner explicitly authorized the TestFlight upload. The exact frozen archive 1.5.0 (16) completed **one** official `xcodebuild` upload successfully on **13 October 2026 at 15:29:59 CEST**. App Store Connect subsequently displayed version 1.5.0 / build 16 as **Verarbeitung läuft** (processing). No duplicate retry, tester invitation or Apple Review submission is asserted.

The uploaded source commit is `43c20a4c3532dd9687087de60f6bd1e0c49ec69b`, matching all **118 frozen build inputs** and the unchanged shipping-source manifest. German beta information, URLs, reviewer instructions and public contact were saved through the actual App Store Connect interface. Saving that information does not request review or prove tester availability.

The candidate’s implementation inventory uses OS-provided CryptoKit and platform transport encryption. Apple’s reference table assigns the OS-only encryption category no additional App Store Connect documentation; that is the basis for the current implementation assessment, not a completed ASC compliance decision. The actual build compliance dialog remains pending, and no separate legal/export approval is inferred from successful upload. [Apple’s encryption documentation table](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/).

When testing becomes available, each of the two installations must provide its own **public signed contact code** for explicit owner-beta relay admission. Private keys, passwords and operator secrets are never requested. After admission, compare every SC3 group on both devices via a trusted second channel, using only synthetic non-sensitive test messages. Apple beta access does not automatically grant relay admission, and the completed code-comparison observations do not claim actual native relay message exchange.

Backend **0.2.0** remains the accepted live contract. The staged **0.2.1** revocation update still awaits guarded data handoff and final deployment proof; the upload milestone does not change that server state.
