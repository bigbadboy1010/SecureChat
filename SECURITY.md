# Security Policy

SecureChat is end-to-end encrypted, but software has bugs. We take
reports seriously. Mailboxes and public endpoints referenced in this
file are kept in sync with
[`docs/CURRENT-ENDPOINTS.md`](docs/CURRENT-ENDPOINTS.md) — that file
is the single source of truth for `security@securechat.team`, the
public healthcheck, and the distribution channels.

## Threat model in one paragraph

The relay is designed so that a successful subpoena, a server-side
breach, or a curious operator is structurally incapable of reading
user messages. The iOS app is the cryptographic root of trust: if a
malicious build of the app is installed, all bets are off. The signed
envelopes and replay protection are independent of the TLS transport;
even a successful MITM cannot forge a sender. See
[`docs/architecture.html`](https://securechat.team/docs/architecture.html)
for the long form.

## Supported versions

The SecureChat project ships two independently versioned artefacts.

### iOS app (TestFlight, bundle id `org.francois.securechat`)

Distributed via [TestFlight](https://testflight.apple.com/join/TEWAWfVb).

| Version          | Supported                |
| ---------------- | ------------------------ |
| v0.1.x          | ✅ Active (current beta) |
| < v0.1           | ❌ End of life           |

### Relay server (`securechat-relay`)

Hosted at `https://relay.securechat.team/`. Source-available; the
on-host deployment is patched in place. The reported build identifier
is the canonical version string (e.g. `v0.1.0+<git-sha>` shown by
`/healthz`).

| Build        | Supported                |
| ------------ | ------------------------ |
| v0.1.x       | ✅ Active (current)      |
| v0.0.x       | ❌ Decommissioned        |

## Reporting a vulnerability

**Please email `security@securechat.team`** rather than filing a
public GitHub issue. Include:

- A description of the vulnerability and its impact.
- Steps to reproduce, ideally with a minimal PoC.
- The relay or iOS app version, the iOS version, and any relevant
  configuration.
- Whether you intend to file a CVE.

### PGP key for `security@securechat.team`

> **Status (2026-06-23, Sprint 14): PGP key generation is in the
> post-1.0 backlog.** The PGP key generation is tracked in the
> open follow-up list; the canonical entry point for the
> `security@securechat.team` mailbox is the
> [Postfix / Mailcow box on the SecureChat server](https://securechat.team/docs/self-host.html)
> which is the only target we monitor for vulnerability reports.
>
> Until the PGP key is generated, please send vulnerability reports
> in clear text. Once the key is generated it will be:
>
> 1. Committed to this repository at
>    `Docs/SECURITY-PGP-KEY.asc` (history in git, no fake placeholder
>    block).
> 2. Published to the public keyserver pool so reporters can verify
>    the fingerprint via the long-form URI.
> 3. Rotated on the same schedule as the relay auth tokens
>    (every 12 months; the rotation is announced on the
>    [status page](https://securechat.team/status.html) and the
>    repo's commit log).
>
> This section is intentionally **honest** rather than a fake
> placeholder key. Do not paste a placeholder here under any
> circumstances.

For sensitive reports, also include the following with your report:

- A throwaway reply-to address (Signal, ProtonMail, or a fresh
  mailbox you control).
- A short "encrypted reply request" so we know whether to send
  the response encrypted (we will set up PGP for the reply if you
  include your public key in the report).

If you would rather use the same key in OpenSSL or another tool, the
ASCII-armoured block above is the canonical export. To verify a
signature on a release artifact, run:

```bash
gpg --verify <signature> <artifact>
```

We aim to:

- Acknowledge new reports within 72 hours.
- Provide a triage verdict (accepted / duplicate / not applicable)
  within 7 days.
- Ship a fix or a documented mitigation within 30 days for issues
  rated High or Critical, 90 days for Medium, and at the next
  regular release for Low.

## Out-of-scope

- Attacks that require physical access to a device that is already
  unlocked.
- UI / UX issues that do not enable a confidentiality, integrity,
  or availability breach.
- Best-practice recommendations that do not enable a concrete
  attack (e.g. "you should add a CSP header" on a page that does not
  load third-party scripts).
- The relay's `InMemoryRelayStore` is **not** for production; the
  file store is the only supported production store. The in-memory
  store is retained for tests and the dev environment.
- The current public beta is **not** audited. High-assurance
  deployments should wait for an external security audit (see the
  <a href="https://securechat.team/known-issues.html">known-issues</a>
  page).

## Security advisories

Security advisories are published as GitHub Security Advisories
on the repository's Security tab. Each advisory has a CVE id (where
one has been assigned) and a fixed-in version. Subscribe to the
repository to be notified of new advisories.

## Acknowledgements

We thank the following researchers for responsible disclosures (in
the order they were received):

_(none yet — first public beta is the public-beta release, June 2026)_
