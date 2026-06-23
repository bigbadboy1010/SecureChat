# SecureChat iOS Build & TestFlight Upload — Runbook (2026-06-23)

## Status

**This document is a runbook, not a script that runs by itself.**
The actual `xcodebuild archive` + `xcrun altool --upload-app` /
`xcrun notarytool submit` steps require:

- An interactive Apple ID sign-in (the first time), or
- A pre-generated App Store Connect API key in
  `~/private_keys/AuthKey_XXXXXXXXXX.p8`
- A Developer-ID signing identity in the keychain
  (`Apple Distribution: François Mignault (355NB9T8RJ)`)

The repo's `scripts/build-and-upload-testflight.sh` handles
the build step. The upload step requires manual sign-in or
an API key.

## Pre-flight (already done 2026-06-23)

| Check | Result |
|---|---|
| `apps/SecureChat/ExportOptions.template.plist` is valid | ✅ `plutil -lint` OK |
| `apps/SecureChat/ExportOptions.plist` generated | ✅ team `355NB9T8RJ`, method `app-store-connect` |
| `CURRENT_PROJECT_VERSION = 10` in pbxproj | ✅ |
| `MARKETING_VERSION = 1.0` in pbxproj | ✅ |
| Xcode 27.0 + `xcodebuild` + `xcrun altool` + `notarytool` | ✅ |
| `apps/SecureChat/ExportOptions.plist` is gitignored | ✅ |

## Step 1 — Generate `ExportOptions.plist` (idempotent)

```bash
cd ~/Desktop/Xcode/SecureChat
./scripts/generate-export-options.sh
```

The script reads `apps/SecureChat/ExportOptions.template.plist`,
copies it to `apps/SecureChat/ExportOptions.plist`, and runs
`plutil -lint`. The generated file is gitignored; rerun the
script any time you change the template.

## Step 2 — Build the archive

```bash
cd ~/Desktop/Xcode/SecureChat
./scripts/build-ios-archive.sh
```

What the script does (3 steps):

1. **Bumps `CURRENT_PROJECT_VERSION`** in pbxproj. Set
   `SKIP_BUMP=1` to skip the bump (you have already bumped
   to 10 in commit `1efb9b5`).
2. **Runs `xcodebuild archive`** with scheme `PrivateChat`,
   destination `generic/platform=iOS`, configuration
   `Release`, and writes the archive to
   `~/Library/Developer/Xcode/Archives/YYYY-MM-DD/SecureChat-BumpHHMMSS.xcarchive`.
3. **Verifies the codesign** of the embedded `.app`.

Expected duration: 5-10 minutes on a modern Mac, mostly
the SwiftPM dependency graph and the dSYM generation. The
"WebRTC.framework dSYM" warning that the user received on
2026-06-23 is from a different project; SecureChat does
not include WebRTC. The archive step for SecureChat is
expected to finish without dSYM warnings.

## Step 3 — Upload to TestFlight

You have two options. Pick the one that matches your setup.

### Option A — App Store Connect API key (recommended, non-interactive)

```bash
# 1. Generate an API key in App Store Connect
#    (Users and Access -> Keys -> App Store Connect API -> Generate)
# 2. Save the .p8 file to ~/private_keys/AuthKey_XXXXXXXXXX.p8
# 3. Note the Key ID (XXXXXXXXXX) and the Issuer ID

cd ~/Desktop/Xcode/SecureChat
export APP_STORE_CONNECT_API_KEY_PATH=~/private_keys/AuthKey_XXXXXXXXXX.p8
export APP_STORE_CONNECT_KEY_ID=XXXXXXXXXX
export APP_STORE_CONNECT_ISSUER_ID=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy

# Validate the archive with the App Store Connect API
xcrun altool --validate-app \
  -f "$HOME/Library/Developer/Xcode/Archives/2026-06-23/SecureChat-Bump123456.xcarchive" \
  --type ios \
  --apiKey "$APP_STORE_CONNECT_API_KEY_PATH" \
  --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"

# Upload to TestFlight
xcrun altool --upload-app \
  -f "$HOME/Library/Developer/Xcode/Archives/2026-06-23/SecureChat-Bump123456.xcarchive" \
  --type ios \
  --apiKey "$APP_STORE_CONNECT_API_KEY_PATH" \
  --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"
```

The upload finishes in 1-3 minutes for a typical iOS app.
App Store Connect then processes the build (5-30 minutes)
and assigns a build number. The new build appears in
**TestFlight → iOS Builds** for the SecureChat app.

### Option B — Interactive sign-in (no API key)

```bash
cd ~/Desktop/Xcode/SecureChat
open -a Xcode ~/Desktop/Xcode/SecureChat/PrivateChat.xcodeproj
```

In Xcode:

1. **Window → Organizer** (or `⇧⌘9`)
2. Select the latest archive in the list.
3. Click **Distribute App** (top right).
4. Choose **App Store Connect → Upload**.
5. Choose **Automatically manage signing** (the team
   is already pinned to `355NB9T8RJ`).
6. **Re-sign the archive** if Xcode asks.
7. **Upload**. If the dSYM warning shows up for any
   framework, click **Continue** — the warning is
   non-fatal and the upload proceeds.
8. App Store Connect will email when the build is
   processed. Then go to **TestFlight → SecureChat →
   Builds**, add the new build to a tester group.

## Step 4 — Update the TestFlight public description

The TestFlight public description in App Store Connect
should match the latest release notes. The current
text lives in `Docs/TESTFLIGHT-LISTING-COPY.md`. After
uploading Build 10, update the "What's New" field to:

> This build includes the peer-bound request signing
> rollout (Sprint 14-16) — every message now carries
> an Ed25519 signature bound to the sender's public key,
> and the relay is wired to verify it before relaying.
> No new user-facing settings.

## Step 5 — Notify testers

After the build is processed, send the test-flight
public link to the tester group. The current public
invite is sent via `mailto:hello@securechat.team`
because TestFlight is invite-only for SecureChat.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `xcodebuild archive` fails with code-sign error | No Developer-ID identity in the keychain | Xcode → Settings → Accounts → Add Apple ID → Download Manual Profiles |
| `xcrun altool --upload-app` returns "Authentication error" | API key path / Key ID / Issuer ID mismatch | Re-check the three values; the path is absolute, the Key ID has no slashes, the Issuer ID is a UUID |
| Build appears in App Store Connect but the version is wrong | Forgot to bump `CURRENT_PROJECT_VERSION` | Run `./scripts/build-ios-archive.sh` again; the script auto-bumps unless you set `SKIP_BUMP=1` |
| dSYM warning for WebRTC.framework | The user has a different project open in Xcode that uses WebRTC | Switch to SecureChat; the warning only appears for archives of the other project |
| "Redundant Binary Upload" | `CURRENT_PROJECT_VERSION` was not bumped between uploads | Set `SKIP_BUMP=0` (the default) on the next `./scripts/build-ios-archive.sh` |
| "Missing required module" | The SwiftPM dependency cache is stale | `xcodebuild -resolvePackageDependencies -project PrivateChat.xcodeproj` |

## Files touched by this runbook

This document is the only new file. The actual build artifacts
(`*.xcarchive`) live under `~/Library/Developer/Xcode/Archives/`
and are not committed.
