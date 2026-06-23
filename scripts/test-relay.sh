#!/usr/bin/env bash
#
# Smoke-Tests gegen die laufende SecureChat-Relay.
#
# Usage:
#   ./scripts/test-relay.sh                          # gegen https://securechat.team
#   ./scripts/test-relay.sh --host chatsecure.ddns.net
#   OPS_TOKEN=*** ./scripts/test-relay.sh --full    # zusaetzlich /healthz/internal mit Token
#
# Exit-Code: 0 = alle Tests gruen, 1 = mindestens ein Test fehlgeschlagen.

set -euo pipefail

HOST="securechat.team"
OPS_TOKEN="${OPS_TOKEN:-}"
FULL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)  HOST="$2"; shift 2 ;;
    --full)  FULL=1; shift ;;
    -h|--help)
      sed -n '2,15p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown flag: $1" >&2
      exit 1
      ;;
  esac
done

BASE="https://$HOST"
PASS=0
FAIL=0

# ----- Helpers -----
expect_status() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  # 'expected' may be a single status code (e.g. "200") or a pipe-
  # separated set (e.g. "401|503" — for the /healthz/internal case
  # where 401 means "bad token" and 503 means "operator token not
  # configured"). We do an exact match against each alternative.
  if [[ "$expected" == *"|"* ]]; then
    local alt
    local matched=0
    IFS='|' read -ra alts <<< "$expected"
    for alt in "${alts[@]}"; do
      if [[ "$alt" == "$actual" ]]; then matched=1; break; fi
    done
    if [[ $matched -eq 1 ]]; then
      echo "  PASS  $label  (got $actual, one of $expected)"
      PASS=$((PASS + 1))
    else
      echo "  FAIL  $label  (expected one of [$expected], got $actual)"
      FAIL=$((FAIL + 1))
    fi
  else
    if [[ "$expected" == "$actual" ]]; then
      echo "  PASS  $label  (got $actual)"
      PASS=$((PASS + 1))
    else
      echo "  FAIL  $label  (expected $expected, got $actual)"
      FAIL=$((FAIL + 1))
    fi
  fi
}

expect_match() {
  local label="$1"
  local pattern="$2"
  local body="$3"
  if echo "$body" | grep -qE "$pattern"; then
    echo "  PASS  $label  (matches $pattern)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  $label  (no match for $pattern)"
    echo "        body: $(echo "$body" | head -c 200)"
    FAIL=$((FAIL + 1))
  fi
}

# ----- Tests -----
echo ">> Smoke tests against $BASE"
echo

echo "1) public /healthz"
RESP=$(curl -sS --max-time 5 -w "\n%{http_code}" "$BASE/healthz" 2>&1 || echo "fail")
STATUS=$(echo "$RESP" | tail -n1)
BODY=$(echo "$RESP" | sed '$d')
expect_status "  HTTP code"  "200" "$STATUS"
expect_match "  body shape" '"status":"ok".*"uptimeSeconds":[0-9]+.*"version":"' "$BODY"

echo
echo "2) /healthz/internal without token (must be 401 or 503)"
RESP=$(curl -sS --max-time 5 -o /dev/null -w "%{http_code}" "$BASE/healthz/internal" 2>&1 || echo "000")
expect_status "  HTTP code"  "401|503" "$RESP"

if [[ $FULL -eq 1 && -n "$OPS_TOKEN" ]]; then
  echo
  echo "3) /healthz/internal with token (--full + OPS_TOKEN)"
  RESP=$(curl -sS --max-time 5 -w "\n%{http_code}" -H "X-Securechat-Ops-Token: $OPS_TOKEN" "$BASE/healthz/internal" 2>&1 || echo "fail")
  STATUS=$(echo "$RESP" | tail -n1)
  BODY=$(echo "$RESP" | sed '$d')
  expect_status "  HTTP code"  "200" "$STATUS"
  expect_match "  body shape" '"status":"ok".*"version":"' "$BODY"
  expect_match "  has peers"  '"peers":[0-9]+' "$BODY"
  expect_match "  has packetCount" '"packetCount":[0-9]+' "$BODY"
