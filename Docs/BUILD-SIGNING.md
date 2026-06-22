# SecureChat iOS Build, Signing & Notarization

This document is the **single source of truth** for turning the
SecureChat iOS source tree into a signed, notarized, TestFlight-ready
build. It mirrors the Loupe `docs/CONTRIBUTING.md` / `BUILD-SIGNING`
setup but adapted for SecureChat's slightly different scripts.

## TL;DR (for François)

To build a TestFlight-ready IPA from a clean checkout:

```bash
cd ~/Desktop/Xcode/SecureChat
./scripts/build-ios-archive.sh              # builds .xcarchive
./scripts/generate-export-options.sh        # creates ExportOptions.plist
xcodebuild -exportArchive \
  -archivePath ~/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/SecureChat-Bump*.xcarchive \
  -exportPath build/testflight-export \
  -exportOptionsPlist apps/SecureChat/ExportOptions.plist
xcrun altool --upload-package \
  --type ios \
  --package build/testflight-export/SecureChat.ipa
```

Or, in one shot:

```bash
./scripts/build-and-upload-testflight.sh
```

…assuming the App Store Connect keychain entry is set up
(see "App Store Connect password" below).

---

## 1. What lives in this repo

```
scripts/
  build-ios-archive.sh            # Bumps build number, runs xcodebuild archive.
  build-and-upload-testflight.sh  # archive -> IPA -> TestFlight upload (one shot).
  generate-export-options.sh      # Creates ExportOptions.plist from the template.
  notarize-mac-binary.sh          # Notarizes a macOS .app/.dmg/.pkg.
  deploy-relay.sh                 # Deploys the Relay to the Lenovo server.
  test-relay.sh                   # Smoke-tests the live Relay.

apps/SecureChat/
  ExportOptions.template.plist    # Template for the (gitignored) ExportOptions.plist.
  (ExportOptions.plist is generated and gitignored.)
```

The Relay-server build, the Caddyfile patch, and the rest of the
ops machinery live under `RelayServer/`, `Docs/`, and `CHANGELOG.md`.
They are **not** in the iOS build scope.

## 2. Code-signing identity

