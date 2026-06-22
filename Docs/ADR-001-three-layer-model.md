# ADR-001: Three-layer model (iOS app, relay, store)

**Status:** Accepted
**Date:** 2026-06-22 (current public-beta release)
**Supersedes:** none

## Context

SecureChat is a privacy-first iOS messenger. The threat model
assumes a network-only adversary, a server-side breach, and a
curious operator. The cryptographic guarantee we are making is:

> The relay, by design, never receives enough information to read
> user messages.

The implementation has to match the threat model at every layer
where the data crosses a boundary, or the claim is false. A
"zero-knowledge relay" that quietly decrypts for analytics, or
stores plaintext to a debug log, is not a zero-knowledge relay.

## Decision

SecureChat has three layers, each with one job:

1. **iOS app.** Owns the Curve25519 identity, the per-message
   symmetric keys, the encrypted local store, the Safety Number
   verification workflow, and the user-facing chat UI. Never talks
   to a server except the configured relay.
2. **Relay (Fastify, Node 22).** Stateless packet dropbox.
   Receives sealed, signed envelopes; persists them for at most
   `MAX_TTL_SECONDS`; delivers on request. Cannot read the
   payload; cannot forge a sender; cannot replay an old packet.
3. **Storage.** File store (`FileRelayStore`) for production,
   in-memory store (`InMemoryRelayStore`) for tests and dev. State
   is opaque envelopes plus acknowledged tombstones; the relay
   has no separate history.

The relay has a deliberately small surface area:

- One well-typed wire format (the `OutboundTransportPacket` schema
  in `RelayServer/src/schemas.ts`).
- One transport (JSON over HTTPS).
- One auth model (Bearer `RELAY_AUTH_TOKEN` for clients, Bearer
  `RELAY_ADMIN_TOKEN` for operators).
- One rate-limit knob (per-IP via `@fastify/rate-limit`).
- One healthcheck shape (`/healthz` for public, `/healthz/internal`
  for operators).

Anything that does not fit one of those — group chat, file
attachments, push notifications, federation — is a future ADR.

## Consequences

- The iOS app is the cryptographic root of trust. If a malicious
  build of the app is installed, all bets are off. This is
  documented in `SECURITY.md` and called out in the iOS app's
  on-device "About this build" sheet.
- The relay cannot be retrofitted into a "real" messaging server
  (group chat, push) without breaking the threat model. Any such
  change requires its own ADR.
- The iOS app's identity is bound to a single device. Multi-device
  sync requires a server-side mailbox and is a future workstream
  (see the `Multi-device sync` entry in `known-issues.html`).
- The relay is a single-process, single-host container. Scaling is
  horizontal (more containers behind a load balancer) once the
  shape of the workload is understood. There is no federation.

## Alternatives considered

- **Peer-to-peer (no relay).** Rejected for v0.1. P2P works
  perfectly for online-and-on-the-same-network cases; it is
  catastrophic for offline and NAT-traversal cases. P2P can be a
  future mode that the iOS app negotiates when both sides are
  reachable, with the relay as the fallback.
- **Federation (XMPP / Matrix-style).** Rejected. Federation
  enables interop but breaks the single-operator threat model and
  introduces metadata-leak surface (server-to-server federation
  headers). Not a fit for v0.1.
- **A single end-to-end app (no separate relay service).** Rejected.
  We want a self-hostable relay, and we want a $5/month VPS to be
  a real deployment target. A monolithic iOS app that does its own
  relay work would not be self-hostable.
