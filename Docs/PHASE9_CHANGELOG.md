# PrivateChat Phase 9 Changelog

Phase 9 baut auf dem stabilen Phase-8.1-Relay auf. Das Relay-Protokoll bleibt kompatibel; der Fokus liegt auf Privacy, Diagnose und UI-Reife.

## Neu

- Vorschau-Schutz für Chatlisten
  - blendet Nachrichteninhalte in der Chatübersicht aus
  - Status, Badges, Pin/Archiv/Stumm bleiben sichtbar
- Keyboard-Schutz im Composer
  - Autokorrektur/Vorschläge können reduziert werden
  - Ziel: weniger iOS-Keyboard-Systemnoise im Debug-Log
- Diagnosebericht
  - teilbar über Share Sheet
  - kopierbar in die Zwischenablage
  - enthält technische Metadaten, aber keine Nachrichteninhalte
- Chat-Details erweitert
  - Chat-Name direkt umbenennen
  - vorhandene Analytics, Export und Sicherheitsdaten bleiben erhalten
- Dashboard erweitert
  - Vorschau-Schutz sichtbar
  - Keyboard-Schutz sichtbar

## Migration

`AppSecurityState` wurde rückwärtskompatibel erweitert:

- `hideMessagePreviews`
- `reduceKeyboardSuggestions`

Alte Settings werden automatisch mit sicheren Defaults geladen.

## Kompatibilität

- Relay API bleibt kompatibel zu Phase 8.1
- Keine Änderung am Transport-Paketformat
- Keine Änderung an Pairing-QR-Codes
