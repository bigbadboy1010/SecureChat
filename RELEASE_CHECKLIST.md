# PrivateChat / SecureChat – Release Checklist

## Current status

Status: **Production Candidate, not externally audited**.

## Build identity

- [ ] Open `PrivateChat.xcodeproj`
- [ ] Target: `PrivateChat`
- [ ] Bundle ID: `org.francois.PrivateChat`
- [ ] Deployment target: iOS 16+
- [ ] Release/TestFlight build on physical iPhone tested

## Relay configuration

- [ ] Relay URL is `https://chatsecure.ddns.net`
- [ ] App contains only `RELAY_AUTH_TOKEN`
- [ ] App does not contain `RELAY_ADMIN_TOKEN`
- [ ] `/health` returns 200
- [ ] `/v1/relay/security/policy` without token returns 401
- [ ] `/v1/relay/security/policy` with `RELAY_AUTH_TOKEN` returns 200
- [ ] Old local Relay URLs are not visible in Xcode logs

## App security

- [ ] Biometric unlock enabled
- [ ] Preview protection reviewed
- [ ] Keyboard suggestion reduction enabled for sensitive input
- [ ] Runtime Security checked in Release/TestFlight build
- [ ] Security Sentinel reviewed
- [ ] Diagnostics report contains no chat plaintext

## Code review cleanup

- [x] `LegacyReference/` removed from package
- [x] stale `schatTests` removed from package
- [x] `PrivacyInfo.xcprivacy` added
- [x] KDF documentation corrected: custom memory-hard KDF, not Argon2id
- [ ] Real `PrivateChatTests` target added
- [ ] Active `PrivateChat/Core/Security` tests added
- [ ] Active `PrivateChat/Core/Transport` tests added
- [ ] External security audit completed

## App Store / privacy

- [x] Camera usage description for QR pairing
- [x] Face ID usage description
- [x] Local Network usage description
- [x] Privacy manifest added
- [ ] App Privacy answers reviewed in App Store Connect
- [ ] Export compliance reviewed

## Final gate

Do not market the app as independently audited secure messaging until the external audit and active target tests are complete.

## Phase 14.5 Checklist Additions

- [ ] Verify `PrivacyInfo.xcprivacy` includes UserDefaults and FileTimestamp reasons.
- [ ] Verify encrypted drafts migrate from legacy UserDefaults and are removed from UserDefaults after launch.
- [ ] Verify `messages.store` and `drafts.store` are excluded from backup.
- [ ] Run `PrivateChatTests` in Xcode.
- [ ] Verify `https://chatsecure.ddns.net/health` and Relay policy checks remain green.
