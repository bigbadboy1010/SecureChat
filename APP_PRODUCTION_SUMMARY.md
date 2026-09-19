# SecureChat – TestFlight Candidate Summary

**App target:** `PrivateChat`  
**Bundle ID:** `org.francois.PrivateChat`  
**Marketing version:** `1.4.2`  
**Build:** `13`  
**Production relay:** `https://relay.securechat.team`  
**Status:** TestFlight candidate; external security audit still open

## Active security posture

The active Release/TestFlight message path uses the established
protocolVersion 2 envelope:

- X25519 pairwise key agreement
- HKDF-SHA256 key derivation
- AES-GCM authenticated encryption
- Ed25519 signed transport envelopes
- Keychain-backed long-term identity keys
- encrypted local message and draft stores
- peer-bound relay request signatures

The newer Double Ratchet implementation remains available in the
source tree for engineering and unit tests but is **disabled on the
active TestFlight/Release path**. It must not be presented as a
reviewed production guarantee until its bootstrap, DH-turn rotation
and crash-persistence behavior have completed a dedicated external
cryptographic review.

## TestFlight hardening completed

- Canonical relay moved to `https://relay.securechat.team`.
- The legacy `chatsecure.ddns.net` value is migrated away.
- Production `TransportCoordinator` now receives the real
  `IdentityManager` signing context and `CryptoService`.
- Inbox GET requests are peer-signed, not bearer-only.
- Missing signing identity fails closed rather than creating a
  temporary random signing key.
- Critical Keychain/encrypted-store startup failure blocks unlock.
- Safety Numbers are now SC2 pair-bound fingerprints derived from
  both peers' Ed25519 public keys.
- Existing verified contacts are automatically downgraded to
  unverified when migrated to SC2 and must be compared again.
- Pairing UI no longer exposes a one-tap verification bypass.
- Block/unverify/delete removes stored experimental ratchet state.
- GitHub CI now builds/tests the actual root Xcode project instead
  of the removed public RelayServer tree.
- Build number bumped to 13.
- The user-facing navigation is chat-first: `Chats`, `Kontakte` and
  `Einstellungen`. Diagnostics are available from Settings instead of
  occupying the launch tab.
- The conversation list and composer no longer expose operational
  counters, relay summaries or implementation-detail banners during
  normal messaging.
- The TestFlight preflight now reads the exact bundle identifier and
  permits obsolete relay strings only inside the explicit migration list.

## Remaining release checks

Before distributing Build 13 beyond a small internal TestFlight
group:

1. GitHub iOS CI must be green.
2. Archive the Release build on the MacBook in Xcode.
3. Fresh-install on two physical iPhones.
4. Pair both directions and verify identical SC2 Safety Numbers.
5. Validate peer enrollment, SEND, inbox GET, ACK and reconnect.
6. Kill/relaunch the app between messages and verify encrypted local
   state remains readable.
7. Block, unblock, delete and re-pair contacts.
8. Review App Store privacy and export-compliance answers.
9. Keep the external security/cryptographic audit as an explicit
   precondition for stronger security claims.