fi

echo
echo "4) /v1/relay/security/policy (public, no auth)"
RESP=$(curl -sS --max-time 5 -w "\n%{http_code}" "$BASE/v1/relay/security/policy" 2>&1 || echo "fail")
STATUS=$(echo "$RESP" | tail -n1)
BODY=$(echo "$RESP" | sed '$d')
expect_status "  HTTP code"  "200" "$STATUS"
expect_match "  encryptedPayloadOnly" '"encryptedPayloadOnly":true' "$BODY"
echo
echo "5) /v1/relay/stats (public, no auth, no peer IDs in body)"
RESP=$(curl -sS --max-time 5 -w "\n%{http_code}" "$BASE/v1/relay/stats" 2>&1 || echo "fail")
STATUS=$(echo "$RESP" | tail -n1)
BODY=$(echo "$RESP" | sed '$d')

expect_status "  HTTP code" "200" "$STATUS"
if echo "$BODY" | grep -qE '[a-f0-9]{64}'; then
  echo "  FAIL  body must not contain a 64-hex peer id"
  FAIL=$((FAIL + 1))
else
  echo "  PASS  body has no peer id"
  PASS=$((PASS + 1))
fi
# Sprint 9C: stats must include the v1 / v2 envelope
# counters (cumulative since relay start).
if echo "$BODY" | grep -qE '"v1EnvelopeRequests":[0-9]+'; then
  echo "  PASS  stats has v1EnvelopeRequests"
  PASS=$((PASS + 1))
else
  echo "  FAIL  stats missing v1EnvelopeRequests: $(echo "$BODY" | head -c 200)"
  FAIL=$((FAIL + 1))
fi
if echo "$BODY" | grep -qE '"v2EnvelopeRequests":[0-9]+'; then
  echo "  PASS  stats has v2EnvelopeRequests"
  PASS=$((PASS + 1))
else
  echo "  FAIL  stats missing v2EnvelopeRequests: $(echo "$BODY" | head -c 200)"
  FAIL=$((FAIL + 1))
fi

echo
echo "6) POST /v1/relay/messages without auth (must be 401)"
RESP=$(curl -sS --max-time 5 -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" \
  -d '{"protocolVersion":2,"id":"11111111-2222-4333-8444-555555555555","senderID":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","recipientID":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","sealedPayloadBase64":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==","signatureBase64":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==","createdAt":"2026-06-22T12:00:00+00:00","expiresAt":"2026-06-22T13:00:00+00:00"}' \
  "$BASE/v1/relay/messages" 2>&1 || echo "000")
expect_status "  HTTP code"  "401" "$RESP"

echo
echo "6b) POST /v1/relay/messages with v2 envelope without auth (must be 401)"
RESP=$(curl -sS --max-time 5 -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" \
  -d '{"protocolVersion":3,"id":"22222222-3333-4444-8555-666666666666","senderID":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","recipientID":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","sealedPayloadBase64":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==","signatureBase64":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==","createdAt":"2026-06-22T12:00:00+00:00","expiresAt":"2026-06-22T13:00:00+00:00"}' \
  "$BASE/v1/relay/messages" 2>&1 || echo "000")
expect_status "  HTTP code"  "401" "$RESP"

echo
echo "7) Public site loads"
for path in / /status.html /known-issues.html /privacy.html /imprint.html /docs/self-host.html /docs/architecture.html; do
  STATUS=$(curl -sS --max-time 5 -o /dev/null -w "%{http_code}" "$BASE$path" 2>&1 || echo "000")
  expect_status "  GET $path"  "200" "$STATUS"
done

echo
echo "=========================="
echo "PASS: $PASS    FAIL: $FAIL"
echo "=========================="
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
