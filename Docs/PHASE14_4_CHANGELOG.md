# Phase 14.4 – Relay Migration & Security Cleanup

## Relay-Fix

- `https://chatsecure.ddns.net` ist das verbindliche Production-Relay-Profil.
- Alte lokale Relay-URLs wie `http://192.168.178.229:8080`, `localhost:8080` und `127.0.0.1:8080` werden migriert und für Background-Requests blockiert.
- Auto-Polling, Inbox-Abruf, Outbox-Retry, Stats und Purge starten nur noch, wenn Relay-URL und `RELAY_AUTH_TOKEN` plausibel gesetzt sind.
- 401-Fehler werden als Token-Problem erklärt, nicht mehr als generischer Server-/npm-run-dev-Fehler.
- Settings zeigt Token-Status und bietet `Production Relay aktivieren` sowie `Lokale Relay-Altlast löschen`.

## Code-Review-Fixes

- `LegacyReference/` wurde aus dem Paket entfernt.
- Stale `Tests/schatTests/` wurde entfernt, weil diese Tests nicht das aktive `PrivateChat`-Target geprüft haben.
- `Tests/README.md` dokumentiert die nächste echte Testmigration auf `PrivateChatTests`.
- `PrivacyInfo.xcprivacy` wurde ergänzt.
- README/Security-Doku korrigiert: KDF ist eine Custom Memory-Hard KDF, nicht Argon2id.
- Production-Claims wurden auf `Production Candidate` entschärft, bis ein externer Security-Audit erfolgt.

## Nicht geändert

- Kein neues Relay-Protokoll.
- Kein neues Nachrichtenformat.
- Kein neues Crypto-Payload-Format.
- Server-Tokens bleiben ausschließlich in `/opt/securechat/.env`; die App erhält nur `RELAY_AUTH_TOKEN`.
