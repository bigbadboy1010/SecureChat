#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO_ROOT/PrivateChat.xcodeproj"
INFO="$REPO_ROOT/Config/Info.plist"
PRIVACY="$REPO_ROOT/PrivateChat/PrivacyInfo.xcprivacy"
EXPECTED_BUNDLE="org.francois.PrivateChat"
EXPECTED_TEAM="355NB9T8RJ"

ok() { printf "  [ok] %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1" >&2; exit 1; }

echo "SecureChat TestFlight preflight"
echo

command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild not found"
ok "$(xcodebuild -version | head -1)"

[[ -f "$PROJECT/project.pbxproj" ]] || fail "PrivateChat.xcodeproj missing"
[[ -f "$INFO" ]] || fail "Config/Info.plist missing"
[[ -f "$PRIVACY" ]] || fail "PrivacyInfo.xcprivacy missing"
plutil -lint "$INFO" >/dev/null
plutil -lint "$PRIVACY" >/dev/null
ok "Info.plist + PrivacyInfo.xcprivacy valid"

SCHEMES="$(xcodebuild -project "$PROJECT" -list 2>/dev/null)"
grep -q "PrivateChat" <<<"$SCHEMES" || fail "PrivateChat scheme missing"
ok "PrivateChat scheme present"

BUILD_SETTINGS="$(xcodebuild -project "$PROJECT" -scheme PrivateChat -configuration Release -showBuildSettings 2>/dev/null)"
BUNDLE="$(awk -F' = ' '/PRODUCT_BUNDLE_IDENTIFIER = / {print $2; exit}' <<<"$BUILD_SETTINGS")"
TEAM="$(awk -F' = ' '/DEVELOPMENT_TEAM = / {print $2; exit}' <<<"$BUILD_SETTINGS")"
MARKETING="$(awk -F' = ' '/MARKETING_VERSION = / {print $2; exit}' <<<"$BUILD_SETTINGS")"
BUILD="$(awk -F' = ' '/CURRENT_PROJECT_VERSION = / {print $2; exit}' <<<"$BUILD_SETTINGS")"

[[ "$BUNDLE" == "$EXPECTED_BUNDLE" ]] || fail "bundle id is $BUNDLE, expected $EXPECTED_BUNDLE"
[[ "$TEAM" == "$EXPECTED_TEAM" ]] || fail "development team is $TEAM, expected $EXPECTED_TEAM"
[[ "$BUILD" =~ ^[0-9]+$ ]] || fail "CURRENT_PROJECT_VERSION is not numeric: $BUILD"

ok "Bundle ID: $BUNDLE"
ok "Team: $TEAM"
ok "Version: $MARKETING ($BUILD)"

if grep -R --line-number --exclude-dir=.git --exclude='*.md' 'chatsecure\.ddns\.net\|192\.168\.178\.229:8080' "$REPO_ROOT/PrivateChat" "$REPO_ROOT/Config" >/tmp/securechat-legacy-relay.txt 2>/dev/null; then
  cat /tmp/securechat-legacy-relay.txt >&2
  fail "legacy relay address remains in active client code"
fi
ok "No legacy relay address in active client code"

echo
echo "Preflight passed."
echo "Next: open PrivateChat.xcodeproj -> Product -> Test -> Product -> Archive."
