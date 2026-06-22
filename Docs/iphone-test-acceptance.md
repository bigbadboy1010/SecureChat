# iPhone TestFlight acceptance — SecureChat

A repeatable end-to-end test that any beta tester can run on their iPhone
to confirm the SecureChat public relay is reachable, that the iOS app
can complete a handshake, and that a round-trip sealed message is
delivered.

> **Last verified:** 2026-06-22. The numbers in the output snippets below
> will change with each test run; the *shape* of the output is the
> canonical pass/fail signal.

---

## Prerequisites

- iPhone or iPad running iOS 16 or newer.
- The current TestFlight build of `LoupeControllerApp` /
  `SecureChat`. Invite link:
  [testflight.apple.com/join/wsJeRw1M](https://testflight.apple.com/join/wsJeRw1M).
  (Replace the bundle-id once the iOS app is renamed to SecureChat in
  the TestFlight listing — the link stays the same.)
- A second device (a friend's phone, a Mac running the iOS Simulator,
  a `curl`-against-the-relay script) that you can send a message to.

## Session id

The default session is:

```
loupe-beta-session
```

(Renamed from `loupe-dev-session` in sprint 12. The session id is
shared by both peers; pick a unique one if you want to avoid
collision with a sibling test.)

## Public endpoints

| Purpose | URL |
| --- | --- |
| Relay | `https://relay.securechat.team/v1/relay/*` |
| Healthcheck | `https://securechat.team/healthz` |
| Status | `https://securechat.team/status.html` |

The canonical source for endpoints is
[`docs/CURRENT-ENDPOINTS.md`](CURRENT-ENDPOINTS.md).

## Step 1 — confirm the relay is up

Open a terminal and run:

```bash
curl -s https://securechat.team/healthz
# {"status":"ok","uptimeSeconds":42,"version":"v0.1.0+<git-sha>"}
```

If you get a non-200, or a response that does not have those three
fields, the test is blocked. Check
[status.html](https://securechat.team/status.html) for any active
incident.

## Step 2 — open the iOS app

Open SecureChat from the home screen. On first launch it generates a
Curve25519 keypair. You should see:

- A `Safety Number` screen with a 60-digit fingerprint.
- A `+` button to add a peer.

The Curve25519 private key is stored in the iOS Keychain with the
`ThisDeviceOnly` attribute — it never leaves the device.

## Step 3 — exchange identity fingerprints with a peer

Out-of-band: tell the peer your 60-digit fingerprint, and ask for
theirs. Verify on the phone. The app will mark the peer as
**verified** once both sides confirm.

This step is the moment where your device and the peer's device
decide that they trust each other. The signed-envelope guarantee
above is independent of this verification, but the verification is
the only way to defend against a key-substitution attack at the
relay.

## Step 4 — send a sealed message

In the app, open the conversation with the verified peer, type a
message, hit send. The app:

1. Generates a per-message symmetric key.
2. Encrypts the message body with AES-GCM.
3. Seals the symmetric key to the peer's Curve25519 public key.
4. Signs the whole envelope with your Ed25519 signing key.
5. POSTs the envelope to the relay at
   `https://relay.securechat.team/v1/relay/messages`.

The relay accepts the envelope, returns a 202 with a `packetID`, and
the envelope sits in the relay's file store.

## Step 5 — receive the message on the peer

The peer's app polls the relay at
`https://relay.securechat.team/v1/relay/messages?recipientID=...`,
fetches the envelope, opens it with the peer's private key, and
displays the plaintext. The peer then POSTs an ack to
`/v1/relay/messages/:packetID/ack`, and the relay deletes the
envelope.

## Step 6 — verify with curl (optional)

If you have a partner who is willing to run a `curl` script for you,
the relay's contract is reproducible from outside the app:

```bash
# Drop a synthetic sealed payload (sender -> recipient, sealed + signed
# per the schemas in RelayServer/src/schemas.ts)
curl -i \
  -H "Authorization: Bearer $RELAY_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  https://relay.securechat.team/v1/relay/messages \
  -d '{
    "protocolVersion": 2,
    "id": "11111111-2222-4333-8444-555555555555",
    "senderID": "<your 64-hex peer id>",
    "recipientID": "<peer's 64-hex peer id>",
    "sealedPayloadBase64": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==",
    "signatureBase64": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==",
    "createdAt": "2026-06-22T12:00:00+00:00",
    "expiresAt": "2026-06-22T13:00:00+00:00"
  }'
```

(Use the iOS app's *Export peer id* and *Export signed envelope*
features — to be added in a future sprint — to obtain the values
without reimplementing the envelope shape.)

## Pass / fail criteria

The test passes if:

1. `GET /healthz` returns a 200 with `{status, uptimeSeconds, version}`.
2. The iOS app generates a Curve25519 keypair and displays a fingerprint.
3. A message sent from device A appears on device B within 30 seconds
   (network permitting).
4. The relay returns a 202 with a `packetID` on send, and a 200 on
   fetch.
5. The acknowledged packet disappears from the relay's storage
   within one second of the peer acking it.
6. After both peers verify each other's Safety Numbers, the chat
   shows a green verified tick on both devices.

The test fails if:

- The relay returns a 5xx at any point.
- The app crashes on send or receive.
- The Safety Number fingerprint does not match the value reported on
  the other device.
- A message sent in plaintext can be intercepted (it should be
  impossible; the relay cannot see the body).
