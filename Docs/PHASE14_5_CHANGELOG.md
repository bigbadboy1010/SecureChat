# Phase 14.5 — App Store / Security Cleanup

Phase 14.5 addresses the post-Phase 14.4 code review findings that affect app-store readiness and security consistency.

## Fixed

- Added encrypted draft persistence:
  - New `DraftStoring` protocol.
  - New `EncryptedDraftStore` backed by AES-GCM and a Keychain-held draft-store key.
  - New `InMemoryDraftStore` for fallback startup mode.
  - `ChatView` no longer stores new drafts in `UserDefaults`.
  - Legacy `PrivateChat.Draft.<UUID>` UserDefaults values are migrated once into the encrypted draft store and then removed.

- Added iCloud-backup exclusion:
  - `EncryptedMessageStore` now marks the `Application Support/PrivateChat` directory and `messages.store` as excluded from iCloud/device backup.
  - `EncryptedDraftStore` also excludes `drafts.store` from backup.

- Hardened Relay auto-sync lifecycle:
  - `ConversationService` now owns a relay auto-sync `Task` handle.
  - Duplicate auto-sync loops are blocked.
  - `RootView` starts the managed loop and cancels it on disappearance.

- Expanded Privacy Manifest:
  - Added `NSPrivacyAccessedAPICategoryFileTimestamp` with reason `C617.1`.
  - Kept UserDefaults declaration because settings and one-time draft migration still use `UserDefaults`.

- Added real app icon asset:
  - `securechat-appicon-1024.png` is now referenced by the AppIcon asset catalog.

- Started PrivateChat test migration:
  - Added `PrivateChatTests` Xcode target.
  - Added `SecureChatProductionProfileTests`.
  - Added `EncryptedDraftStoreTests` using `InMemoryDraftStore`.

## Not changed

- No Relay protocol changes.
- No transport packet format changes.
- No cryptographic message payload changes.
- No Docker/Caddy changes.

## Still recommended for Phase 15

- Split `ConversationService` into smaller components:
  - `ConversationStore`
  - `RelaySyncCoordinator`
  - `OutboundDeliveryService`
  - `InboundMessageProcessor`
- Add `CryptoServiceTests` and `EncryptedMessageStoreTests`.
- Add Safety Number comparison UI.
- Add Push Notification / silent-sync design.
