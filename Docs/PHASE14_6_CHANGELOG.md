# Phase 14.6 — TestFlight UX Readiness

## Ziel

Phase 14.6 adressiert die Review-v4-Empfehlungen für die ersten TestFlight-Nutzer: Onboarding, Beta-Hinweis, Display-Name-Editor, Solo-Test-Modus und ein nicht-leerer Launch-Screen.

## Änderungen

### Onboarding

- Neuer 3-Screen-Onboarding-Flow beim ersten Start nach Entsperrung.
- Erklärt E2E-Speicherung, Relay-Modi, Pairing und Safety-Number-Verifikation.
- Skip/Fertig-Option für Power-User.
- Onboarding-Status wird in `UserDefaults` gespeichert.

### Beta-Hinweis

- Einmaliger Beta-Disclaimer nach dem Onboarding.
- Hinweis: Production Candidate, externer Security-Audit steht noch aus.
- Settings enthält einen Bereich `Beta & TestFlight` mit Reset-Button für Onboarding/Beta-Hinweis.

### Display-Name-Editor

- Pairing-Tab enthält jetzt einen Editor für den lokalen Anzeigenamen.
- Anzeigename wird im Keychain gespeichert.
- Neue Pairing-Codes verwenden den aktualisierten Namen.
- Neuer `IdentityManagerTests` deckt Persistenz und PairingPayload-Export ab.

### Solo-Test-Modus

- Dashboard enthält eine `TestFlight Einstieg`-Card.
- Button `Solo-Test-Chat anlegen` erstellt einen lokalen Chat ohne Peer und ohne Relay-Transport.
- Dadurch können Tester Composer, Chat-UI und verschlüsselte lokale Speicherung ohne zweites Gerät testen.

### Launch Screen

- `UILaunchScreen` ist nicht mehr leer.
- `UIColorName = systemBackground` gesetzt, um App-Store-/TestFlight-Warnungen wegen leerem Launch-Screen zu vermeiden.

## Nicht geändert

- Kein Relay-Protokoll geändert.
- Kein Nachrichtenformat geändert.
- Kein Crypto-Payload-Format geändert.
- Kein Caddy-/Docker-Setup geändert.
- ConversationService-Split bleibt Phase 15.
- Push Notifications bleiben ein späterer Sprint.

## Verifikation

- `Info.plist` gültig.
- `PrivacyInfo.xcprivacy` gültig.
- `project.pbxproj` gültig.
- AppIcon Contents.json gültig.
- RelayServer `npm run typecheck` erfolgreich.
- RelayServer `npm run build` erfolgreich.
