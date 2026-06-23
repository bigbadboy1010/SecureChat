# SecureChat Relay API Contract v0.1 (2026-06-23)

> **Sprint 14E: full rewrite.** The previous
> `PrivateChat Relay API Contract` was
> significantly behind the live relay and the
> `CURRENT-ENDPOINTS.md` source of truth. This
> document is now the canonical public contract
> for the `relay.securechat.team` surface.

This contract covers the **public** relay
surface served by `https://relay.securechat.team`
behind a Caddy TLS terminator. The single source
of truth for endpoint names, host names, and
auth requirements is
[`Docs/CURRENT-ENDPOINTS.md`](CURRENT-ENDPOINTS.md).
This document drills into request / response
shape, error schema, and replay / TTL semantics.

If you are integrating against this contract,
**read `CURRENT-ENDPOINTS.md` first**, then come
back here for the wire-format details.

---

## 1. Base URLs

| Surface      | URL                                          |
| ------------ | -------------------------------------------- |
| Public prod  | `https://relay.securechat.team`              |
| Public prod  | `https://securechat.team/v2-stats.html`      |
| Local dev    | `http://localhost:8080` (only in Debug)      |

HTTPS is mandatory in any non-development build.
The iOS `RelayTransport` enforces this and
throws `insecureRelayURL` for plain-HTTP bases
in TestFlight / Release (Sprint 14C).

---

## 2. Auth layers

The relay stacks three independent auth layers.
Each request may exercise one, two, or all
three, depending on the surface.

### 2.1 Bearer-token abuse gate

A long-lived `RELAY_AUTH_TOKEN` (alias
`RELAY_CLIENT_TOKEN`) is configured via the
relay's environment. Every request to
`/v1/relay/*` must carry it as:

```text
Authorization: Bearer $RELAY_AUTH_TOKEN
```

The relay blocks placeholder values
(`change-this`, `example`, `placeholder`,
`client-token`, `admin-token`, ...) in
production, requires the token to be at least
32 characters, and refuses to start in
production if the token is missing or matches
a placeholder.

### 2.2 Peer-bound request signing (Sprint 14
in progress, opt-in)

Once the iOS `RelayTransport` ships the
peer-bound signing code, every request will
additionally carry:

```text
X-Securechat-Peer-ID:    <hex-encoded Curve25519 public peer ID>
X-Securechat-Timestamp:  <unix epoch seconds, integer>
X-Securechat-Nonce:      <32 random bytes, hex>
X-Securechat-Signature:  <hex-encoded Ed25519 signature>
```

The signature is computed over a canonical
string (see §6) and is verified by the relay
using the `PeerRegistry` (which is built from
the `/v1/relay/peers` enrollment endpoint).
See [`Docs/ADR-005-peer-bound-relay-auth.md`](ADR-005-peer-bound-relay-auth.md)
for the migration plan.

### 2.3 Operator / admin tokens

* `X-Securechat-Ops-Token: $OPS_TOKEN` for
  `/healthz/internal` and the
  `isPublicRelaySubRoute = false` operators
  surface. The env alias `WAITLIST_ADMIN_TOKEN`
  is accepted for backwards compatibility.
* `Authorization: Bearer $RELAY_ADMIN_TOKEN`
  for `/v1/admin/*` (per-peer counters, purge).

---

## 3. Public endpoints

### 3.1 `GET /healthz`

```http
GET /healthz HTTP/1.1
Host: relay.securechat.team
```

Response (200):

```json
{"status":"ok","uptimeSeconds":42,"version":"v0.1.0+<git-sha>"}
```

Three fields, no auth, no operational knobs.
Replaces the old `/health` operator-only
endpoint as the public healthcheck (Sprint 1.1
+ Sprint 14A).

### 3.2 `GET /v1/relay/security/policy`

```http
GET /v1/relay/security/policy HTTP/1.1
```

Response (200) shows the current posture
(auth-required, https-required, max packet
bytes, max TTL, max clock skew, max total
packets, max packets per recipient,
clientPurgeEnabled). No auth.

### 3.3 `GET /v1/relay/stats`

```http
GET /v1/relay/stats HTTP/1.1
```

Response (200):

