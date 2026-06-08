# PrivateChat Phase 4.1 Changelog

## Relay Sync Stabilization

Phase 4.1 reduces repeated relay churn observed after successful ACKs.

### Changes

- Delivery receipts are now sent once per inbound message ID.
- Duplicate inbound packets no longer trigger repeated delivery receipts after the first successful receipt.
- Repeated ACK attempts for already acknowledged packet IDs are throttled locally.
- The relay packet ledger now stores delivery-receipt send state in Keychain-backed encrypted app state.
- Existing Phase 4 ledgers remain readable; the new delivery receipt ledger defaults to empty during migration.

### Operational Impact

- Relay `GET`, `POST`, and `ACK` stay unchanged at API level.
- Existing RelayServer remains compatible, but deploying this version on both app sides is recommended.
- Log volume should drop substantially during auto-polling.
