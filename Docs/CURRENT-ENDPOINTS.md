# CURRENT-ENDPOINTS

Single source of truth for every public endpoint, header, file, mailbox
and distribution channel that the SecureChat project advertises.
Every user-facing doc, release note, support reply, and Caddy block
**must** match this file. Drift between this file and the live site
is a public-beta trust regression.

The status page footer points at the latest commit hash of this file.
When you change a public endpoint, edit this file **first**, then
update everything that referenced the old value, then deploy, then
re-verify the live site.

---

## Canonical public endpoints

The relay has two surfaces:

- `securechat.team` — the user-visible product. Marketing site at the
  apex, app pages under `/docs/`, status at `/status.html`, privacy
  at `/privacy.html`.
- `relay.securechat.team` — the encrypted packet dropbox. This is the
  only host the iOS app talks to.

Caddy terminates TLS for both and reverse-proxies the relay container
on port 8080 for `relay.securechat.team`. The marketing site is
served as static files by Caddy itself (no app process for the
website).

| Purpose              | URL                                              | Auth                 |
| -------------------- | ------------------------------------------------ | -------------------- |
| Marketing site       | `https://securechat.team/`                       | none                 |
| Status page          | `https://securechat.team/status.html`            | none                 |
| Known issues         | `https://securechat.team/known-issues.html`      | none                 |
| Privacy policy       | `https://securechat.team/privacy.html`           | none                 |
| Imprint              | `https://securechat.team/imprint.html`           | none                 |
| Self-host guide      | `https://securechat.team/docs/self-host.html`    | none                 |
| Architecture         | `https://securechat.team/docs/architecture.html` | none                 |
| Public healthz       | `https://securechat.team/healthz`                | none                 |
| Operator healthz     | `https://securechat.team/healthz/internal`      | `X-Securechat-Ops-Token` |
| Relay WebSocket / API| `https://relay.securechat.team/v1/relay/*`       | `Authorization: Bearer $RELAY_AUTH_TOKEN` (and HTTPS) |
| Relay admin          | `https://relay.securechat.team/v1/admin/*`       | `Authorization: Bearer $RELAY_ADMIN_TOKEN` (and HTTPS) |
| Security policy      | `https://relay.securechat.team/v1/relay/security/policy` | none (public — this is the post-deployment posture) |
| Stats (public read)  | `https://relay.securechat.team/v1/relay/stats`   | none — see "Public stats surface" below |

### Public stats surface

`/v1/relay/stats` is unauthenticated on purpose. It returns only the
counters needed to size the relay (live packet count, total packets
served, recipients tracked). It does **not** include message
contents, peer IDs, or any payload that would let an observer
correlate traffic. The same endpoint exists at `/v1/admin/relay/stats`
behind `RELAY_ADMIN_TOKEN` and adds administrative fields (per-peer
counters, last-seen timestamps).

The current stats schema lives in
[`RelayServer/src/routes.ts`](../RelayServer/src/routes.ts) under
`app.get('/v1/relay/stats', ...)`.

## Health endpoints

Two endpoints, same shape convention as Loupe. The relay's existing
`/health` endpoint leaks operational knobs (store type, max packet
bytes, auth-required flag, etc.) — fine for an internal healthcheck,
**not** fine for a public endpoint. Sprint 1.1 splits it.

### `/healthz` (public, unauthenticated)

Returns the minimum that an external monitor or a beta user needs to
know that the relay is alive and on the expected build:

```json
{"status":"ok","uptimeSeconds":42,"version":"v0.4.0+<git-sha>"}
```

Three fields, no operational knobs, no auth.

### `/healthz/internal` (operator-only)

Same three fields, plus a flat dictionary of the relay's current
operational state. The operator must send a header
`X-Securechat-Ops-Token: $WAITLIST_ADMIN_TOKEN` (or whatever env var
is wired up at deploy time); without it, the response is `401
Unauthorized`. The token value is stored in `/opt/securechat/.../env`
on the server only and is rotated when an operator with access to
that file changes.

```json
{
  "status": "ok",
  "uptimeSeconds": 42,
  "version": "v0.4.0+<git-sha>",
  "sessions": 12,
  "peers": 7,
  "packetCount": 318,
  "nodeEnv": "production"
}
```

Field set will grow as the relay's observability surface grows;
the rule is that nothing goes into the public payload that an
external observer would not already be able to infer from the
source code.

## Distribution channels

| Artefact              | Channel                                                  |
| --------------------- | -------------------------------------------------------- |
| iOS app               | TestFlight (Public Beta)                                 |
| iOS source            | GitHub `bigbadboy1010/SecureChat` (public beta)        |
| Relay source          | same GitHub repo, `RelayServer/` subdir                  |
| Marketing site        | this repo, `RelayServer/site/` subdir (served by Caddy)  |
| Docker images         | rebuilt on `main` via `scripts/deploy-relay.sh`          |
| Privacy-respecting    | no analytics, no tracking pixels, no third-party scripts |

The TestFlight invite link is added to `docs/TESTFLIGHT-LISTING-COPY.md`
when the first TestFlight build is uploaded. Until then, the
marketing site links to the self-host guide as the recommended
onboarding path.

## Mailboxes

| Address                      | Purpose                          | Backed by           |
| ---------------------------- | -------------------------------- | ------------------- |
| `security@securechat.team`   | Vulnerability reports (PGP)      | Mailcow on the same server |
| `privacy@securechat.team`    | Privacy / data-deletion requests | Mailcow             |
| `admin@securechat.team`      | Account & abuse reports          | Mailcow             |
| `hello@securechat.team`      | Everything else                  | Mailcow             |

The PGP key for `security@securechat.team` is in `SECURITY.md` and
must be re-exported every 24 months.

## Legacy hosts (decommissioned, do not reintroduce)

The following hostnames were decommissioned during the cutover to
`securechat.team`. They must not appear in user-facing docs, release
notes, or default configurations:

- `chatsecure.ddns.net` — old NoIP free-tier hostname used for the
  pre-public-beta relay. DNS A record was removed at the registrar
  on 22 June 2026; the Caddy block returns `308 Permanent Redirect`
  to `https://securechat.team{uri}` for every request as a
  belt-and-braces measure for cached resolvers. Verified NXDOMAIN
  on 22 June 2026 (8.8.8.8, server's local resolver, build host).

## Decommission of the pre-public-beta `securechat-relay-server` image name

The relay runs in a Docker container called `securechat` (the only
container in the `securechat` Compose project). The image is built
on every `main` deploy via `scripts/deploy-relay.sh`; the image tag
is `node:22-alpine` and the build context is the `RelayServer/`
subdir of this repo. There is no separate "production" image.

## How to keep this in sync

When you change a public endpoint:

1. Update this file **first**.
2. Run `rg -n 'securechat\.team|chatsecure\.ddns\.net|relay\.securechat\.team' --type-add 'doc:*.{md,html,yml}' -t doc .`
   and clean up anything that disagrees.
3. Re-deploy the relay container and the static site.
4. Update the live status page footer to point at the new commit of this file.
