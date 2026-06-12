# Phase 14.5.1 — iOS 17 onChange Cleanup

## Änderungen

- `ChatView.swift`: `onChange(of:)` auf die iOS-17-kompatible Zwei-Parameter-Closure umgestellt.
- `ServiceErrorAlert.swift`: `onChange(of:)` auf die iOS-17-kompatible Zwei-Parameter-Closure umgestellt.
- Keine Änderung am Relay-Protokoll.
- Keine Änderung am Nachrichtenformat.
- Keine Änderung am Crypto-Payload-Format.
- Keine Server-/Docker-/Caddy-Änderung.

## Hinweis

Die Runtime-Meldung `non-launching port is incompatible with service identifier "com.apple.PointerUI.pointeruid.default-service"` stammt aus Apple PointerUI/UIKit Runtime und ist kein SecureChat-Relay- oder App-Codefehler.
