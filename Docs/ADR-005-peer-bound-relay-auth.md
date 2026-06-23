# ADR-005: Peer-bound Relay Auth

## Status

Accepted (Sprint 7, 2026-06-22)

## Context

The current relay authorization model (Sprint 1) uses a single
global `RELAY_AUTH_TOKEN` as a Bearer token for every client
request. This is fine as an **abuse gate** but it is not an
**identity** or **authorization** model: every client that
possesses the token can

- poll any `recipientID`'s inbox,
- acknowledge any known `packetID` (including for inboxes that
  are not their own),
- delete any packet they can name,
- post messages claiming any `senderID` they want.

End-to-end encryption still protects message **content** — the
relay cannot read plaintext. But the relay cannot enforce
**availability** or **metadata access** controls, and a leaked
client token gives one adversary access to every inbox that
client can name.

The previous reviewer report (Sprint 5) named this as the
biggest remaining P1 finding: "the relay's authorization is too
coarse to be a robust identity model."

## Decision

We add a **peer-bound request-signing layer** on top of the
existing bearer-token gate. The bearer token is kept (and
required) as the abuse gate; the signature layer is what tells
the relay which peer is actually making the request.

### Headers

```http
Authorization:        Bearer <RELAY_AUTH_TOKEN>          # global abuse-gate
X-Securechat-Peer-ID: <sender-public-key-fingerprint>   # who is signing
X-Securechat-Timestamp: <RFC3339>                        # ±5 min clock-skew
X-Securechat-Nonce:    <base64url(16 random bytes)>      # replay-cache 10 min
X-Securechat-Signature: <base64url(ed25519 sig)>         # over canonical string
```

### Canonical string

The signature is computed over a canonical string that covers
the entire request surface, so a replayed request cannot be
re-targeted at a different endpoint, body, or peer:

```
<METHOD>\n
<PATH>\n
<CANONICAL_QUERY>\n
<SHA256_HEX(body)>\n
<TIMESTAMP>\n
<NONCE>\n
<PEER_ID>
```

`CANONICAL_QUERY` is the query string with parameters sorted
lexicographically by key. If there is no query, the line is the
empty string.

### Peer registry

The relay keeps a server-side **peer registry** that maps
`X-Securechat-Peer-ID` (a SHA-256 of the peer's Ed25519 public
key, 32 hex chars) to the peer's registered Ed25519 public
key. The registry is populated by:

1. **Pairing bootstrap:** when a new peer enrolls through the
   iOS app's pairing flow, the app registers its public key
   with the relay by submitting a signed enrollment packet
   to `POST /v1/relay/peers`.
2. **Self-hosted relays:** the operator seeds the registry
   from a `peers.json` file at startup.

The registry never holds private keys, message bodies, or any
identifying information beyond the public key and a
`registeredAt` timestamp. Peers can rotate their public key by
submitting a new enrollment packet signed by their **old** key
(the relay requires a `prevPeerID` field for rotation).

### Recipient-bound operations

Once a request is signed and verified, the relay checks that
the operation is bound to the signer:

| Endpoint            | Signer must be ...                | Otherwise                    |
|---------------------|-----------------------------------|------------------------------|
| `POST /messages`    | the `senderID` of the packet      | 403 `signer_not_sender`     |
| `GET  /inbox`       | the `recipientID` of the inbox    | 403 `signer_not_recipient`  |
| `POST /messages/ack`| the `recipientID` of the packet   | 403 `signer_not_recipient`  |
| `DELETE /messages`  | the `recipientID` of the packet   | 403 `signer_not_recipient`  |

`/`/v1/admin/*` remains bearer-only (operator surface); the
peer-signing layer is for client traffic only.

### Replay protection

Nonces are kept in an in-memory LRU cache with a 10-minute TTL
and a 100 000-entry cap. The cap is the safety valve; in
practice the 10-minute TTL is what bounds the cache size in a
healthy deployment. The cache is rebuilt on restart — that is
acceptable because the timestamp window is ±5 minutes, so a
restart closes the window within minutes anyway.

### Backwards compatibility

The peer-bound layer is **opt-in per request** in Sprint 7.
Requests that do not carry the four new headers continue to
work as long as the bearer token is valid. The deprecation
timeline:

- **Sprint 7 (now):** peer-bound auth is accepted everywhere
  it is sent. The relay emits a `deprecation` notice in
  `/healthz/internal` that includes the percentage of
  client requests that arrived without the new headers.
- **Sprint 8:** the relay starts logging a warning per
  un-signed client request. A configuration flag
  `RELAY_REQUIRE_PEER_AUTH=1` is added to make the warning
  into a hard 401.
- **Sprint 9:** the flag is enabled by default in production
  (`RELAY_REQUIRE_PEER_AUTH=1` is the default for
  `NODE_ENV=production`).
- **Sprint 10+:** the un-signed code path is removed; only
  peer-bound requests are accepted.

## Consequences

- The relay's authorization model is now **two-factor**:
  bearer token (abuse gate) + signed request (identity +
  intent + freshness). Either alone is insufficient.
- The relay can now enforce **availability** and
  **metadata access** controls, not just message-confidentiality
  controls.
- The iOS app's `RelayTransport` (currently in
  `PrivateChat/Core/Transport/RelayTransport.swift`) needs to
  be updated to compute the canonical string, sign it, and
  attach the four new headers on every request. This is the
  bulk of the Sprint 7 iOS work.
- A new endpoint `POST /v1/relay/peers` enrolls new peers; the
  existing pairing flow becomes a thin wrapper around it.
- The threat model in `Docs/SECURITY_ROADMAP.md` is updated
  to reflect that metadata-protection and inbox-confidentiality
  now have relay-enforced controls.

## References

- `PrivateChat/Core/Transport/RelayTransport.swift` — updated
  to compute canonical string + sign
- `RelayServer/src/peerAuth.ts` — new module (canonical string,
  signature verification, replay cache)
- `RelayServer/src/routes.ts` — updated to gate every client
  route on the peer-bound layer
- `RelayServer/src/store.ts` — peer registry added
- `Docs/THREAT_MODEL.md` — updated with the new trust model
