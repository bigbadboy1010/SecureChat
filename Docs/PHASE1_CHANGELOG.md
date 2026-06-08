# Phase 1 Changelog

## Rebranding

- App display name changed to `PrivateChat`.
- Bundle identifier changed to `org.francois.PrivateChat`.
- Product name changed to `PrivateChat`.
- Deployment target raised to iOS 16.0.

## Target cleanup

- The app target now synchronises only the new `PrivateChat/` source folder.
- Legacy BIT/SecureChat sources were moved to `LegacyReference/OriginalSecureChatLegacy`.
- Duplicate `@main` entry points are no longer in the app target.
- Duplicate legacy models are no longer in the app target.

## Security baseline

- Local identity uses Curve25519 signing and key-agreement keys.
- Peer IDs are SHA-256 hashes of signing public keys.
- Local messages are stored encrypted via AES-GCM.
- Database key is generated with `SecRandomCopyBytes` and stored in Keychain.
- Trust store is persisted in Keychain.
- Relay mode exists only as an optional encrypted-packet transport scaffold.

## Known limitations

- No BLE transport yet in the clean target.
- No QR scanner yet.
- No receive path from relay yet.
- Double Ratchet is not integrated yet.
- Group encryption is not integrated yet.

## Optional relay server scaffold

- Added `RelayServer/` Fastify + Zod TypeScript baseline.
- Server accepts opaque encrypted packets only.
- In-memory store is for development only and must be replaced with PostgreSQL/Redis before production.
