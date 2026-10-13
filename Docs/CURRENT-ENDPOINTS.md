# PrivateRoom public endpoints and owner-beta client contract

Updated 13 October 2026 for the **PrivateRoom 1.5.0 (15)** integration candidate. The hardened approved-owner-beta relay and redesigned project site went live at **12:00:14 UTC**. Eleven public HTTPS routes passed acceptance and all 15 static source files matched their served bytes. Client simulator and unsigned device-target Release checks passed; physical owner-device and native GUI acceptance remain pending. See the [dated review](PRIVATEROOM-REVIEW-2026-10-13.md) for the exact verification boundaries. A live backend is not an Apple release.

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

Connecting is an explicit user action. The canonical-host candidate uses no consumer or operator bearer token: signed enrollment proves possession of the device's advertised signing key, and subsequent client requests use peer-bound Ed25519 signatures. The deployed relay requires approved owner-beta identities and rejects unsigned or mismatched client requests. This is not a public open-registration or anonymity promise.

The signature binds the HTTP method, path, canonical query, body hash, timestamp, nonce and public peer identifier. Existing `X-Securechat-*` wire names may remain for compatibility with the technical code name. Peer identifiers and protocol syntax are public-format data; actual production identity lists and private signing keys are not publishable fixtures.

Sender/recipient authorization, bounded timestamp/nonce replay checks and rejection of unsigned or mismatched requests passed the isolated contract checks and 26 backend regressions. Actual Swift signed enrollment, text/media transfer, inbox reads and acknowledgements passed against the exact deployed contract in isolation. A successful `/healthz` response alone does not prove those properties, and these fixture checks do not establish physical two-device acceptance.

New routine backups exclude live queues, acknowledgement tombstones and nonce state. Historical encrypted backup/recovery copies remain and are outside immediate deletion. The shared reverse proxy's global error logging may retain network or routing metadata; the deployment does not promise metadata-free operation.

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
- Integration candidate: **1.5.0 (15)**; final 141-test simulator run and unsigned device-target Release build passed. Physical owner-device and native GUI acceptance remain pending.
- Active message envelope: **protocol 2**, static pairwise agreement; signed contact-code format **3** and fingerprint **SC3** are distinct versions.
- Experimental ratchet code is disabled. A format-version number is not proof of forward secrecy.

Obsolete host/subdomain/LAN configurations must not be copied into new release settings. Any required migration retains private configuration only under the owner-controlled client path and must be tested without publishing real infrastructure addresses.

## Deployment acceptance and remaining distribution checks

The controlled public switch completed with a verified rollback/recovery path. The 89 pre-existing containers retained their identities, start times and restart counts; central server process IDs were unchanged. Recovery copies were verified on the owner's Mac and separate backup server.

The isolated Swift wire fixture transferred a full 8 MiB attachment in 128 × 64 KiB chunks, reassembled its SHA-256 digest and completed acknowledgements. Sender and receiver ran serially with 0.65-second request pacing against the same 120-request-per-minute IP budget. This proves the tested contract; it does not claim that simultaneously competing traffic or real phones have passed acceptance.

Physical owner-device and native GUI acceptance, physical iOS Data Protection verification, distribution acceptance and independent audit remain separate outstanding checks. No Apple upload, TestFlight release or App Store submission has been performed for this candidate.

The public source repository does not contain production deployment secrets. Historical endpoint/runbook descriptions do not supersede this observed owner-beta contract or [SECURITY.md](../SECURITY.md).
