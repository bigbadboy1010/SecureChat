# PrivateChat Phase 5 Changelog

## Focus

Phase 5 hardens the now-stable relay chain for longer running tests on real iPhones. The ACK path from Phase 4.1 remains unchanged and successful; Phase 5 reduces sync noise and adds operational controls for diagnostics and cleanup.

## Added

- Relay stats UI in Security > Transport.
- Manual relay inbox purge for the current local identity.
- Local message retention setting with manual cleanup.
- Relay stats models and client calls:
  - `GET /v1/relay/stats`
  - `POST /v1/relay/messages/purge`
- Stronger local ACK deduplication: packets already acknowledged by this device are skipped before full decrypt/process work.
- Longer local ACK retry suppression window for already acknowledged packets.

## Changed

- Default auto-polling interval is now 15 seconds for calmer logs and lower battery/network pressure.
- Security diagnostics now include local retention information.
- Settings screen exposes Relay Stats and Relay Inbox purge.

## Operational notes

- `GET`, `POST`, and `ACK` relay calls should remain successful.
- Regular `GET /v1/relay/messages` calls are expected while auto-polling is active.
- Apple system logs such as `com.apple.linkd.autoShortcut`, `Reporter disconnected`, `RTIInputSystemClient`, and OTP/autofill warnings are not PrivateChat failures.
- Use manual Relay Inbox purge only for the current test identity when old packets keep reappearing during development.
