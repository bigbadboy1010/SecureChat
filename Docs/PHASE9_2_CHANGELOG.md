# PrivateChat Phase 9.2

## Ziel

Phase 9.2 reduziert das verbleibende iOS-/Keyboard-Systemrauschen im Composer, ohne das Relay-Protokoll oder das verschlüsselte Nachrichtenformat zu ändern.

## Änderungen

- Der Privacy-/Keyboard-Schutz verwendet im Composer nun ein eigenes UIKit-basiertes Textfeld.
- Bei aktivem Keyboard-Schutz wird der SwiftUI-`VerticalTextView` nicht mehr verwendet.
- Deaktiviert im Privacy-Composer:
  - Autokorrektur
  - Spellchecking
  - Smart Quotes
  - Smart Dashes
  - Smart Insert/Delete
  - TextContentType
- Return-Taste sendet die Nachricht, wenn der Composer sendefähig ist.
- Der normale mehrzeilige SwiftUI-Composer bleibt verfügbar, wenn der Keyboard-Schutz deaktiviert wird.

## Kompatibilität

- Keine Änderung am Relay-Protokoll.
- Keine Änderung am verschlüsselten Payload-Format.
- Keine Migration erforderlich.
