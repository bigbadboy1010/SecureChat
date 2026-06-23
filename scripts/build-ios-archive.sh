#!/usr/bin/env bash
# Build the SecureChat iOS app for the App Store / TestFlight.
#
# This is the SecureChat counterpart of Loupe's
# scripts/build-and-upload-testflight.sh. It does the same three
# steps but stops just before upload, so you can inspect the
# archive first or run scripts/upload-ios-testflight.sh separately.
#
# Usage:
#   ./scripts/build-ios-archive.sh
#
# Optional env vars:
#   ARCHIVE_DIR    Where to put the .xcarchive. Default:
#                  $HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)
#   ARCHIVE_NAME   Default: SecureChat-Bump$(date +%H%M%S)
#   SKIP_BUMP=1    Don't auto-increment CURRENT_PROJECT_VERSION
#                  (useful when you bumped it manually).
#
# The script auto-increments CURRENT_PROJECT_VERSION each run, so
# the TestFlight "Redundant Binary Upload" error cannot happen.
#
# Required tools: xcodebuild, plutil.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO_ROOT/PrivateChat.xcodeproj"
SCHEME="PrivateChat"

ARCHIVE_DIR="${ARCHIVE_DIR:-$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)}"
ARCHIVE_NAME="${ARCHIVE_NAME:-SecureChat-Bump$(date +%H%M%S)}"
ARCHIVE_PATH="$ARCHIVE_DIR/$ARCHIVE_NAME.xcarchive"

mkdir -p "$ARCHIVE_DIR"
echo
echo "==> 1/3  Bumping CURRENT_PROJECT_VERSION in $PROJECT"
CURRENT_VERSION=$(grep -m1 "CURRENT_PROJECT_VERSION" "$PROJECT/project.pbxproj" | sed 's/.*= //;s/;//')
if [[ -z "$CURRENT_VERSION" ]]; then
  echo "    error: could not read CURRENT_PROJECT_VERSION from $PROJECT" >&2
  exit 1
fi
if [[ "${SKIP_BUMP:-}" == "1" ]]; then
  echo "    SKIP_BUMP=1, leaving at $CURRENT_VERSION"
  NEW_VERSION="$CURRENT_VERSION"
else
  NEW_VERSION=$((CURRENT_VERSION + 1))
  echo "    $CURRENT_VERSION -> $NEW_VERSION"
  sed -i '' "s/CURRENT_PROJECT_VERSION = $CURRENT_VERSION;/CURRENT_PROJECT_VERSION = $NEW_VERSION;/g" \
    "$PROJECT/project.pbxproj"
fi
echo
echo "==> 2/3  xcodebuild archive -> $ARCHIVE_PATH"
cd "$REPO_ROOT"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" 2>&1 | tail -5

echo
echo "==> 3/3  Verifying archive signature"
# The .app name in the archive follows PRODUCT_NAME / BUILDABLE_NAME
# in project.pbxproj. The current product name is "PrivateChat" (the
# Xcode target is still called PrivateChat, even though the bundle
# identifier and CFBundleDisplayName are now SecureChat). The bundle
# name on the user's home screen is "SecureChat" via the display
# name in Config/Info.plist, which is what really matters.
APP_BUNDLE="$ARCHIVE_PATH/Products/Applications/PrivateChat.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
  APP_BUNDLE="$ARCHIVE_PATH/Products/Applications/SecureChat.app"
fi
if [[ -d "$APP_BUNDLE" ]]; then
  codesign -dvv "$APP_BUNDLE" 2>&1 | grep -E "Identifier=|TeamIdentifier=|Authority=" | head -5
else
  echo "    warning: no .app found at $APP_BUNDLE (archive incomplete?)"
  echo "    archive contents:"
  ls -la "$ARCHIVE_PATH/Products/Applications/" 2>&1 | head -10
fi

echo
echo "==> Done"
echo "    Archive: $ARCHIVE_PATH"
echo "    Build version: $NEW_VERSION"
echo
echo "    Next:"
echo "      ./scripts/upload-ios-testflight.sh $ARCHIVE_PATH"
echo "    Or open Xcode -> Window -> Organizer -> Archives to distribute manually."
