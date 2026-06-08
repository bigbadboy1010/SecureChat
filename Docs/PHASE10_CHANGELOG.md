# Phase 10 Changelog

## Goal

Move PrivateChat from a local test relay toward a production baseline without changing the encrypted message payload format.

## Relay Server

- Added file-backed persistent relay store.
- Added optional bearer-token authentication for `/v1/relay/*` endpoints.
- `/health` now reports store mode and whether relay auth is required.
- Added Dockerfile.
- Added docker-compose.yml.
- Added Caddyfile baseline for HTTPS reverse proxy.
- Added `.env.example`.
- Added production relay README.

## iOS App

- Added Production Readiness screen under Security.
- Added server/deployment checklist.
- Added backup/restore policy guidance.
- Added App Store readiness section.
- Added diagnosis/remediation guidance for local vs public relay.

## Compatibility

- Relay API payload format remains compatible.
- Message payload format remains version 3.
- Existing local stores remain readable.
- Existing pairing/trust model remains unchanged.
