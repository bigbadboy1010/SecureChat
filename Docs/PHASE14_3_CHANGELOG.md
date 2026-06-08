# Phase 14.3 – Production Relay UX Polish

## Ziel

Phase 14.3 verbindet die professionelle UI aus Phase 14 mit dem produktiven Relay-Deployment unter:

```text
https://chatsecure.ddns.net
```

Die App unterscheidet deutlicher zwischen Development-/Xcode-Testbetrieb und echter Production-Bewertung.

## Änderungen iOS

- `chatsecure.ddns.net` als SecureChat Production Relay Profil ergänzt.
- Neuer Ein-Klick-Button in `Security > Transport`:
  - Production-URL übernehmen
  - übernehmen und Relay prüfen
- Production Readiness View vollständig überarbeitet:
  - Hero-Statuskarte
  - Production Relay Panel
  - Readiness Snapshot
  - Runtime Integrity Panel
  - Server Hardening Panel
  - Client Security Panel
  - Deployment Commands
- Security Sentinel gruppiert Findings nach:
  - Production-Risiken
  - empfohlene Maßnahmen
  - Development & Info
- Development-/Debug-/Xcode-Signale werden ruhiger dargestellt.
- Dashboard erkennt Production Relay und zeigt `Production Relay` als Status-Pill.
- Relay-Fehlermeldungen nennen nun Production-URL und LAN-Testpfad getrennt.

## Änderungen Relay/Doku

- Caddy-Beispiele auf `chatsecure.ddns.net` aktualisiert.
- Production-Kommandos auf `chatsecure.ddns.net` aktualisiert.
- Keine Änderung am Relay-Protokoll.
- Keine Änderung am Nachrichtenformat.
- Keine Änderung am Crypto-Payload-Format.

## App-Konfiguration

```text
Relay URL:
https://chatsecure.ddns.net

Relay Token:
/opt/securechat/.env → RELAY_AUTH_TOKEN
```

`RELAY_ADMIN_TOKEN` bleibt ausschließlich serverseitig.
