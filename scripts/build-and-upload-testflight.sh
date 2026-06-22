#!/usr/bin/env bash
# Build, sign, notarize and upload the SecureChat iOS app to
# TestFlight in one shot.
#
# Usage:
#   ./scripts/build-and-upload-testflight.sh
#
# Optional env vars:
#   ARCHIVE_DIR    Where to put the .xcarchive. Default:
#                  $HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)
#   ARCHIVE_NAME   Default: SecureChat-Bump$(date +%H%M%S)
#   SKIP_UPLOAD=1  Just build the archive, do not upload.
#   SKIP_BUMP=1    Don't auto-increment CURRENT_PROJECT_VERSION.
#
# Required tools: xcodebuild, plutil, xcrun altool.
#
# The script expects:
#   - ExportOptions.plist in apps/SecureChat/ExportOptions.plist
#     (created by the developer; contains signing + notarization
#     settings for the SecureChat distribution team).
#   - An Apple ID app-specific password, stored in the keychain as
#     "AC_PASSWORD" (so xcrun altool can read it). To set it:
#         security add-generic-password -a "<your-apple-id>" \
#             -s "AC_PASSWORD" -w "<app-specific-password>"
#     (see https://appleid.apple.com -> App-Specific Passwords).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO_ROOT/PrivateChat.xcodeproj"
SCHEME="PrivateChat"
APP_DIR="$REPO_ROOT/apps/SecureChat"
EXPORT_OPTIONS="$APP_DIR/ExportOptions.plist"
EXPORT_PATH="$REPO_ROOT/build/testflight-export"

ARCHIVE_DIR="${ARCHIVE_DIR:-$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)}"
ARCHIVE_NAME="${ARCHIVE_NAME:-SecureChat-Bump$(date +%H%M%S)}"
ARCHIVE_PATH="$ARCHIVE_DIR/$ARCHIVE_NAME.xcarchive"

mkdir -p "$ARCHIVE_DIR"

echo "==> 1/5  Bumping CURRENT_PROJECT_VERSION in $PROJECT"
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
echo "==> 2/5  xcodebuild archive -> $ARCHIVE_PATH"
cd "$REPO_ROOT"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" 2>&1 | tail -3

echo
echo "==> 3/5  Verifying archive signature"
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

if [[ "${SKIP_UPLOAD:-}" == "1" ]]; then
  echo
  echo "    SKIP_UPLOAD=1 set, stopping here."
  echo "    Archive ready at: $ARCHIVE_PATH"
  exit 0
fi

echo
echo "==> 4/5  Exporting IPA for TestFlight"
if [[ ! -f "$EXPORT_OPTIONS" ]]; then
  echo "    error: ExportOptions.plist not found at $EXPORT_OPTIONS" >&2
  echo "           create one in Xcode (Organizer -> Distribute App -> TestFlight) and save it to: $EXPORT_OPTIONS" >&2
  echo "           OR run ./scripts/generate-export-options.sh to scaffold one from this repo's settings." >&2
  exit 1
fi

mkdir -p "$EXPORT_PATH"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" 2>&1 | tail -5

IPA_PATH="$EXPORT_PATH/PrivateChat.ipa"
# The exported IPA inherits the Xcode product name. We rename it
# so downstream tools (and humans) see the brand name, not the
# legacy target name. This is purely cosmetic; the bundle inside
# is correctly identified as com.securechat.app either way.
if [[ -f "$IPA_PATH" ]]; then
  RENAME_PATH="$EXPORT_PATH/SecureChat.ipa"
  mv "$IPA_PATH" "$RENAME_PATH"
  IPA_PATH="$RENAME_PATH"
fi
if [[ ! -f "$IPA_PATH" ]]; then
  echo "    error: IPA not found at $IPA_PATH" >&2
  exit 1
fi

echo
echo "==> 5/5  Uploading to TestFlight"
xcrun altool --upload-package \
  --type ios \
  --package "$IPA_PATH" \
  --keychain-info "$HOME/Library/Keychains/login.keychain-db" \
  2>&1 | tail -10 || {
    echo "    altool upload failed. If the error is 'auth':" >&2
    echo "      security add-generic-password -a \"<your-apple-id>\" -s \"AC_PASSWORD\" -w \"<app-specific-password>\"" >&2
    exit 1
  }

echo
echo "==> Done"
echo "    Archive: $ARCHIVE_PATH"
echo "    IPA:     $IPA_PATH"
echo "    Build:   $NEW_VERSION"
echo
echo "    TestFlight will process the build in a few minutes. You'll"
echo "    get an email when it's ready to distribute to testers."
