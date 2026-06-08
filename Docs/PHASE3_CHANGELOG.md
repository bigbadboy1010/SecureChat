# PrivateChat Phase 3 Changelog

## Ziel

Phase 3 stabilisiert den Relay-Betrieb nach dem erfolgreichen iPhone-Test. `POST` und `GET` liefen bereits, aber das Acknowledge/Delete alter Relay-Pakete konnte mit HTTP 500 fehlschlagen. Außerdem wurde die manuelle Inbox-Bedienung durch Auto-Polling und Outbox-Retry erweitert.

## iOS App

- Auto-Polling für Relay-Inbox nach dem Entsperren der App.
- Konfigurierbares Auto-Polling-Intervall: 5 bis 300 Sekunden.
- Automatischer Retry für fehlgeschlagene Outbox-Nachrichten.
- Manueller Button „Outbox erneut senden“.
- Outbox-Zähler in Security > Transport.
- Neue Zustände für Nachrichten:
  - `queued`
  - `sending`
  - `sentToRelay`
  - `sent`
  - `delivered`
  - `failed`
- Beim App-Start werden abgebrochene `sending`-Nachrichten wieder auf `queued` gesetzt.
- Relay-Sync zeigt ACK-Fehler separat an.
- Lokale Notiz-Chats werden ohne Netzwerktransport als `delivered` markiert.

## Relay Server

- Neuer idempotenter ACK-Endpunkt:

```http
POST /v1/relay/messages/:packetID/ack
```

- Bestehender Legacy-Endpunkt bleibt erhalten:

```http
DELETE /v1/relay/messages/:packetID
```

- Wiederholte ACKs sind kein Fehler mehr. Wenn ein Paket bereits gelöscht wurde, antwortet der Server mit:

```json
{"deleted":false,"packetID":"..."}
```

- Fehlerantworten enthalten nun eine `requestID`.
- Im Development-Modus enthält HTTP 500 zusätzlich ein nicht-sensitives `detail`-Feld.

## Test

TypeScript-Check:

```bash
cd RelayServer
npm install
npm run typecheck
```

Smoke-Test durchgeführt:

- `GET /health` -> 200
- `POST /v1/relay/messages` -> 202
- `GET /v1/relay/messages` -> 200
- `POST /v1/relay/messages/:packetID/ack` -> 200
- wiederholtes ACK -> 200 mit `deleted:false`
- Legacy DELETE -> 200 mit `deleted:false`
