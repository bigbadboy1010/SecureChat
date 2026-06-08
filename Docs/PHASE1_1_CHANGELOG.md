# PrivateChat Phase 1.1 Changelog

## Fixes

- Fixed SwiftUI `Section` generic inference issue in `PrivateChat/Features/Settings/SettingsView.swift`.
- Replaced shorthand `Section("Title")` usages in active app views with explicit `SwiftUI.Section { } header: { }` syntax.
- Kept `Bundle Identifier` as `org.francois.PrivateChat` and app display name as `PrivateChat`.

## Affected files

- `PrivateChat/Features/Settings/SettingsView.swift`
- `PrivateChat/Features/Chat/ConversationListView.swift`
- `PrivateChat/Features/Pairing/PairingView.swift`
