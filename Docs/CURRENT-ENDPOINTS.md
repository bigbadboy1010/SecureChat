# PrivateRoom public endpoints and candidate client contract

Updated 13 October 2026 for the **PrivateRoom 1.5.0 (15)** integration candidate. The new hardened relay/site contract is being evaluated in an isolated canary. This document does not claim that the public deployment has already changed; final cutover and acceptance must be recorded in the [dated review](PRIVATEROOM-REVIEW-2026-10-13.md).

## Canonical public URLs

| Purpose | URL | Expected audience/access |
|---|---|---|
| Product site | `https://securechat.team/` | Public |
| Project status | `https://securechat.team/status.html` | Public, sanitized release information |
| German privacy information | `https://securechat.team/privacy-de.html` | Public |
| English privacy information | `https://securechat.team/privacy.html` | Public |
| Support | `https://securechat.team/support.html` | Public; supported contact `miggu69@gmail.com` |
| Security model | `https://securechat.team/security.html` | Public |
| Known limitations | `https://securechat.team/known-issues.html` | Public |
| Public relay liveness | `https://securechat.team/healthz` | Minimal public liveness; not a security certification |
| Client protocol | `https://securechat.team/v1/relay/*` | Approved device identities using the signed beta contract |

Public documentation must not expose operator environment values, private health routes/credentials, deployment addresses, allowlists, raw logs or recovery material. Internal operational access is a separate private contract.

## Canonical-host owner-beta authentication

The ordinary candidate client uses exactly the public base URL:

```text
https://securechat.team
```

Connecting is an explicit user action. The canonical-host candidate can be configured without a shared bearer token: signed enrollment proves possession of the device's advertised signing key, and subsequent client requests use peer-bound Ed25519 signatures. Access remains subject to the approved owner-beta relay policy. This is not a public open-registration or anonymity promise.

The signature binds the HTTP method, path, canonical query, body hash, timestamp, nonce and public peer identifier. Existing `X-Securechat-*` wire names may remain for compatibility with the technical code name. Peer identifiers and protocol syntax are public-format data; actual production identity lists and private signing keys are not publishable fixtures.

Sender/recipient authorization, bounded timestamp/nonce replay checks and rejection of unsigned or mismatched requests are acceptance requirements for the hardened relay. A successful `/healthz` response alone does not prove that enrollment, SEND, inbox or acknowledgement work correctly or are properly isolated.

## Custom relay rules

A custom relay is an advanced user choice, not an automatic substitution for the canonical host.

- Use a valid public HTTPS base URL with normal platform TLS validation. Release use must not rely on skipped certificate checks.
- Embedded URL credentials, query strings and fragments are rejected by the transport. Insecure production HTTP and literal local/private-host profiles are not supported by the consumer configuration.
- The current profile requires a suitable access token for a noncanonical custom relay. That token is local configuration, never an operator value copied from a public document or an app-bundled secret.
- Saving a custom URL does not implicitly switch a local-only session online. Activating transport is separate and deliberate.
- The other relay must implement the compatible client contract; an arbitrary HTTPS service is not compatible merely because it returns a health response.

Any narrowly scoped loopback fixture used by a debug test is not a production exception and must not be advertised as release behavior. No private LAN addresses belong in this public endpoint list.

## Compatibility and release identity

- Public name: **PrivateRoom**.
- Technical target/scheme and existing source directory: `PrivateChat`.
- Existing bundle: `org.francois.PrivateChat`.
- Integration candidate: **1.5.0 (15)**; final acceptance pending.
- Active message envelope: **protocol 2**, static pairwise agreement; signed contact-code format **3** and fingerprint **SC3** are distinct versions.
- Experimental ratchet code is disabled. A format-version number is not proof of forward secrecy.

Obsolete host/subdomain/LAN configurations must not be copied into new release settings. Any required migration retains private configuration only under the owner-controlled client path and must be tested without publishing real infrastructure addresses.

## Publication gates

Before describing a changed contract as live:

1. Record a preserved rollback path and confirm the isolated candidate's health and authentication behavior.
2. Test signed enrollment, genuine two-identity text/media delivery, inbox ownership and acknowledgements; also test unsigned, forged, replayed and wrong-recipient requests.
3. Confirm the narrowly scoped public switch and unrelated-service continuity.
4. Update this document, website copy and the dated acceptance record with the observed deployed state.
5. Complete physical device and distribution acceptance separately; a public backend change is not an Apple upload.

The public source repository does not contain production deployment secrets. Historical endpoint/runbook descriptions do not supersede this candidate contract or [SECURITY.md](../SECURITY.md).
