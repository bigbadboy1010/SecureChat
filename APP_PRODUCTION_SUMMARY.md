# PrivateChat / SecureChat – Production Candidate Summary

**App target:** `PrivateChat`  
**Bundle ID:** `org.francois.PrivateChat`  
**Production Relay:** `https://chatsecure.ddns.net`  
**Status:** Production Candidate ⚠️ – external security audit still required

## Current position

PrivateChat/SecureChat is a hardened secure-messaging candidate with local encrypted persistence, Keychain-backed identity material, manual QR pairing, trust-state handling and a hardened TypeScript Relay Server.

The project must not claim final production-grade cryptographic assurance until the active `PrivateChat` target has dedicated tests and an external security audit.

## Implemented hardening

- Single active iOS app target: `PrivateChat`.
- Local message store encrypted with AES-GCM.
- Store keys and trust state stored outside UserDefaults.
- Pairing payloads and Safety Number workflow.
- Relay packets are signed and AEAD-protected before upload.
- Relay server uses bearer-token authorization for `/v1/relay/*`.
- Public relay is HTTPS-only through Caddy at `https://chatsecure.ddns.net`.
- Separate `RELAY_AUTH_TOKEN` and `RELAY_ADMIN_TOKEN`.
- Runtime Security view and local Security Sentinel.
- Privacy Composer and preview-protection settings.
- `PrivacyInfo.xcprivacy` added.

## Phase 14.4 cleanup

- Removed packaged `LegacyReference/` to eliminate duplicate-code security risk.
- Removed stale `Tests/schatTests/` because they did not test the active `PrivateChat` target.
- Added `Tests/README.md` with the required PrivateChat test migration scope.
- Corrected KDF documentation: password-channel derivation is a custom memory-hard KDF, not Argon2id.
- Auto-polling now blocks old local Relay URLs and requires a plausible `RELAY_AUTH_TOKEN` before Relay API calls.

## Required before stronger production claims

1. Create a real `PrivateChatTests` target.
2. Add tests for `PrivateChat/Core/Security`, `PrivateChat/Core/Transport`, encrypted store migration and Relay configuration migration.
3. Replace or externally review the custom memory-hard KDF before marketing it as high-assurance password hashing.
4. Run an external security review of the active app and Relay server.
5. Test Release/TestFlight builds on physical iPhone hardware.

## App configuration

```text
Relay URL:
https://chatsecure.ddns.net

Relay Token:
RELAY_AUTH_TOKEN from /opt/securechat/.env
```

Do not put `RELAY_ADMIN_TOKEN` into the app.

## Phase 14.5 Update

Status remains Production Candidate. Phase 14.5 fixes the most direct App Store / security-readiness findings: encrypted drafts instead of UserDefaults plaintext, backup exclusion for encrypted local stores, Privacy Manifest FileTimestamp reason, managed Relay auto-sync lifecycle, and initial PrivateChat unit-test target. External audit and broader ConversationService refactor remain open.
