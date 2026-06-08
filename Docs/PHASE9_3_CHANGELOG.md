# PrivateChat Phase 9.3

## Ziel

Phase 9.3 stabilisiert den Privacy-Composer aus Phase 9.2. Die Nutzerlogs zeigten keine Relay-Probleme mehr, aber SwiftUI meldete `AttributeGraph: cycle detected` und `Modifying state during view update`.

## Änderungen

- `ChatView` entkoppelt Composer-Fokus von SwiftUI `@FocusState`.
- `PrivacyComposerTextField` ruft aus `updateUIView` kein `becomeFirstResponder()` oder `resignFirstResponder()` mehr auf.
- UIKit-Delegate-Callbacks schreiben Textänderungen asynchron zurück nach SwiftUI.
- Submit aus dem UIKit-Textfeld wird asynchron auf dem Main-Queue ausgeführt.
- `markConversationRead` aus `ChatView` wird nicht mehr direkt während Scroll-/View-Update-Zyklen ausgeführt, sondern auf den nächsten Main-Runloop verschoben.
- Relay-Protokoll, Crypto-Payloads und Store-Format bleiben unverändert.

## Erwartetes Ergebnis

- deutlich weniger `AttributeGraph: cycle detected`
- keine `Modifying state during view update`-Warnung aus dem Chat-Composer
- weiterhin reduzierte Keyboard-Vorschläge im Privacy-Modus
- kein Relay-/Transport-Migrationsbedarf
