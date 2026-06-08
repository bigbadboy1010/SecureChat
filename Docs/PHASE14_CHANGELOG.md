# Phase 14 – Professional UI Refresh

## Ziel

Phase 14 bringt eine visuell modernere, professionellere Oberfläche auf die stabile Phase-13-Sicherheitsbasis. Nachrichtenformat, Relay-Protokoll und Crypto-Payload bleiben unverändert.

## Änderungen

- Neues zentrales Design-System in `PrivateChatDesign.swift`
- Glas-/Material-Karten mit einheitlichen Radien, Schatten und Borders
- Neuer Unlock-Screen mit professioneller Security-Positionierung
- Dashboard wird zum `Command Center`
- Hero-Karte mit Runtime-, Sentinel- und Privacy-Status
- Verbesserte Statuskarten und horizontale Status-Pills
- Chatliste mit moderneren Kartenzeilen, klareren Metriken und ruhigerem Hintergrund
- Composer optisch verfeinert mit Material-Bar, Border und konsistenter Send-Aktion
- Chat-Hintergrund auf konsistentes App-Gradient-System umgestellt

## Nicht geändert

- Kein neues Relay-Protokoll
- Kein neues Nachrichtenformat
- Kein neues Crypto-Payload-Format
- Keine Änderung an Schlüsselableitung oder Signaturen

## Teststatus

- RelayServer `npm run typecheck`: erfolgreich
- RelayServer `npm run build`: erfolgreich
- ZIP-Test: erfolgreich
- Xcode/iOS-Build nicht im Container ausführbar, da kein iOS-SDK vorhanden ist.
