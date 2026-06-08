# PrivateChat Phase 4 Changelog

## Ziel

Phase 4 stabilisiert die Relay-Synchronisation nach dem erfolgreichen ACK-Fix und erweitert das Protokoll um Delivery-Receipts, damit aus `sentToRelay` echte `delivered`-Status werden können.

## iOS

- Transport-Payload auf Version 3 erweitert.
- Neue Payload-Kinds:
  - `message`
  - `deliveryReceipt`
- Empfangene Nachrichten erzeugen automatisch ein verschlüsseltes Delivery-Receipt an den Sender.
- Eingehende Delivery-Receipts markieren die ursprüngliche ausgehende Nachricht als `delivered`.
- Persistentes Relay-Paket-Ledger in der Keychain:
  - bekannte Paket-IDs
  - ACK-Zähler
  - Duplikat-Erkennung
  - letzte ACK-Zeit
- Relay-Sync-Summary erweitert:
  - verarbeitet
  - Duplikate
  - verworfen
  - bestätigt
  - Delivery-Receipts
  - ACK-/Receipt-Fehler
- Pairwise-Key-Kontext für Nutzdaten auf `PrivateChat/pairwise-message/v3/...` erhöht.

## Relay Server

- ACK-Tombstones eingeführt.
- Bereits bestätigte Paket-IDs werden nicht erneut ausgeliefert.
- ACK/DELETE bleibt hart idempotent.
- Neuer Diagnose-Endpunkt:
  - `GET /v1/relay/stats`
- Neuer Admin-/Test-Endpunkt:
  - `POST /v1/relay/messages/purge`
- Relay-Store räumt stale packet IDs beim Listen auf.

## Teststatus

- TypeScript `npm run typecheck`: erfolgreich.
- Relay smoke test erfolgreich:
  - `/health`
  - `/v1/relay/stats`
  - `POST /v1/relay/messages`
  - `GET /v1/relay/messages`
  - `POST /v1/relay/messages/:packetID/ack`
  - erneutes `GET` liefert bestätigte Pakete nicht mehr aus.

## Hinweise

- Für Phase 4 müssen App und RelayServer gemeinsam ersetzt werden.
- Alte Relay-Pakete aus Phase 2/3 können verworfen und ACK-bestätigt werden, weil Payload v3 erzwungen wird.
- `delivered` bedeutet: Empfängergerät hat die Nachricht entschlüsselt und ein Delivery-Receipt an den Relay gesendet. Es bedeutet noch nicht `read`.