| Key                       | Value                                                                                |
|---------------------------|--------------------------------------------------------------------------------------|
| Team ID                   | `355NB9T8RJ` (Apple Distribution: Francois Alexandre Marie De Lattre)                |
| Bundle ID (app)           | `com.securechat.app`                                                                 |
| Bundle ID (tests)         | `com.securechat.app.tests`                                                           |
| Marketing version         | `0.1.0` (in `MARKETING_VERSION`, set in Xcode Build Settings)                        |
| Build number              | `CURRENT_PROJECT_VERSION`, auto-incremented by `build-ios-archive.sh`                |
| Provisioning profile name | `SecureChat App Store` (must exist in App Store Connect; create it if missing)       |
| `CODE_SIGN_STYLE`         | `Automatic` (Xcode picks the right distribution identity from the team)              |
| iCloud environment        | `Production` (we don't ship an iCloud-enabled variant)                               |

These settings live in `PrivateChat.xcodeproj/project.pbxproj`.
Do **not** change the team ID or bundle ID without coordinating
with François — TestFlight and App Store Connect group builds by
bundle ID and team.

## 3. App Store Connect password

`xcrun altool --upload-package` and `xcrun notarytool` both need an
app-specific password. The convention in this repo is to read it
from the keychain entry `AC_PASSWORD`. To set it up:

```bash
security add-generic-password -a "fdelattre1010@gmail.com" \
  -s "AC_PASSWORD" -w "<app-specific-password>"
```

You can generate the app-specific password at
<https://appleid.apple.com> → "App-Specific Passwords".

Once stored, the `xcrun` tools will pick it up automatically
when called with the default keychain.

## 4. What each script does

### `scripts/build-ios-archive.sh`

1. Reads `CURRENT_PROJECT_VERSION` from `project.pbxproj`.
2. Bumps it by 1 (so TestFlight doesn't reject the build as
   "Redundant Binary Upload"). Set `SKIP_BUMP=1` to opt out.
3. Runs `xcodebuild archive` with `Release` configuration and
   `generic/platform=iOS` destination, writing to
   `~/Library/Developer/Xcode/Archives/YYYY-MM-DD/SecureChat-Bump*.xcarchive`.
4. Verifies the archive's code signature with `codesign -dvv`.

The output is a `.xcarchive` (a folder, not a single file) ready
for `xcodebuild -exportArchive` or Xcode's Organizer.

### `scripts/build-and-upload-testflight.sh`

Does everything `build-ios-archive.sh` does, plus:

5. Generates an IPA from the archive using
   `xcodebuild -exportArchive` with the
   `ExportOptions.plist` (which must exist at
   `apps/SecureChat/ExportOptions.plist`).
6. Uploads the IPA to TestFlight via `xcrun altool`.

Set `SKIP_UPLOAD=1` to stop after the archive is built.

### `scripts/generate-export-options.sh`

Copies `apps/SecureChat/ExportOptions.template.plist` to
`apps/SecureChat/ExportOptions.plist` (the latter is gitignored,
so it stays out of source control). The generated file contains:

- `method = app-store-connect` (TestFlight, not direct App Store)
- `signingStyle = automatic` (Xcode resolves the identity)
- `teamID = 355NB9T8RJ`
- `uploadSymbols = true` (for symbolicated crash reports)
- `provisioningProfiles = { "com.securechat.app": "SecureChat App Store" }`

Verify it after generation with `plutil -lint ExportOptions.plist`.

### `scripts/notarize-mac-binary.sh`

Used for macOS binaries (the iOS app does **not** need this —
Apple handles notarization of TestFlight builds automatically).
The script wraps `xcrun notarytool submit` with the same keychain
convention as the iOS build, polls for completion, and staples the
ticket back.

Set `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_PASSWORD` env vars
before running.

## 5. Verifying a build

After a successful TestFlight upload, sanity-check the build by:

1. Opening App Store Connect → My Apps → SecureChat → TestFlight.
2. Confirming the new build number appears in the "Builds" list
   (processing usually takes 1-5 minutes).
3. Installing it on a real device via the TestFlight app.
4. Running through the onboarding, sending a test message, and
   confirming the Live-Encryption-Pulse on the lock screen
   animates correctly.

## 6. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `error: ... "Your team has no iOS Distribution certificate"` | The team's Apple Distribution cert isn't installed locally. | Open Keychain Access → log in to appleid.apple.com → "Manage your certificates" → download. |
| `altool: "Auth is invalid"` | Wrong / expired app-specific password. | Regenerate at appleid.apple.com → App-Specific Passwords. |
| `error: Redundant Binary Upload` | Build number not bumped. | Run `SKIP_BUMP=1` is **not** what you want — the script auto-bumps, so check it actually did. |
| `error: Bundle identifier already in use` | Bundle ID exists in another team's App Store Connect. | Use a different bundle ID (e.g. `com.securechat.app.beta`). |
| Archive builds fine but export fails with "Provisioning profile not found" | The `SecureChat App Store` profile doesn't exist. | Create it in developer.apple.com → Profiles → iOS App Store. |
| xcodebuild complains about `iphoneos-Deployment-Target` mismatch | Minimum iOS version in pbxproj differs from what the project compiles for. | Check `IPHONEOS_DEPLOYMENT_TARGET` in Build Settings. |

## 7. CI integration (future)

The scripts are designed to be CI-friendly:

- `SKIP_BUMP=1` for reproducible builds
- `SKIP_UPLOAD=1` for archive-only runs
- All output goes to stdout (no interactive prompts)
- Keychain entry name is a constant (`AC_PASSWORD`)

When we move to CI, the only additions will be:

1. A `~/.config/sign/AC_PASSWORD` provisioning step
2. A Fastlane lane wrapping these scripts
3. A `build/testflight-export` upload artifact
