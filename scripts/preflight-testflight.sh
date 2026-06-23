#!/usr/bin/env bash
# preflight-testflight.sh
# Sprint 14+ (2026-06-23): pre-flight check for the SecureChat
# TestFlight upload. Verifies the local toolchain and the project
# state without running the slow xcodebuild step.
#
# Usage:
#   ./scripts/preflight-testflight.sh
#
# Exit code 0 if all checks pass, non-zero on the first failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO_ROOT/PrivateChat.xcodeproj"
TEMPLATE="$REPO_ROOT/apps/SecureChat/ExportOptions.template.plist"
EXPORT_OPTIONS="$REPO_ROOT/apps/SecureChat/ExportOptions.plist"

ok() { printf "  [ok] %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1" >&2; exit 1; }

echo "Pre-flight: SecureChat iOS TestFlight upload"
echo

# 1. xcodebuild
if ! command -v xcodebuild >/dev/null 2>&1; then
  fail "xcodebuild not on PATH (install Xcode and re-run)"
fi
ok "xcodebuild: $(xcodebuild -version | head -1)"

# 2. xcrun + altool
if ! command -v xcrun >/dev/null 2>&1; then
  fail "xcrun not on PATH"
fi
if ! xcrun altool --version >/dev/null 2>&1; then
  fail "xcrun altool not available (need Xcode 14+)"
fi
ok "xcrun altool: $(xcrun altool --version 2>&1 | tail -1)"

# 3. notarytool
if ! xcrun notarytool --version >/dev/null 2>&1; then
  fail "xcrun notarytool not available (need Xcode 13+)"
fi
ok "xcrun notarytool: $(xcrun notarytool --version 2>&1 | tail -1)"

# 4. Template
if [[ ! -f "$TEMPLATE" ]]; then
  fail "ExportOptions.template.plist not found at $TEMPLATE"
fi
if ! plutil -lint "$TEMPLATE" >/dev/null 2>&1; then
  fail "ExportOptions.template.plist is not a valid plist"
fi
ok "ExportOptions.template.plist is a valid plist"

# 5. Generated ExportOptions.plist
if [[ ! -f "$EXPORT_OPTIONS" ]]; then
  printf "  [warn] ExportOptions.plist not generated yet. Run scripts/generate-export-options.sh\n"
else
  if ! plutil -lint "$EXPORT_OPTIONS" >/dev/null 2>&1; then
    fail "ExportOptions.plist is not a valid plist"
  fi
  ok "ExportOptions.plist is a valid plist"
fi

# 6. Team ID
TEAM_ID=$(/usr/libexec/PlistBuddy -c "Print :teamID" "$EXPORT_OPTIONS" 2>/dev/null || echo "")
if [[ -z "$TEAM_ID" ]]; then
  printf "  [warn] could not read teamID from ExportOptions.plist\n"
else
  if [[ "$TEAM_ID" != "355NB9T8RJ" ]]; then
    fail "teamID in ExportOptions.plist is $TEAM_ID (expected 355NB9T8RJ)"
  fi
  ok "teamID = $TEAM_ID"
fi

# 7. Method
METHOD=$(/usr/libexec/PlistBuddy -c "Print :method" "$EXPORT_OPTIONS" 2>/dev/null || echo "")
if [[ "$METHOD" != "app-store-connect" ]]; then
  fail "method = $METHOD (expected app-store-connect for TestFlight)"
fi
ok "method = $METHOD"

# 8. Project file
if [[ ! -f "$PROJECT/project.pbxproj" ]]; then
  fail "project.pbxproj not found at $PROJECT/project.pbxproj"
fi
ok "project.pbxproj exists"

# 9. CURRENT_PROJECT_VERSION
CURRENT_VERSION=$(grep -m1 "CURRENT_PROJECT_VERSION" "$PROJECT/project.pbxproj" | sed 's/.*= //;s/;//' || echo "")
if [[ -z "$CURRENT_VERSION" ]]; then
  fail "could not read CURRENT_PROJECT_VERSION from project.pbxproj"
fi
if ! [[ "$CURRENT_VERSION" =~ ^[0-9]+$ ]]; then
  fail "CURRENT_PROJECT_VERSION = $CURRENT_VERSION (not a number)"
fi
ok "CURRENT_PROJECT_VERSION = $CURRENT_VERSION"

# 10. MARKETING_VERSION
MARKETING=$(grep -m1 "MARKETING_VERSION" "$PROJECT/project.pbxproj" | sed 's/.*= //;s/[";]//g' || echo "")
if [[ -z "$MARKETING" ]]; then
  fail "could not read MARKETING_VERSION from project.pbxproj"
fi
ok "MARKETING_VERSION = $MARKETING"

# 11. Schemes
SCHEMES=$(xcodebuild -project "$PROJECT" -list 2>/dev/null | awk '/Schemes:/,/^$/' | tail -n +2 | sed 's/^[[:space:]]*//' | head -10)
if ! echo "$SCHEMES" | grep -q "^PrivateChat$"; then
  fail "scheme 'PrivateChat' not found in $PROJECT"
fi
ok "scheme 'PrivateChat' is present"

# 12. App Store Connect API key (optional, only if API_KEY env is set)
if [[ -n "${APP_STORE_CONNECT_API_KEY_PATH:-}" ]]; then
  if [[ ! -f "$APP_STORE_CONNECT_API_KEY_PATH" ]]; then
    fail "APP_STORE_CONNECT_API_KEY_PATH=$APP_STORE_CONNECT_API_KEY_PATH not found"
  fi
  ok "API key file: $APP_STORE_CONNECT_API_KEY_PATH"
fi

echo
echo "All checks passed. Next step:"
echo "  ./scripts/build-ios-archive.sh"
echo "Then upload with xcrun altool or Xcode Organizer (see Docs/IOS-TESTFLIGHT-RUNBOOK.md)."
