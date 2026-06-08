# PrivateChat Phase 6

Phase 6 moves the project from a working secure relay prototype toward a usable messenger UI.

## Implemented

- New Status dashboard tab with relay, outbox, unread, peer and security overview.
- Chat list search across titles, peer names and message bodies.
- Chat filters: active, unread, archived.
- Conversation pinning and archiving with context-menu actions.
- Unread tracking for incoming messages using local `readAt` metadata.
- Chat view now marks messages as read when opened.
- Modern chat composer with secure/local banners.
- Message context menu: copy, retry failed/queued messages, delete message.
- Message status labels now use German labels and SF Symbol status icons.
- Dashboard quick actions: sync, retry, purge.
- Backward-compatible local persistence migration for new message/conversation fields.

## Security posture

Phase 6 does not weaken the cryptographic transport. All message payloads remain encrypted and signed as in Phase 5. New read/unread, pinned and archived flags are local UI metadata stored inside the encrypted local message store.

## Still open

- Production HTTPS deployment for relay.
- Push notification strategy.
- Multi-device account/device registry.
- Full per-message Double Ratchet forward secrecy.
- App Store privacy text and final review metadata.
