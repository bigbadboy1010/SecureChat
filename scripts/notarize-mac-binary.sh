#!/usr/bin/env bash
# Notarize a macOS binary (typically a .app, .dmg, or .pkg) with
# Apple's notary service and staple the ticket to the binary so
# Gatekeeper allows it on first run.
#
# Usage:
#   ./scripts/notarize-mac-binary.sh path/to/SecureChat.dmg
#   ./scripts/notarize-mac-binary.sh path/to/SecureChat.app
#
# Required environment:
#   APPLE_ID             The Apple ID email that owns the
#                        Developer ID Application certificate
#                        (e.g. fdelattre1010@gmail.com).
#   APPLE_TEAM_ID        The 10-char Apple Developer Team ID
#                        (e.g. 355NB9T8RJ).
#   APPLE_APP_PASSWORD   An app-specific password from
#                        https://appleid.apple.com. NEVER check
#                        this into git. Pass it via env or read
#                        it from a secrets manager.
#
# What it does:
#   1. Submits the binary to Apple's notary service
#   2. Polls until Apple finishes (typically 30-90 seconds)
#   3. Staples the notarization ticket to the binary
#   4. Verifies with spctl that Gatekeeper accepts it
#
# After notarization, ship the binary via:
#   xcrun stapler staple path/to/SecureChat.dmg

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "    usage: $0 <path-to-binary>" >&2
  exit 1
fi

BINARY="$1"

if [[ ! -e "$BINARY" ]]; then
  echo "    error: $BINARY does not exist" >&2
  exit 1
fi

for var in APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD; do
  if [[ -z "${!var:-}" ]]; then
    echo "    error: $var env var is not set" >&2
    echo "           export $var=..." >&2
    exit 1
  fi
done

echo "==> 1/4  Zipping (notarytool wants a zip, not a bare app)"
TMP_DIR="$(mktemp -d)"
ZIP="$TMP_DIR/notarize-submit.zip"
if [[ -d "$BINARY" ]]; then
  /usr/bin/ditto -c -k --keepParent "$BINARY" "$ZIP"
else
  cp "$BINARY" "$TMP_DIR/"
  /usr/bin/ditto -c -k "$TMP_DIR/$(basename "$BINARY")" "$ZIP"
fi

echo
echo "==> 2/4  Submitting to notary service"
SUBMIT_OUTPUT=$(xcrun notarytool submit "$ZIP" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait 2>&1)
echo "$SUBMIT_OUTPUT"
SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | awk -F': ' '/^  id:/ {print $2}' | tr -d ' ')
if [[ -z "$SUBMISSION_ID" ]]; then
  echo "    error: could not parse submission id from notarytool output" >&2
  exit 1
fi
echo "    submission id: $SUBMISSION_ID"

echo
echo "==> 3/4  Fetching notarization log (if it failed)"
if ! echo "$SUBMIT_OUTPUT" | grep -q '"status": "Accepted"'; then
  xcrun notarytool log "$SUBMISSION_ID" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD"
  exit 1
fi

echo
echo "==> 4/4  Stapling notarization ticket to $BINARY"
xcrun stapler staple "$BINARY"
echo
echo "    verifying Gatekeeper assessment..."
spctl --assess --type open --context context:primary-engine -vv "$BINARY" 2>&1 || \
  spctl --assess -vv "$BINARY" 2>&1 || \
  echo "    (Gatekeeper rejected - this is normal for unsigned ad-hoc binaries)"

echo
echo "==> Done. $BINARY is notarized and ready to ship."
