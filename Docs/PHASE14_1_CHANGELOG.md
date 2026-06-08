# Phase 14.1 – Security UX & Development Runtime Calibration

## Ziel

Phase 14.1 verfeinert die Security-Oberflächen und korrigiert die zu harte Bewertung von Debug-/Mac-/Xcode-Testläufen.

## Änderungen

- Security Sentinel erhält eine professionellere, zentrierte Card-UI.
- App Hardening Ansicht wurde von breiter Tabellenansicht auf moderne Status-Cards umgestellt.
- Debugger in Xcode/Debug-Builds wird als Development-Risiko klassifiziert, nicht mehr automatisch als kompromittierte Production.
- Mac-/Catalyst-/iOS-on-Mac-Runtime wird als Testumgebung erkannt.
- iOS-Jailbreak-Pfade werden in Simulator/Mac/Debug nicht mehr als echte Jailbreak-Signale gewertet.
- Relay-Block bei Runtime-Risiko greift nur noch in produktionsähnlicher Runtime.
- Security Sentinel Score bestraft Development-Runtime nur leicht und erklärt den Unterschied zu Production.

## Unverändert

- Kein neues Relay-Protokoll.
- Kein neues Nachrichtenformat.
- Kein neues Crypto-Payload-Format.
- Keine Änderung an E2E-Verschlüsselung, Signaturen oder Key-Derivation.
