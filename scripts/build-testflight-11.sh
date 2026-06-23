#!/usr/bin/env bash
# build-testflight-11.sh
# 2026-06-23: one-shot Build 11 release script for SecureChat.
#
# Runs the pre-flight checks, then the archive step, then (if
# APP_STORE_CONNECT_API_KEY_PATH is set) the altool upload.
#
# Usage:
#   ./scripts/build-testflight-11.sh
#
# Optional env vars (only needed for the upload step):
#   APP_STORE_CONNECT_API_KEY_PATH  - path to AuthKey_XXXX.p8
#   APP_STORE_CONNECT_KEY_ID        - the 10-char Key ID
#   APP_STORE_CONNECT_ISSUER_ID     - the Issuer ID UUID
#
# If the API key env is missing, the script stops after the
# archive step and tells you how to upload via Xcode Organizer.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$REPO_ROOT"

echo "=================================================================="
echo " SecureChat TestFlight Build 11 -- one-shot release"
echo "=================================================================="
echo
echo "Step 1/4 -- pre-flight checks"
echo "------------------------------------------------------------------"
bash scripts/preflight-testflight.sh
echo

echo "Step 2/4 -- generate ExportOptions.plist (idempotent)"
echo "------------------------------------------------------------------"
bash scripts/generate-export-options.sh
echo

echo "Step 3/4 -- archive the build (CURRENT: 10 -> 11)"
echo "------------------------------------------------------------------"
SKIP_BUMP=0 bash scripts/build-ios-archive.sh 2>&1 | tail -25
ARCHIVE_DIR="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)"
ARCHIVE=$(ls -1dt "$ARCHIVE_DIR"/*.xcarchive 2>/dev/null | head -1 || echo "")
if [[ -z "$ARCHIVE" || ! -d "$ARCHIVE" ]]; then
  echo
  echo "  [error] no .xcarchive found under $ARCHIVE_DIR"
  echo "  inspect scripts/build-ios-archive.sh output above for the cause"
  exit 1
fi
echo
echo "  archive: $ARCHIVE"
echo

if [[ -z "${APP_STORE_CONNECT_API_KEY_PATH:-}" ]]; then
  echo "Step 4/4 -- upload (skipped, no API key)"
  echo "------------------------------------------------------------------"
  echo "  Set the three env vars and re-run, or upload via Xcode:"
  echo "    open -a Xcode $REPO_ROOT/PrivateChat.xcodeproj"
  echo "    Xcode -> Window -> Organizer (⇧⌘9) -> Distribute App"
  echo
  echo "  See Docs/IOS-TESTFLIGHT-RUNBOOK.md for full instructions."
  exit 0
fi

echo "Step 4/4 -- upload to App Store Connect / TestFlight"
echo "------------------------------------------------------------------"
echo "  API key:   $APP_STORE_CONNECT_API_KEY_PATH"
echo "  Key ID:    ${APP_STORE_CONNECT_KEY_ID:-<not set>}"
echo "  Issuer ID: ${APP_STORE_CONNECT_ISSUER_ID:-<not set>}"
if [[ -z "${APP_STORE_CONNECT_KEY_ID:-}" || -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
  echo
  echo "  [error] APP_STORE_CONNECT_KEY_ID and APP_STORE_CONNECT_ISSUER_ID"
  echo "          must also be set when APP_STORE_CONNECT_API_KEY_PATH is set."
  exit 1
fi

xcrun altool --upload-app \
  -f "$ARCHIVE" \
  --type ios \
  --apiKey "$APP_STORE_CONNECT_API_KEY_PATH" \
  --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID" 2>&1 | tail -10

echo
echo "=================================================================="
echo " Done. The build is now in App Store Connect. Processing usually"
echo " takes 5-30 minutes. The build will appear under"
echo "   App Store Connect -> SecureChat -> TestFlight -> iOS Builds"
echo
echo " After processing:"
echo "   1. Open TestFlight, find the new build"
echo "   2. Add the build to a tester group (or your own internal group)"
echo "   3. Update the 'What's New' field with the text in"
echo "      Docs/TESTFLIGHT-LISTING-COPY.md"
echo "=================================================================="
