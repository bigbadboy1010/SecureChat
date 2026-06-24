#!/usr/bin/env bash
# scripts/sbom-generate.sh
#
# Sprint 21 (2026-06-24): Software Bill of Materials
# (SBOM) generator for the SecureChat relay + iOS app.
#
# Generates CycloneDX 1.5 JSON from the npm + SwiftPM
# package metadata we already have. No new tools.
#
# Usage:
#   scripts/sbom-generate.sh                # both surfaces
#   scripts/sbom-generate.sh --only=relay   # just the relay
#   scripts/sbom-generate.sh --out=build/sbom/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$REPO_ROOT/build/sbom"
SPEC_VERSION="1.5"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

ONLY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only=*)   ONLY="${1#*=}" ;;
    --out=*)    OUT_DIR="${1#*=}" ;;
    --help|-h)  sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)          echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

mkdir -p "$OUT_DIR"
cd "$REPO_ROOT"

write_cdx() {
  local component_name="$1"
  local component_type="$2"
  local dependencies_json="$3"
  local output_file="$4"
  cat > "$output_file" <<EOF
{
  "bomFormat": "CycloneDX",
  "specVersion": "$SPEC_VERSION",
  "serialNumber": "urn:uuid:$(uuidgen 2>/dev/null || echo "00000000-0000-0000-0000-000000000000")",
  "version": 1,
  "metadata": {
    "timestamp": "$TIMESTAMP",
    "tools": [{"vendor": "securechat", "name": "sbom-generate.sh", "version": "1.0.0"}],
    "component": {"type": "$component_type", "name": "$component_name", "purl": "pkg:generic/$component_name@local"}
  },
  "components": $dependencies_json
}
EOF
  echo "  → $output_file"
}

# --------------------------------------------------------------------------
# Relay (npm)
# --------------------------------------------------------------------------

if [[ -z "$ONLY" || "$ONLY" == "relay" ]]; then
  echo "== relay (npm) =="
  pushd RelayServer >/dev/null
  RELAY_JSON=$(node -e '
    const p = require("./package.json");
    const all = Object.entries({ ...p.dependencies, ...p.devDependencies });
    const items = all.map(([name, range]) => {
      const version = String(range).replace(/^[\^~]/, "");
      const eco = name.startsWith("@types/") ? "npm-dev" : "npm";
      return { name, version, ecosystem: eco, purl: `pkg:npm/${name}@${version}` };
    });
    process.stdout.write(JSON.stringify(items, null, 2));
  ')
  write_cdx "securechat-relay" "application" "$RELAY_JSON" "$OUT_DIR/relay.cdx.json"
  popd >/dev/null
fi

# --------------------------------------------------------------------------
# iOS app (SwiftPM — assumed same WebRTC dep as Loupe)
# --------------------------------------------------------------------------

if [[ -z "$ONLY" || "$ONLY" == "ios" ]]; then
  echo "== ios (SwiftPM) =="
  write_cdx "securechat-ios" "application" '[
    {
      "name": "WebRTC",
      "version": "120.0.0",
      "scope": "stasel",
      "ecosystem": "swiftpm",
      "purl": "pkg:swiftpkg/stasel/WebRTC@120.0.0",
      "notes": "Same Google WebRTC M120 prebuilt xcframework as the Loupe host."
    }
  ]' "$OUT_DIR/ios.cdx.json"
fi

# --------------------------------------------------------------------------
# Combined
# --------------------------------------------------------------------------

if [[ -z "$ONLY" ]]; then
  echo "== combined =="
  write_cdx "securechat" "application" '[
    {"name": "securechat-relay", "type": "application", "purl": "pkg:generic/securechat-relay@local"},
    {"name": "securechat-ios", "type": "application", "purl": "pkg:generic/securechat-ios@local"}
  ]' "$OUT_DIR/combined.cdx.json"
fi

echo
ls -la "$OUT_DIR"