# SecureChat Relay Server

Minimaler Relay für PrivateChat. Der Server speichert und leitet ausschließlich bereits clientseitig verschlüsselte und signierte Pakete weiter. Er kennt keine Klartextnachrichten und keine Schlüssel.

## Start

```bash
npm install
npm run dev
```

Standard:

```text
http://0.0.0.0:8080
```

## Health

```bash
curl http://localhost:8080/health
```

Erwartet:

```json
{"status":"ok"}
```

## Endpoints

### Nachricht ablegen

```http
POST /v1/relay/messages
```

### Inbox abrufen

```http
GET /v1/relay/messages?recipientID=<64-hex-peer-id>&limit=50
```

### Paket bestätigen

```http
POST /v1/relay/messages/:packetID/ack
```

ACK ist idempotent. Ein bereits gelöschtes Paket erzeugt keinen Fehler.

### Legacy Delete

```http
DELETE /v1/relay/messages/:packetID
```

Bleibt für ältere Clients erhalten.

## Production-Hinweise

Für produktiven Betrieb fehlen noch persistenter Store, TLS-Termination, Auth-/Abuse-Limits pro Identity, Monitoring und saubere Retention-Policies.
