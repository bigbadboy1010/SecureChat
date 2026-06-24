#!/usr/bin/env bash
# scripts/e2e-acceptance.sh
#
# Sprint 20 (2026-06-24): end-to-end acceptance test
# for the SecureChat relay + iOS controller. Bridges the
# gap between the relay smoke test and a real-device
# TestFlight build.
#
# Pipeline:
#  1. (optional) start a fresh relay container against the
#     staging env. We don't do this in CI; the test assumes
#     a relay is already reachable at $RELAY_BASE_URL.
#  2. POST /v1/relay/security/policy and assert
#     productionMode=false (we never run acceptance
#     against prod).
#  3. Run the smoke test (test/smoke.ts) to confirm the
#     relay is healthy end-to-end.
#  4. (optional) drive the iOS controller via xcrun simctl
#     if a booted simulator is available. The CI workflow
#     gates this on macos-14 with a pre-installed iOS 17
#     simulator image.
#
# Usage:
#   scripts/e2e-acceptance.sh
#   RELAY_BASE_URL=https://securechat.team scripts/e2e-acceptance.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELAY_BASE_URL="${RELAY_BASE_URL:-http://127.0.0.1:3000}"
TEST_RESULT_JSON="${TEST_RESULT_JSON:-$REPO_ROOT/build/e2e-result.json}"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "$(dirname "$TEST_RESULT_JSON")"

echo "== SecureChat E2E acceptance =="
echo "  relay:   $RELAY_BASE_URL"
echo "  result:  $TEST_RESULT_JSON"
echo

# Step 1: policy check
echo "-- Step 1: security policy"
POLICY_BODY=$(curl -sS -w "\nHTTP %{http_code}\n" "$RELAY_BASE_URL/v1/relay/security/policy" || echo "FETCH_FAILED")
POLICY_STATUS=$(echo "$POLICY_BODY" | tail -1 | awk '{print $2}')
echo "  status: $POLICY_STATUS"
if [[ "$POLICY_STATUS" != "200" ]]; then
  echo "  ❌ policy endpoint failed"
  cat > "$TEST_RESULT_JSON" <<EOF
{"status":"fail","step":"policy","http_status":$POLICY_STATUS,"timestamp":"$TIMESTAMP"}
EOF
  exit 1
fi

# Refuse to run acceptance against a production-mode relay.
if echo "$POLICY_BODY" | grep -q '"productionMode":true'; then
  echo "  ❌ relay is in productionMode=true; refusing acceptance against prod"
  cat > "$TEST_RESULT_JSON" <<EOF
{"status":"fail","step":"policy","reason":"productionMode=true","timestamp":"$TIMESTAMP"}
EOF
  exit 1
fi
echo "  ✅ relay is non-production"

# Step 2: healthz
echo "-- Step 2: healthz"
HEALTH=$(curl -sS -w "\nHTTP %{http_code}\n" "$RELAY_BASE_URL/healthz" || echo "FETCH_FAILED")
HEALTH_STATUS=$(echo "$HEALTH" | tail -1 | awk '{print $2}')
if [[ "$HEALTH_STATUS" != "200" ]]; then
  echo "  ❌ /healthz failed"
  exit 1
fi
echo "  ✅ /healthz 200"

# Step 3: smoke test
echo "-- Step 3: relay smoke"
pushd "$REPO_ROOT/RelayServer" >/dev/null
if ! npx tsx test/smoke.ts; then
  echo "  ❌ smoke test failed"
  popd >/dev/null
  cat > "$TEST_RESULT_JSON" <<EOF
{"status":"fail","step":"smoke","timestamp":"$TIMESTAMP"}
EOF
  exit 1
fi
popd >/dev/null
echo "  ✅ smoke test passed"

# Step 4: optional iOS controller drive
echo "-- Step 4: iOS controller drive (optional)"
if command -v xcrun >/dev/null 2>&1 && xcrun simctl list devices booted 2>/dev/null | grep -q Booted; then
  echo "  detected booted simulator; driving controller"
  # The actual drive logic lives in Sprint 20.1 — we just print
  # a stub here so the script structure is stable.
  echo "  (skipped: simulator drive is Sprint 20.1)"
else
  echo "  no booted simulator; skipping controller drive"
fi

# All done
cat > "$TEST_RESULT_JSON" <<EOF
{"status":"pass","steps":["policy","healthz","smoke"],"timestamp":"$TIMESTAMP"}
EOF
echo
echo "✅ E2E ACCEPTANCE PASSED"