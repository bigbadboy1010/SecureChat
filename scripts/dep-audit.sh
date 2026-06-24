#!/usr/bin/env bash
# scripts/dep-audit.sh
#
# Sprint 21 (2026-06-24): dependency vulnerability audit.
# Wraps `npm audit` for the relay with a configurable
# severity threshold; emits build/audit.json.
#
# Usage:
#   scripts/dep-audit.sh                       # full
#   scripts/dep-audit.sh --only=relay
#   scripts/dep-audit.sh --fail-on=high        # default

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_FILE="$REPO_ROOT/build/audit.json"
FAIL_ON="high"

ONLY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only=*)      ONLY="${1#*=}" ;;
    --fail-on=*)   FAIL_ON="${1#*=}" ;;
    --out=*)       OUT_FILE="${1#*=}" ;;
    --help|-h)     sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

mkdir -p "$(dirname "$OUT_FILE")"

severity_rank() {
  case "$1" in
    critical) echo 4 ;;
    high)     echo 3 ;;
    moderate) echo 2 ;;
    low)      echo 1 ;;
    info)     echo 0 ;;
    *)        echo 0 ;;
  esac
}

should_fail() {
  local advisory="$1"
  local running="$(severity_rank "$advisory")"
  local cutoff="$(severity_rank "$FAIL_ON")"
  [[ "$running" -ge "$cutoff" ]]
}

RELAY_FAIL=0
RELAY_MAX="none"

if [[ -z "$ONLY" || "$ONLY" == "relay" ]]; then
  echo "== relay (npm audit) =="
  pushd "$REPO_ROOT/RelayServer" >/dev/null
  RELAY_RAW=$(npm audit --json 2>/dev/null || echo '{"vulnerabilities":{}}')
  popd >/dev/null
  COUNTS=$(echo "$RELAY_RAW" | python3 -c '
import json, sys
d = json.load(sys.stdin)
v = d.get("vulnerabilities", {})
counts = {"critical":0,"high":0,"moderate":0,"low":0,"info":0}
for name, info in v.items():
  sev = info.get("severity","info")
  counts[sev] = counts.get(sev,0)+1
print(json.dumps(counts))
')
  echo "  relay counts: $COUNTS"
  RELAY_MAX=$(echo "$COUNTS" | python3 -c '
import json, sys
counts = json.load(sys.stdin)
for sev in ["critical","high","moderate","low","info"]:
  if counts.get(sev,0) > 0:
    print(sev); break
else:
  print("none")
')
  if should_fail "$RELAY_MAX"; then
    echo "  ❌ relay has $RELAY_MAX vulnerabilities (fail-on=$FAIL_ON)"
    RELAY_FAIL=1
  else
    echo "  ✅ relay clean at $FAIL_ON threshold (max: $RELAY_MAX)"
  fi
fi

cat > "$OUT_FILE" <<EOF
{
  "fail_on": "$FAIL_ON",
  "relay": {
    "vulnerability_counts": $COUNTS,
    "max_severity": "$RELAY_MAX",
    "fail": $RELAY_FAIL
  },
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
echo
cat "$OUT_FILE"
echo

if [[ "$RELAY_FAIL" -ne 0 ]]; then
  echo "❌ AUDIT FAILED"
  exit 1
fi
echo "✅ AUDIT PASSED"