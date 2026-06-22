#!/usr/bin/env bash
# Generate a working ExportOptions.plist for SecureChat
# TestFlight uploads, based on the project settings that already
# live in apps/SecureChat/ExportOptions.template.plist.
#
# Usage:
#   ./scripts/generate-export-options.sh
#
# What it does:
#   - Reads the template from apps/SecureChat/ExportOptions.template.plist
#   - Writes apps/SecureChat/ExportOptions.plist (gitignored)
#   - Verifies the file with plutil -lint
#
# Why a template + generated file instead of committing the plist:
#   The plist contains team identifiers, bundle identifiers, and
#   (optionally) App Store Connect API key paths. Some teams want
#   those checked in for reproducibility; others (like us) prefer
#   the file stays out of git so a developer's personal Apple ID
#   doesn't leak. Adjust EXPORT_OPTIONS_TEMPLATE below to your
#   team's policy.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$REPO_ROOT/apps/SecureChat"
TEMPLATE="$APP_DIR/ExportOptions.template.plist"
OUT="$APP_DIR/ExportOptions.plist"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "    error: $TEMPLATE not found" >&2
  exit 1
fi

mkdir -p "$APP_DIR"
cp "$TEMPLATE" "$OUT"

echo "    wrote $OUT"
echo "    verifying..."
plutil -lint "$OUT"

echo
echo "    Done. Review $OUT, then run:"
echo "      ./scripts/build-and-upload-testflight.sh"
