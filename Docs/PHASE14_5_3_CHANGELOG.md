# Phase 14.5.3 — SecureChat Desktop/App Icon & SwiftUI Update Stabilization

## Änderungen

- Neues SecureChat Icon in `PrivateChat/Assets.xcassets/AppIcon.appiconset` integriert.
- AppIcon-Set erweitert um iPhone-, iPad-, macOS-/Desktop-kompatible Icon-Größen und iOS-Marketing-Icon 1024×1024.
- Zusätzliches Desktop-Quellbild abgelegt unter `PrivateChat/Resources/SecureChatDesktopIcon.png`.
- Letzte app-eigene `onChange`-Handler in `ChatView.swift` und `ServiceErrorAlert.swift` durch `.task(id:)`-basierte, asynchrone Aktualisierung ersetzt, um SwiftUI-Frame-Update-Warnungen weiter zu reduzieren.

## Hinweis

Die übrigen Logs wie `LSPrefs`, `linkd.autoShortcut`, `CSInlineDonation`, `PointerUI` und `ViewBridge` sind Apple-/Xcode-/Simulator-/Runtime-Ausgaben und kein Relay- oder SecureChat-Serverfehler.