```json
{
  "storedPackets": 0,
  "activeRecipients": 0,
  "acknowledgedPacketTombstones": 0,
  "v1EnvelopeRequests": 0,
  "v2EnvelopeRequests": 0,
  "firstV2RequestAt": null,
  "lastV2RequestAt": null
}
```

`firstV2RequestAt` and `lastV2RequestAt` are
ISO-8601 UTC strings, `null` until the first
v2 envelope request has been observed. The
counter reset semantics are
**per-relay-process** (the counters are
in-memory, not persistent). Optional for
backwards compatibility with pre-Sprint-12
relay builds.

No auth. No peer IDs, no payloads, no
correlatable traffic data.

### 3.4 `GET /v1/relay/v2-health` (Sprint 12)

```http
GET /v1/relay/v2-health HTTP/1.1
```

Optional `?freshWindow=N` query parameter
(default 86400 = 1 day).

Response (200):

```json
{
  "ready": false,
  "v2EnvelopeRequests": 0,
  "v1EnvelopeRequests": 0,
  "totalEnvelopeRequests": 0,
  "v2SharePercent": 0,
  "firstV2RequestAt": null,
  "lastV2RequestAt": null,
  "lastV2RequestAgeSeconds": null,
  "warnings": ["no v2 envelope requests observed yet"]
}
```

`warnings` is a synthesized array of advisory
strings. The current heuristics are:

* `"no v2 envelope requests observed yet"` when
  `v2EnvelopeRequests === 0`.
* `"no v2 envelope requests in the last Ns"`
  when the last v2 request is older than
  `?freshWindow=N`.
* `"v2 share is X% (below 1% threshold)"` when
  at least one envelope request has been
  observed but the v2 share is below 1%.

The endpoint is wired into the
`isPublicRelaySubRoute` allowlist in
`src/routes.ts` so no auth header is required.

---

## 4. Client endpoints

All endpoints under `/v1/relay/messages*` and
`/v1/relay/peers` require the bearer-token
abuse gate (§2.1). The peer-bound signing
layer (§2.2) is the canonical authorization
for `POST` / `GET` / `DELETE` and is being
rolled out as part of the Sprint 14 release
track.

### 4.1 `POST /v1/relay/peers`

Enroll a new peer. The request body carries
the peer's public key bundle (Ed25519 signing
+ Curve25519 key agreement, base64) and a
human-readable display name. The response
returns the assigned `peerID`. Rate-limited
per source IP.

### 4.2 `POST /v1/relay/messages`

Store a single encrypted packet. Body is a
JSON `OutboundTransportPacket` (protocol
version 2 = v1 envelope, 3 = v2 envelope, see
[`ADR-002`](ADR-002-envelope-and-crypto.md)
and [`ADR-006`](ADR-006-double-ratchet.md)).
The relay validates packet structure, size,
TTL, and policy. Returns 202 with the
assigned `packetID`; duplicate sends return
the original `packetID` (idempotent within
the TTL window).

### 4.3 `GET /v1/relay/messages?recipientID=...`

Fetch the inbox for the calling peer. Query
parameter `recipientID` must match the
authenticated peer (the relay's own peer
registry enforces this once peer-bound
signing is enabled; in legacy unsigned mode
the query parameter alone is accepted).
Response body lists `OutboundTransportPacket`
records. The caller should `DELETE` each
packet after a successful send, to drop the
tombstone.

### 4.4 `DELETE /v1/relay/messages/:id`

Delete a single packet by ID. Requires the
authenticated peer to be the recipient.

### 4.5 `POST /v1/relay/messages/:id/ack`

Mark a packet as acknowledged. Requires the
authenticated peer to be the recipient. The
relay writes a tombstone and removes the
packet on the next cleanup pass.

---

## 5. Admin endpoints

### 5.1 `GET /v1/admin/relay/stats`

Same shape as `/v1/relay/stats` (Sprint 12),
plus per-peer counters and last-seen
timestamps. Requires
`Authorization: Bearer $RELAY_ADMIN_TOKEN`.

### 5.2 `POST /v1/admin/relay/purge`

Purge all packets for a `recipientID`. Requires
admin token. Body: `{recipientID: string}`.

### 5.3 `GET /healthz/internal`

