# PrivateChat / SecureChat – Security Notes

## Scope

This document describes the active `PrivateChat` baseline and the hardened Relay Server. Historical BIT/SecureChat reference code was removed from the package in Phase 14.4 to reduce duplicate-code risk.

## Active security baseline

- Local identity uses Curve25519 key material through CryptoKit.
- Peer IDs are derived from signing public keys.
- Local message persistence is encrypted with AES-GCM.
- Store keys, trust state and Relay ledger metadata are stored via Keychain-backed stores.
- Relay packets are signed and payloads are AEAD-protected before upload.
- Relay server is a blind relay and does not receive message plaintext.
- Public production Relay is `https://chatsecure.ddns.net` behind Caddy.
- `/v1/relay/*` requires `RELAY_AUTH_TOKEN`.
- `/v1/admin/*` requires `RELAY_ADMIN_TOKEN` and must never be configured in the app.

## KDF statement

Password-channel derivation is documented as a **custom memory-hard KDF**, not Argon2id.

This distinction matters. The current KDF is intended to raise local brute-force cost without external dependencies, but it must not be marketed as Argon2id or as a substitute for a formally reviewed password-hashing construction.

## Production caveat

The project is a production candidate, not externally audited secure-messaging infrastructure. Before public security claims:

- migrate tests to the active `PrivateChat` target;
- add transport and persistence tests;
- review KDF design;
- run external cryptographic/security audit;
- verify Release/TestFlight builds on physical hardware.

## Relay production configuration

```text
Relay URL: https://chatsecure.ddns.net
Client token: RELAY_AUTH_TOKEN
Admin token: RELAY_ADMIN_TOKEN, server only
```

Old local Relay URLs are blocked/migrated in Phase 14.4 and must not be used for production.
