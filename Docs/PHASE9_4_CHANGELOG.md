# Phase 9.4 Changelog

## Ziel

Phase 9.4 stabilisiert den Composer nach Phase 9.2/9.3 weiter. Der Fokus liegt auf SwiftUI-State-Zyklen und dem Hinweis:

```text
onChange(of: String) action tried to update multiple times per frame.
```

## Änderungen

- Entfernt die direkte `.onChange(of: draft)`-Persistenz im ChatView.
- Draft-Änderungen laufen jetzt über ein explizites `Binding<String>`.
- Drafts werden beim Setzen, Löschen, Senden und Verlassen des Chats persistiert.
- Der UIKit-Privacy-Composer koalesziert schnelle Textänderungen pro Runloop.
- `UITextField`-Events schreiben nicht mehr mehrfach pro Frame in SwiftUI zurück.

## Unverändert

- Relay API
- ACK/Delivery Receipt Flow
- verschlüsseltes Payload-Format
- Keychain/Store-Format
- Pairing/Trust-Modell

## Erwartung

Die Logs sollten nach Phase 9.4 keine oder deutlich weniger Meldungen dieser Form zeigen:

```text
onChange(of: String) action tried to update multiple times per frame.
```
