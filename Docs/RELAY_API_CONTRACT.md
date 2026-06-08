# PrivateChat Relay API Contract

## Scope

Der Relay ist ein Blind Relay. Er validiert Paketstruktur, Größe und TTL, speichert aber keine Schlüssel und entschlüsselt keine Payload.

## Base URL

```text
http://localhost:8080
```

Produktiv ausschließlich HTTPS verwenden.

## Health

```http
GET /health
```

Response:

```json
{"status":"ok"}
```

## Store packet

```http
POST /v1/relay/messages
Content-Type: application/json
Accept: application/json
```

Request:

```json
{
  "protocolVersion": 2,
  "id": "b4b4bd34-c38d-4a9c-a4f5-6c56644b3d1e",
  "senderID": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "recipientID": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "sealedPayloadBase64": "BASE64_AES_GCM_COMBINED_PAYLOAD",
  "signatureBase64": "BASE64_ED25519_SIGNATURE",
  "createdAt": "2026-06-07T08:23:16Z",
  "expiresAt": "2026-06-08T08:23:16Z"
}
```

Response `202`:

```json
{
  "accepted": true,
  "packetID": "b4b4bd34-c38d-4a9c-a4f5-6c56644b3d1e"
}
```

## Fetch inbox

```http
GET /v1/relay/messages?recipientID=<64-hex-peer-id>&limit=50
Accept: application/json
```

Response:

```json
{
  "packets": []
}
```

## Delete packet

```http
DELETE /v1/relay/messages/:packetID
Accept: application/json
```

Response:

```json
{
  "deleted": true,
  "packetID": "b4b4bd34-c38d-4a9c-a4f5-6c56644b3d1e"
}
```

## Validation

- `senderID` und `recipientID`: 64 Zeichen hex, SHA-256 des Signing Public Keys.
- `sealedPayloadBase64`: AES-GCM combined payload.
- `signatureBase64`: Ed25519 Signature über das kanonische Envelope-Material der App.
- `expiresAt` muss in der Zukunft liegen.
- TTL darf die Serverpolicy nicht überschreiten.
