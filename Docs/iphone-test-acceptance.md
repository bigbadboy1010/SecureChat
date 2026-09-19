# SecureChat iPhone acceptance test

Repeatable acceptance test for the SecureChat 1.4.2 (Build 13)
TestFlight candidate. Execute the full two-device section before external
distribution.

> Last documentation review: 2026-09-19.

## Scope

This test verifies:

- chat-first navigation and the reduced conversation UI;
- biometric unlock and encrypted local persistence;
- QR pairing and SC2 Safety Number verification;
- production-relay enrollment, delivery and acknowledgement;
- offline recovery and contact lifecycle behavior.

It does not constitute an independent cryptographic or security audit.

## Prerequisites

- Two physical iPhones running iOS 16 or newer.
- SecureChat 1.4.2 (Build 13) installed from the same candidate build.
- Production relay reachable at `https://securechat.team`.
- A valid client `RELAY_AUTH_TOKEN` provided through the controlled tester
  channel. Never paste the token into screenshots, issues or feedback.
- Xcode device console available for the engineering run.

## 1. Release identity and preflight

On the MacBook:

```bash
cd ~/Desktop/Xcode/SecureChat
git status --short
git rev-parse HEAD
./scripts/preflight-testflight.sh
```

Acceptance criteria:

- the working tree is clean;
- the reviewed release commit is checked out;
- preflight reports bundle ID `org.francois.PrivateChat`;
- preflight reports team `355NB9T8RJ`;
- preflight reports version `1.4.2 (13)`;
- preflight ends with `Preflight passed.`.

## 2. First launch and navigation

On device A:

1. Launch SecureChat and complete onboarding.
2. Accept the beta notice.
3. Unlock with Face ID or Touch ID.
4. Confirm that the initial application tab is `Chats`.
5. Confirm that the tab bar contains only `Chats`, `Kontakte` and
   `Einstellungen`.
6. Confirm that the conversation list does not show relay counters,
   security-score cards or sync-result rows.
7. Open `Einstellungen → Diagnose & Sicherheitsstatus` and confirm that the
   technical status remains available outside the normal chat flow.

## 3. Local encrypted-chat smoke test

On device A:

1. Under `Chats`, create a local chat.
2. Send at least two messages.
3. Enter a third message without sending it.
4. Force-quit SecureChat and launch it again.
5. Unlock the app.

Acceptance criteria:

- sent messages are still present;
- the unsent encrypted draft is restored;
- the composer contains the message field and send action without persistent
  implementation-detail banners;
- search finds a known message;
- pin, mute, archive and restore work from swipe/context actions;
- deleting a message requires an explicit destructive action.

## 4. Pair both devices

On both devices:

1. Open `Kontakte` and set a distinct display name.
2. On device A, show the local QR code.
3. On device B, scan device A's QR code.
4. Repeat in the opposite direction if the contact is not already available
   on both devices.
5. Open the Safety Number view on each device.
6. Compare the complete SC2 Safety Number over an independent channel or in
   person.
7. Confirm verification only when both values are identical.

Acceptance criteria:

- QR import succeeds without exposing private keys;
- both devices display the same SC2 Safety Number for the pair;
- no one-tap verification bypass is available;
- an unverified or blocked peer cannot silently become verified.

## 5. Configure the production relay

On both devices:

1. Open `Einstellungen` and select relay transport.
2. Set the relay URL to `https://securechat.team`.
3. Enter only the client `RELAY_AUTH_TOKEN` value.
4. Save the configuration.
5. Open `Einstellungen → Diagnose & Sicherheitsstatus` and refresh the relay
   status.

Acceptance criteria:

- the relay is reported as reachable/healthy;
- no active configuration references `chatsecure.ddns.net`, a LAN address or
  plain HTTP;
- no admin token is present in the app;
- a missing or invalid client token produces an actionable error and does not
  silently fall back to an insecure transport.

## 6. Bidirectional delivery

1. Send a unique message from device A to device B.
2. Confirm receipt on device B.
3. Send a different unique message from device B to device A.
4. Confirm receipt on device A.
5. Force-quit both apps, relaunch and unlock them.

Acceptance criteria:

- both messages decrypt correctly only on their recipient devices;
- outgoing delivery state reaches the expected delivered state;
- messages remain readable after relaunch;
- duplicate relay packets do not create duplicate chat messages;
- no message plaintext, token or private key appears in the Xcode console.

## 7. Offline and retry behavior

1. Disable network access on device B.
2. Send a message from device A to device B.
3. Re-enable network access on device B.
4. Open SecureChat or wait for the configured polling cycle.

Acceptance criteria:

- the message is queued while device B is offline;
- the message arrives after connectivity returns;
- the acknowledgement removes the relay packet according to the retention
  policy;
- retry does not duplicate the message.

## 8. Trust lifecycle

Test the following flows:

1. Block the peer and confirm that sending is prevented.
2. Unblock and require the intended verification state.
3. Delete the contact.
4. Re-import the contact by QR code.
5. Compare the Safety Number again before verification.

Acceptance criteria:

- block, unverify and delete remove associated experimental ratchet state;
- deleting a contact does not preserve a verified state for the new import;
- re-pairing never bypasses Safety Number comparison.

## 9. Device-log review

The following Apple framework messages are non-blocking when the app remains
responsive and no SecureChat exception accompanies them:

- `com.apple.PointerUI.pointeruid.default-service`;
- `cannot add handler to 0 from 0 - dropping`;
- `UIKBDynamicRenderFactory` setting messages;
- navigation-bar snapshot timing warnings;
- context-menu update timing warnings.

The test fails for crashes, Swift fatal errors, uncaught exceptions, repeated
SecureChat transport/decryption errors, plaintext leakage or legacy relay
network requests.

## Final pass criteria

The candidate passes only when:

- Xcode unit tests and GitHub iOS CI are green;
- the preflight passes from a clean checkout;
- all chat-first UI checks pass on a physical iPhone;
- two-device pairing, SC2 comparison and bidirectional relay delivery pass;
- encrypted local state survives force-quit/relaunch;
- offline recovery and trust-lifecycle tests pass;
- no release-blocking finding remains open in `RELEASE_CHECKLIST.md`.
