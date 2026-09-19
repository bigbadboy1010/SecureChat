# SecureChat iOS – Xcode / TestFlight Runbook

Current candidate:

- Marketing version: **1.4.2**
- Build: **13**
- Project: `PrivateChat.xcodeproj`
- Scheme / target: `PrivateChat`
- Bundle ID: `org.francois.PrivateChat`
- Minimum iOS: 16
- Production relay: `https://securechat.team`

This runbook intentionally uses **Xcode Organizer** for distribution.
No command-line uploader is required.

## 1. Update the MacBook checkout

```bash
cd ~/Desktop/Xcode/SecureChat
git fetch origin
git switch fix/testflight-prod-gate-20260919
git pull --ff-only origin fix/testflight-prod-gate-20260919
```

After the reviewed branch is merged, use `main` for the final archive.
Never archive an uncommitted or locally divergent checkout.

Confirm that the expected release is present:

```bash
grep -m1 'MARKETING_VERSION' PrivateChat.xcodeproj/project.pbxproj
grep -m1 'CURRENT_PROJECT_VERSION' PrivateChat.xcodeproj/project.pbxproj
```

Expected app values are `1.4.2` and `13`.

## 2. Run local preflight

```bash
cd ~/Desktop/Xcode/SecureChat
./scripts/preflight-testflight.sh
```

The preflight validates the project, scheme, plist/privacy manifest,
exact bundle identifier, team, build number and active-code references to
obsolete relay endpoints. It does not upload anything. The legacy endpoint
values retained exclusively for automatic configuration migration are
intentionally permitted.

## 3. Build and test before Archive

Open the project:

```bash
open ~/Desktop/Xcode/SecureChat/PrivateChat.xcodeproj
```

In Xcode:

1. Select scheme **PrivateChat**.
2. Select a physical iPhone and run the app once.
3. **Product → Test**.
4. Confirm that SecureChat opens on `Chats` and shows exactly three tabs:
   `Chats`, `Kontakte`, `Einstellungen`.
5. Confirm that the chat list has no operational dashboard or relay-result
   rows and that the composer shows only the message field and send action.
6. Verify under `Einstellungen → Diagnose & Sicherheitsstatus` that the app
   shows the canonical relay
   `https://securechat.team`.
7. Use a fresh/re-paired contact and compare the same **SC2 Safety
   Number** on both devices.
8. Verify SEND → receive → ACK in both directions.

The active TestFlight message path is protocolVersion 2
(X25519/HKDF/AES-GCM + Ed25519 signed envelope). The experimental
Double Ratchet code remains disabled for Release/TestFlight pending
dedicated cryptographic review.

## 4. Create the archive

In Xcode:

1. Select **Any iOS Device (arm64)** / generic iOS device.
2. **Product → Clean Build Folder**.
3. **Product → Archive**.
4. Wait for Organizer to open.
5. Select the newest SecureChat / PrivateChat archive.
6. Confirm version **1.4.2 (14)** and bundle
   `org.francois.PrivateChat`.

If Archive fails, do not change bundle IDs or signing identities to
work around it. Fix the signing/project error first.

## 5. Upload through Organizer

In Organizer:

1. **Distribute App**
2. **App Store Connect**
3. **Upload**
4. Keep **Automatically manage signing** enabled unless there is a
   known provisioning reason not to.
5. Review validation warnings.
6. Upload.

After App Store Connect finishes processing, add Build 14 only to the
small internal TestFlight group first.

## 6. Mandatory Build 14 device checks

Use two physical iPhones, preferably on different networks.

- Fresh install and existing-install upgrade.
- Face ID / Touch ID unlock.
- Launch destination is `Chats`; tabs are `Chats`, `Kontakte`,
  `Einstellungen`.
- Local chat creation, message send, encrypted persistence after relaunch
  and draft restoration.
- Pairing by QR under `Kontakte`.
- Same SC2 Safety Number displayed on both devices.
- No direct verification without the Safety Number flow.
- Send/receive in both directions.
- Send a photo and a short video from the library in both directions;
  open each received attachment.
- Send a PDF and a text document from Files in both directions; open each
  received attachment and verify it remains available after relaunch.
- Capture and send a photo and a short video from a physical device camera.
- Confirm a larger attachment does not trigger HTTP 429 while its paced chunk
  transfer is running.
- Retry one deliberately interrupted attachment and confirm the recipient queue
  does not grow by a second complete set of chunks.
- Verify chat text remains clearly readable in light and dark appearance.
- App kill/relaunch between messages.
- Offline → reconnect → inbox delivery.
- Duplicate/retry behavior.
- Block → unblock → re-pair.
- Delete contact → re-pair.
- Relay peer enrollment works after fresh install.
- Diagnostics remain reachable under
  `Einstellungen → Diagnose & Sicherheitsstatus`.
- Xcode/device logs contain no calls to `chatsecure.ddns.net`,
  `192.168.*:8080` or other legacy relay addresses.

### Recovering a full recipient queue

`Recipient relay queue limit exceeded` means the target peer has reached the
relay's stored-packet cap; it is not a camera or attachment-picker failure.
First leave SecureChat open on the receiving device and run
`Einstellungen → Diagnose & Sicherheitsstatus → Inbox synchronisieren` until
the relay packet count falls. ACKs and delivery receipts are paced so this
cleanup stays below the production request-rate limit.

For a test identity whose pending encrypted packets may be discarded, an
operator can instead call `POST /v1/admin/relay/messages/purge` with that
recipient's 64-character peer ID and `RELAY_ADMIN_TOKEN`. This is destructive:
all undelivered relay packets for that recipient are removed. Never place the
admin token in the app.

## 7. Before external testers

Complete the remaining items in `RELEASE_CHECKLIST.md`, including
App Store privacy answers, export compliance and the external security
review requirement for stronger security claims.

Do not describe Build 14 as externally audited, Signal-protocol
compatible, or as using a reviewed production Double Ratchet.