Operator-only healthcheck (store type, max
packet bytes, max TTL, max clock skew,
max total packets, max packets per recipient,
client purge enabled, max clock skew seconds,
auth required, admin auth required,
production mode, https required). Requires
`X-Securechat-Ops-Token: $OPS_TOKEN`.

---

## 6. Canonical string (peer-bound signing)

When peer-bound signing is enabled
(Sprint 14 forward), every signed request
builds the signature input from the canonical
string:

```text
<HTTP-METHOD>\n
<request-path>\n
<query-string-canonicalized>\n
<body-sha256-hex>\n
<X-Securechat-Timestamp>\n
<X-Securechat-Nonce>\n
<X-Securechat-Peer-ID>
```

The signature is the Ed25519 signature over
this string, using the peer's long-term
signing private key. The relay verifies the
signature against the registered peer
public key, checks that the timestamp is
within the allowed clock-skew window, and
checks that the nonce has not been seen
within the nonce-cache TTL (default 10 min).

The peer-bound request signing is **opt-in
in development** (the relay accepts unsigned
requests and only counts them in the
`unsignedRequests` counter); in production
the `RELAY_REQUIRE_PEER_AUTH=true` flag
enforces signing on every client request.

---

## 7. Error schema

All errors are returned as a JSON body of
the form:

```json
{
  "error": "human-readable error code",
  "message": "operator-friendly description",
  "requestID": "<uuid>"
}
```

Common error codes:

| HTTP | `error`                    | When                                              |
| ---- | -------------------------- | ------------------------------------------------- |
| 400  | `invalid_packet`           | Body fails zod schema validation.                 |
| 400  | `clock_skew`               | Timestamp outside ±`maxClockSkewSeconds`.         |
| 401  | `unauthorized`             | Bearer token missing / wrong / placeholder.       |
| 401  | `unsigned_request_required`| `RELAY_REQUIRE_PEER_AUTH=true` and no signature.  |
| 403  | `invalid_signature`        | Peer signature does not verify.                   |
| 404  | `not_found`                | Unknown peer / packet / endpoint.                 |
| 413  | `packet_too_large`         | Packet exceeds `maxPacketBytes`.                   |
| 429  | `rate_limited`             | Per-IP or per-peer rate limit exceeded.            |
| 503  | `store_full`               | Relay queue at capacity.                           |

---

## 8. Replay / TTL semantics

* `createdAt` is set by the iOS app at send
  time.
* `expiresAt = createdAt + 24h` (default
  `MAX_TTL_SECONDS=86400`).
* Packets whose `expiresAt` is in the past at
  arrival are rejected with `400 invalid_packet`.
* Packets whose `expiresAt` is in the past at
  *any* later cleanup pass are removed.
* ACK tombstones live for `ACK_TOMBSTONE_TTL`
  (default 5 min) so that duplicate `POST` /
  `GET` calls within that window are
  idempotent.

---

## 9. Deprecation of unsigned mode

The relay currently accepts unsigned client
requests for backwards compatibility with
pre-Sprint-14 iOS builds. The migration plan
in [`ADR-005`](ADR-005-peer-bound-relay-auth.md)
defines the rollout:

1. **Sprint 14 (current):** unsigned requests
   are still accepted. The relay counts signed
   vs. unsigned traffic. The iOS
   `RelayTransport` is being updated to send
   peer-bound headers.
2. **Sprint 15 (planned):** opt-in
   `RELAY_REQUIRE_PEER_AUTH=true` per relay
   deployment. The iOS app will refuse to send
   to a relay that requires peer-bound signing
   unless the user has completed a fresh
   pairing (which seeds the necessary
   long-term signing key).
3. **Sprint 16 (planned):** default
   `RELAY_REQUIRE_PEER_AUTH=true` for the
   public production relay. Pre-Sprint-14 iOS
   builds will start receiving `401
   unsigned_request_required`. Users will need
   to install the latest TestFlight build to
   keep the inbox working.

---

## 10. Self-host

The same contract applies to a self-hosted
relay. Replace the host name with your own
and supply the env vars from the
[Self-host guide](docs/self-host.html). The
iOS app picks up the host via
`RELAY_BASE_URL` (and `RELAY_AUTH_TOKEN`) and
points the same client endpoints at your host.
