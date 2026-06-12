# Phase 14.5.4 — Crypto Test Coverage & Safety Number Verification

## Ziel

Phase 14.5.4 setzt die nächsten hoch priorisierten Punkte aus dem Code Review v3 um: bessere Beweisbarkeit der Crypto-Pipeline und eine erste dedizierte Safety-Number-Verifikation im Produkt-UI.

## Änderungen

### Tests

- `Tests/PrivateChatTests/CryptoServiceTests.swift`
  - AES-GCM Roundtrip mit AAD
  - AAD-Tamper-Test
  - Ciphertext-Tamper-Test
  - Ed25519/Curve25519 Signing Roundtrip und Tamper-Test
  - X25519 Pairwise-Key-Determinismus zwischen beiden Peers
  - Peer-ID- und Safety-Number-Stabilität

- `Tests/PrivateChatTests/EncryptedMessageStoreTests.swift`
  - Speichern/Laden von verschlüsselten Conversations
  - Klartext darf nicht im Store-File sichtbar sein
  - fehlender Store lädt sauber eine leere Liste
  - korrupter Store schlägt geschlossen fehl

- `Tests/PrivateChatTests/TestSupport.swift`
  - `MockKeychainStore`
  - isolierte Testverzeichnisse

- `EncryptedDraftStoreTests.swift`
  - erweitert um einen echten `EncryptedDraftStore`-Roundtrip mit Datei-Check, nicht nur `InMemoryDraftStore`.

### Testbarkeit der Stores

- `EncryptedMessageStore` und `EncryptedDraftStore` unterstützen jetzt optional `storageDirectoryURL`.
- Production-Verhalten bleibt unverändert.
- Tests können damit in isolierten Temporary-Directories laufen, ohne den echten App-Store zu berühren.

### Safety Number UI

- Neue View: `PrivateChat/Features/Chat/SafetyNumberView.swift`
- In `ChatDetailsView` integriert über `Safety Number vergleichen`.
- Safety Number wird als 4-Spalten-Raster dargestellt.
- Jede Gruppe muss aktiv bestätigt werden.
- Der Button zur Kontakt-Verifizierung bleibt deaktiviert, bis alle Gruppen bestätigt sind.
- Bestehende Copy-Funktion bleibt erhalten.

## Nicht geändert

- Kein neues Relay-Protokoll.
- Kein neues Crypto-Payload-Format.
- Keine Änderung am Docker/Caddy-Setup.
- Kein ConversationService-Split in dieser Phase. Das bleibt Phase 15.

## Verifikation

- RelayServer `npm run typecheck` erfolgreich.
- RelayServer `npm run build` erfolgreich.
- ZIP enthält kein `node_modules` und kein `RelayServer/dist`.
