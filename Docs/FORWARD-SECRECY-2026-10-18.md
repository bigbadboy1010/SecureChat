# PrivateRoom next beta: forward-secrecy integration

**Unreleased development candidate 1.5.2 (19). No TestFlight upload is authorized until the security release gate is satisfied.** Last distributed 1.5.1 (18) does not gain forward secrecy from these source changes. Both devices must update; existing recorded protocol-2 traffic cannot be protected retroactively.

## Protocol

New messages, delivery receipts and attachment chunks exclusively use **vodozemac 0.11.1 Olm**, pinned in `Crypto/PrivateRoomOlm/Cargo.lock`. Olm uses a one-time-key 3DH bootstrap and a Double Ratchet. There is no Megolm channel, fallback key, root-key export, static pairwise fallback or in-house ratchet routing. Historical experimental modules remain test/reference code only; ConversationService no longer instantiates or routes through their router.

The supported `SessionConfig::version_1()` is used. It has an 8-byte internal MAC in the published Olm format. Every PrivateRoom packet additionally requires a valid **Ed25519 signature over the complete envelope** before the receiver invokes Olm, using the previously verified SC3 contact. This outer authentication is enforced at the cryptographic receive boundary, including cached-journal retries, bootstrap, receipts and attachments. No claim of Signal interoperability, post-quantum security or metadata anonymity is made.

An account's Olm Curve25519 identity is signed by its existing device Ed25519 key. Each public one-time key separately binds domain, device ID, Olm identity, key ID, key and expiry in length-delimited signed fields. The relay verifies those signatures, and the sender independently verifies them against its trusted contact. Incoming encrypted envelopes bind the sender's Olm identity through the mandatory outer signature. Each client pins that identity. Unexpected identity replacement fails closed instead of silently resetting the session or contact trust.

## Relay contract

- Signed owner `GET /v1/relay/prekeys` returns only that owner's available-key count/sequence. Unlock checks this pool and can refill after recovery without resetting the identity.
- Signed owner `PUT /v1/relay/prekeys`: public key batches, strictly increasing sequence; exact idempotent retry does not restore already claimed keys.
- Signed `POST /v1/relay/prekeys/claim`: requester-bound UUID; both operator admission and mutual unexpired recipient consent required. A key goes to a single claim transaction. The exact reply survives a lost response and process restart.
- No private account, session or one-time key is sent to the relay.
- Maximum 50 keys per batch, 350 available public keys per account, eight claims per sender/recipient during the key lifetime, 4096 cached claims and an 8 MB file bound. These are closed-beta capacity limits, not an unlimited service guarantee.
- Client publication is normally daily with a six-day expiry, and may refill a low/missing pool after an authenticated availability check. Unused private keys are removed after expiry plus one packet TTL and clock margin. Consumed private one-time keys are removed by vodozemac after successful bootstrap authentication.
- Revocation and claim execution share the existing admission transaction; consent changes and claims serialize at the enrollment boundary. No nested admission-lock re-entry.
- Old clients may still use their old relay contract during coordinated rollout, but the new client rejects protocol 2/3 network packets. Both participants must upgrade before resending pending old content. Already saved local history remains readable.

## Persistence and crash invariants

1. The encrypted forward-secrecy store includes account/session pickles, pinned identities, pending key publication/claim, exact outbound packets and an inbound recovery journal in a single atomic transaction.
2. The encryption result is not returned to the transport before its advanced state and exact ciphertext/signature are durably written. Retries reuse that committed packet, including after restart.
3. On receive, advanced state and decrypted recovery journal are committed before modifying chat history/attachment storage. Failed history writes can replay the journal without restoring a consumed message key.
4. Message and attachment stores flush their protected atomic files before the relay ACK permits dropping the crypto journal. Received delivery receipts can release the matching outbound cache; old UI send completions cannot demote an already delivered message.
5. File contents and parent directories are flushed; files are mode 0600, complete Data Protection on iOS, and excluded from backup. The encryption key is device-bound in Keychain. A failed crypto-store commit blocks further use; it never triggers a weaker format or a fresh identity.
6. A Keychain initialization marker prevents a missing account file from silently regenerating an identity. Corrupt or mismatched state prevents startup. There is no session backup/recovery export or automatic identity reset.
7. Journal/outbox expiry and explicit bounds limit retained copies. The journal is encrypted **local content**, not a claim that the user's existing plaintext history disappears after delivery. Forward secrecy does not prevent an unlocked/compromised device or recipient from reading retained history.
8. Skipped message keys allow bounded reordering until consumed. Olm's library limits apply; indefinitely delayed/skipped messages are not guaranteed recoverable. A current compromise can expose pending skipped messages, pending one-time keys, current chains and local history. Only discarded past message keys are covered by the tested forward-secrecy property.

## Security evidence and limits

Upstream [vodozemac](https://github.com/matrix-org/vodozemac) is Apache-2.0 and previously received a [Least Authority audit](https://matrix.org/media/Least%20Authority%20-%20Matrix%20vodozemac%20Final%20Audit%20Report.pdf) in 2022 (reviewed revisions are in that report). **That audit is not an audit of version 0.11.1, our bridge, persistence, app or relay integration.** The current version includes later upstream changes and fixes for the two published low-severity 2024 advisories. Dependency inventory, license notices, exact artifact hashes and a build script accompany the bridge. Rust is pinned to 1.90.0; iPhone arm64 and simulator arm64/x86_64 libraries are built locally from checked sources and Cargo's checksum-verified dependency lock.

Own synthetic tests cover discarded-key secrecy, removal of a consumed bootstrap key, passive session compromise followed by fresh two-sided DH recovery, invalid authentication without state advancement, reordering/replay, restart recovery, simultaneous initiation, identity substitution, encrypted-store loss/corruption, failed storage, exact retry bytes/signature and maximum attachment-chunk wire size. These are regression proofs, not an independent cryptographic audit or a 100% security guarantee. Physical two-device interoperability and independent integration review remain release gates.

Post-compromise recovery requires honest fresh DH contributions after the attacker loses access. It does not heal an actively controlled endpoint or stolen signing identity by itself. Earlier traffic encrypted using the previous static-key implementation remains vulnerable if the old long-term decryption key is later exposed.

## Apple release gate

`Config/SecurityReleaseGate.json` and the automated upload scripts block build 19+. vodozemac contains external cryptographic implementations, so `ITSAppUsesNonExemptEncryption` is now true pending accurate Apple classification; do not reuse the previous OS-only declaration. [Apple's table](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption) distinguishes externally implemented standard algorithms and notes the French declaration requirement when distributing in France. Distribution intent, supporting declaration and Apple's outcome must be resolved before tester distribution/release. On the owner's later explicit request, `--staging-upload-only` checks a build-19-specific authorization to upload the binary to Apple while preserving the pending non-exempt declaration. The default distribution gate stays closed; no declaration approval, country restriction or production protocol cutover is claimed. Actual upload/processing results are recorded separately.
