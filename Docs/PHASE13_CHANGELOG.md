# Phase 13 – Relay Server Hardening

Phase 13 focuses on the relay as a production security boundary. The relay still stores only encrypted transport packets and ACK tombstones; it never sees chat plaintext or private keys.

## Why this phase exists

A strong E2E messenger can still be weakened by a poorly hardened relay. The main relay risks are not message decryption, but availability loss, queue exhaustion, purge abuse, metadata leakage in logs, weak tokens, and accidental HTTP production deployment.

## Relay hardening added

- Production fail-fast:
  - `STORE_TYPE=file` required in production
  - `RELAY_AUTH_TOKEN` required in production
  - minimum token length enforced
- Separate `RELAY_ADMIN_TOKEN`
- Constant-time Bearer-token comparison
- HTTPS enforcement for `/v1/relay/*` and `/v1/admin/*` in production
- Client purge disabled by default in production
- Admin-only purge endpoint:
  - `POST /v1/admin/relay/messages/purge`
- Client-visible policy endpoint:
  - `GET /v1/relay/security/policy`
- Admin policy endpoint:
  - `GET /v1/admin/relay/security/policy`
- Admin stats endpoint:
  - `GET /v1/admin/relay/stats`
- Per-recipient queue limit
- Global packet capacity limit
- Clock-skew validation
- TTL validation tightened
- Reject senderID == recipientID
- Sanitized audit logs without query strings
- Security headers:
  - `Cache-Control: no-store`
  - `X-Content-Type-Options: nosniff`
  - `Referrer-Policy: no-referrer`
  - `X-Frame-Options: DENY`
  - `Permissions-Policy`
- Docker hardening:
  - read-only root filesystem
  - `no-new-privileges`
  - `cap_drop: ALL`
  - Caddy HTTPS reverse proxy service

## New environment variables

```env
RELAY_ADMIN_TOKEN=<long random admin token>
REQUIRE_AUTH_IN_PRODUCTION=true
REQUIRE_HTTPS_IN_PRODUCTION=true
TRUST_PROXY_HEADERS=true
ENABLE_CLIENT_PURGE=false
SECURITY_AUDIT_LOG=true
MIN_AUTH_TOKEN_LENGTH=32
MAX_CLOCK_SKEW_SECONDS=300
MAX_TOTAL_PACKETS=10000
MAX_PACKETS_PER_RECIPIENT=500
```

## iOS updates

- Relay health decoding now understands the hardened `/health` response.
- Health check displays server policy summary when available.
- Production Readiness view now includes Phase 13 relay-hardening checks.

## Compatibility

No change to:

- encrypted payload format
- relay packet envelope format
- message payload format
- peer pairing format
- local store format

## Operational note

For public production use, put only `RELAY_AUTH_TOKEN` into the iOS app. Do not put `RELAY_ADMIN_TOKEN` into the app.
