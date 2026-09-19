# SecureChat – TestFlight / Release Checklist

## Current status

Status: **TestFlight candidate, not externally audited**.

The active production message path uses protocolVersion 2:
X25519 pairwise key agreement + AES-GCM payload protection + Ed25519
signed envelopes. The experimental Double Ratchet implementation is
kept in the source tree but is disabled in TestFlight/Release until a
dedicated cryptographic review is complete.

## Build identity

- [x] Xcode project: `PrivateChat.xcodeproj`
- [x] Target / scheme: `PrivateChat`
- [x] Bundle ID: `org.francois.PrivateChat`
- [x] Marketing version: `1.4.2`
- [x] TestFlight build: `13`
- [x] Deployment target: iOS 16+
- [ ] Archive succeeds on the MacBook with Release configuration
- [ ] Build 13 tested on at least two physical iPhones

## Relay configuration

- [x] Canonical relay URL is `https://relay.securechat.team`
- [x] Legacy `chatsecure.ddns.net` migrates to the canonical relay
- [x] Plain HTTP / LAN relay URLs are blocked for Release
- [x] App contains only the client `RELAY_AUTH_TOKEN`
- [x] App does not contain `RELAY_ADMIN_TOKEN`
- [x] Production `TransportCoordinator` is wired to the Keychain identity
- [x] Inbox GET requests use the same peer-bound signature path as writes/ACKs
- [ ] `https://relay.securechat.team/healthz` returns HTTP 200
- [ ] Peer enrollment succeeds from a fresh physical-device install
- [ ] SEND → GET inbox → ACK works between two physical devices

## Identity and trust

- [x] SC2 Safety Number is derived symmetrically from both Ed25519 public keys
- [x] Legacy verified peers are forced back to unverified after SC2 migration
- [x] Direct “Verifizieren” bypass was removed from Pairing UI
- [x] Block / unverify / delete revokes stored experimental ratchet state
- [ ] Compare the same SC2 Safety Number on both physical devices
- [ ] Key-change / re-pair flow tested

## Local security

- [x] Identity and trust records stored in iOS Keychain
- [x] Message and draft stores encrypted with AES-GCM
- [x] Sensitive local stores excluded from backup
- [x] Critical Keychain/store bootstrap failure is fail-closed
- [x] Privacy manifest present
- [ ] Biometric unlock tested on physical hardware
- [ ] Background/app-switch preview behavior reviewed

## Automated gates

- [x] Real `PrivateChatTests` target exists
- [x] Security / crypto tests exist
- [x] Encrypted-store tests exist
- [x] Request-signing tests exist
- [x] Production-profile migration tests exist
- [x] Pull requests run Xcode unit tests and a Release compile gate
- [x] Public-repo SBOM job no longer depends on the private relay repository
- [ ] GitHub CI green for the TestFlight hardening PR
- [ ] Protect `main` and require the iOS CI check before merge

## App Store Connect

- [x] Camera usage description for QR pairing
- [x] Face ID usage description
- [x] Privacy manifest added
- [ ] App Privacy answers reviewed against the current relay metadata model
- [ ] Export-compliance answers reviewed
- [ ] Privacy Policy and Support URLs verified publicly
- [ ] TestFlight “What to Test” text updated for Build 13

## Final gate

Do not market SecureChat as independently audited, Signal-protocol
compatible, or as providing a reviewed Double Ratchet until those
claims are supported by an external cryptographic/security audit.
