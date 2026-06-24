# Peer-bound request signing — migration runbook

This document is the step-by-step procedure for an
operator who wants to turn on `RELAY_REQUIRE_PEER_AUTH`
in production. It is written for the SecureChat relay,
but the same procedure applies to the Loupe host (where
the flag is `LOUPE_REQUIRE_PEER_AUTH`).

## Why migrate

Every relay request today is **also** signed by a
peer-bound HMAC, but the verifier only **monitors**
unsigned requests — it does not reject them. That keeps
old iOS clients (pre-Sprint 15) working during the
migration window. After the iOS app is broadly on the
Sprint 15+ release, the operator can flip the flag and
the relay rejects unsigned requests with 401.

The flag is **off-by-default** (`false`) so the
deployment story is: ship the new client → measure the
unsigned-request counter → flip the flag.

## What ships today (24 June 2026)

- ✅ Relay parses every `x-sc-*` header set and runs the
  verifier; if the verifier accepts the signature, the
  relay attaches the signer's `peerID` to the request
  context.
- ✅ Unsigned requests are accepted and counted in the
  `/v1/relay/security/policy` response and the relay's
  structured logs.
- ✅ A new startup warning logs `SECURITY: peer-bound
  request signing is OFF in production` when
  `NODE_ENV=production` and `RELAY_REQUIRE_PEER_AUTH`
  is unset/`false`. The warning is greppable; it does
  not fail startup.
- ✅ Smoke test (`npm run test:smoke`) signs all
  requests and exercises the verifier path. A separate
  test exercises the **strict** server (an ephemeral
  `buildServer({ ... requirePeerAuth: true })`) to
  verify that bad signatures are rejected with 401.
- ⏳ The flip itself is **operator-initiated** and is
  documented here, not automated, because the operator
  needs to be the one to decide "all clients are now on
  Sprint 15+".

## Migration steps

### 1. Confirm the iOS client is widely deployed

```
$ curl -sS https://securechat.team/v1/relay/security/policy | jq .
{
  "productionMode": true,
  "authRequired": true,
  ...
  "unsignedRequestCount": 12,    ← non-zero is fine
  "lastUnsignedAt": "2026-06-24T07:00:00Z"
}
```

If `unsignedRequestCount` is trending down over the
last 7 days, you're ready. If it has plateaued, wait
another week before flipping.

### 2. Verify the iOS app version in production

```
$ xcrun altool --list-builds --app-platform ios \
    --bundle-id org.francois.PrivateChat \
    --api-key 4S5KCC5NH6 --api-issuer <issuer-uuid>
```

Look for the highest Build number. The relay logs
the signer's client version (if the iOS app sends it)
so you can cross-check.

### 3. Flip the flag

On `miggu69@212.186.18.125`:

```bash
ssh miggu69@212.186.18.125
cd /opt/securechat/app/RelayServer
# Edit .env: change RELAY_REQUIRE_PEER_AUTH to true
# (or add it if missing)
grep RELAY_REQUIRE_PEER_AUTH .env
# RELAY_REQUIRE_PEER_AUTH=true
```

### 4. Rebuild + bounce the relay container

```bash
ssh miggu69@212.186.18.125 "cd /opt/securechat/app && \
  docker compose build --no-cache securechat && \
  docker compose up -d securechat"
```

### 5. Verify the flip

```bash
# Should now show: productionMode=true AND requirePeerAuth=true
curl -sS https://securechat.team/v1/relay/security/policy | jq .
```

If `requirePeerAuth` is still `false`, the env file
was not picked up. Check that `.env` lives in the
working directory and that the file has Unix line
endings (not CRLF — Windows-edited files break the
parser).

### 6. Watch the rejection rate

```bash
ssh miggu69@212.186.18.125 "cd /opt/securechat/app && \
  docker compose logs --tail=200 securechat | grep -c 'unsigned_request_required'"
```

A non-zero number is **expected** for the first 24h
as pre-Sprint-15 clients age out. If the rate stays
above 10/hour after a week, you have a stale client
deployment — investigate before considering a
rollback.

### 7. Rollback

If the rejection rate is too high and clients are
broken:

```bash
ssh miggu69@212.186.18.125 "cd /opt/securechat/app/RelayServer && \
  sed -i 's/RELAY_REQUIRE_PEER_AUTH=true/RELAY_REQUIRE_PEER_AUTH=false/' .env && \
  cd .. && docker compose up -d securechat"
```

The flip is instant because the verifier reads
`config.requirePeerAuth` at request-time (no rebuild
required).

## What the iOS app needs to do

Nothing — if the iOS app is on Sprint 15 or later, it
already signs every request via `peerBoundHeaders()`
(see the `peer-bound-canonical` skill). Sprint 15+
is the minimum because earlier versions did not
include the Ed25519 peerID used for signing.

## What happens to clients that don't sign

```
$ curl -sS -X POST https://securechat.team/v1/relay/messages \
    -H "x-sc-peer-id: $(printf 'a%.0s' {1..64})" \
    -H "x-sc-ts: $(date +%s%3N)" \
    -H "x-sc-nonce: $(openssl rand -hex 16)" \
    -H "x-sc-body-sha256: $(printf '' | sha256sum | awk '{print $1}')" \
    -H "content-type: application/json" \
    -d '{"protocolVersion":3,"id":"00000000-0000-4000-8000-000000000000","senderID":"'$(printf 'a%.0s' {1..64})'","recipientID":"'$(printf 'b%.0s' {1..64})'","sealedPayloadBase64":"AA==","signatureBase64":"'$(printf 'A%.0s' {1..88})'","createdAt":"2026-06-24T07:00:00Z","expiresAt":"2026-06-24T08:00:00Z"}'
```

With `RELAY_REQUIRE_PEER_AUTH=true` this returns:

```json
{
  "error": "unsigned_request_required",
  "reason": "this relay requires peer-bound request signing; please upgrade your iOS app to the Sprint 15 build or later"
}
```

HTTP 401.

## What the operator dashboard shows

The existing `/v1/relay/security/policy` endpoint
returns `requirePeerAuth`. After the flip, the value
is `true`. The relay's `/admin/metrics` (operator-only,
requires `ADMIN_TOKEN`) returns the unsigned-request
counter as a gauge; the agent's `/admin/unsign…` route
is a separate endpoint added in Sprint 16A.

## See also

- `peer-bound-canonical` skill — the canonical-string
  format reference.
- `securechat-deploy-pitfalls/references/sprint15-ios-peer-bound-signing.md`
  — iOS-side pitfalls.
- `RelayServer/src/peerAuth.ts` — verifier.
- ADR-005 — the original peer-bound design.