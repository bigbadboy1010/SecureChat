# SecureChat Relay Production Hardening

Phase 13 hardens the relay as an encrypted packet dropbox. The relay never receives chat plaintext, private keys, or decrypted message bodies. It still matters because abuse of the relay can cause metadata exposure, queue exhaustion, purge abuse, or denial of service.

## Production invariants

Production startup now fails fast unless these are true:

- `NODE_ENV=production`
- `STORE_TYPE=file`
- `RELAY_AUTH_TOKEN` is set and at least `MIN_AUTH_TOKEN_LENGTH` characters
- HTTPS is required for `/v1/relay/*` and `/v1/admin/*` unless explicitly disabled

## Recommended `.env`

```env
NODE_ENV=production
STORE_TYPE=file
DATA_DIR=/data
RELAY_AUTH_TOKEN=<openssl rand -base64 48>
RELAY_ADMIN_TOKEN=<openssl rand -base64 48>
REQUIRE_AUTH_IN_PRODUCTION=true
REQUIRE_HTTPS_IN_PRODUCTION=true
ENABLE_CLIENT_PURGE=false
MAX_PACKET_BYTES=131072
MAX_TTL_SECONDS=86400
MAX_CLOCK_SKEW_SECONDS=300
MAX_TOTAL_PACKETS=10000
MAX_PACKETS_PER_RECIPIENT=500
RATE_LIMIT_MAX=120
RATE_LIMIT_WINDOW=1 minute
```

## Start

```bash
cp .env.example .env
# edit tokens and domain
docker compose up -d --build
```

## Health

Container health remains unauthenticated and contains policy metadata only. The production compose file does not publish host port 8080; check it through Docker or through Caddy:

```bash
docker exec securechat wget -qO- http://127.0.0.1:8080/health
curl https://chatsecure.ddns.net/health
```

Expected production shape:

```json
{
  "status": "ok",
  "store": "file",
  "authRequired": true,
  "adminAuthRequired": true,
  "productionMode": true,
  "httpsRequired": true,
  "clientPurgeEnabled": false
}
```

## Client API

All client relay routes use the app token:

```bash
curl -H "Authorization: Bearer $RELAY_AUTH_TOKEN" \
  https://chatsecure.ddns.net/v1/relay/security/policy
```

## Admin API

Admin routes use `RELAY_ADMIN_TOKEN`; do not put this token into the iOS app.

```bash
curl -H "Authorization: Bearer $RELAY_ADMIN_TOKEN" \
  https://chatsecure.ddns.net/v1/admin/relay/stats
```

Admin purge:

```bash
curl -X POST https://chatsecure.ddns.net/v1/admin/relay/messages/purge \
  -H "Authorization: Bearer $RELAY_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"recipientID":"<64-char-peer-id>"}'
```

## Hardened controls

- constant-time Bearer-token comparison
- separate client and admin token
- production fail-fast for missing auth/file-store
- HTTPS enforcement behind reverse proxy
- client purge disabled by default in production
- admin-only purge endpoint
- per-recipient packet cap
- total packet cap
- clock-skew enforcement
- max TTL enforcement
- sender must differ from recipient
- global rate limit
- sanitized audit logs without query strings
- no-store and browser security headers
- Docker `read_only`, `no-new-privileges`, `cap_drop: ALL`

## Limits

The relay cannot prove message authenticity itself because payloads are encrypted end-to-end and signatures are validated on the client. That is intentional. The relay policy protects availability, metadata minimization, and abuse resistance; message trust remains client-side cryptographic verification.
