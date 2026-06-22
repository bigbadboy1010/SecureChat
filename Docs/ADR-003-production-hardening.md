# ADR-003: Production-hardening contract for the relay

**Status:** Accepted
**Date:** 2026-06-22
**Supersedes:** none

## Context

The relay runs in a public, multi-tenant, internet-facing
environment. A misconfigured deployment is a security incident,
not a performance issue. We need the relay to refuse to start in
production unless the deployment is set up correctly, and we need
the failure mode to be loud (a clear, specific error message) so
that the operator can fix the configuration without a code
change.

## Decision

The relay fails fast at startup in production unless **all** of
the following are true:

- `NODE_ENV=production`.
- `STORE_TYPE=file` (not `memory`).
- `RELAY_AUTH_TOKEN` is set and is at least
  `MIN_AUTH_TOKEN_LENGTH` characters (default 32).
- HTTPS is required for `/v1/relay/*` and `/v1/admin/*` unless
  `REQUIRE_HTTPS_IN_PRODUCTION=false` is set explicitly. The
  default is `true`; the operator must opt out to run a
  non-HTTPS deployment.
- The data dir is writable.

The `preHandler` hook in `RelayServer/src/routes.ts` enforces the
HTTPS and the auth requirements on every relay and admin request
in production. The `onSend` hook adds the response headers that
the project's trust posture requires (`Cache-Control: no-store`,
`Referrer-Policy: no-referrer`, `X-Frame-Options: DENY`, the
`Permissions-Policy` set).

The `onResponse` hook writes a security-audit log line per
relay/admin request when `SECURITY_AUDIT_LOG=true` (the default).
The line is JSON via pino and includes the request id, the
sanitised path (query string removed), the method, and the
response status code. The body, the peer IDs, and the sealed
payload are **not** logged.

The startup check is in `RelayServer/src/index.ts`'s
`loadConfig` step: any of the above failures throw before the
Fastify server is registered.

## Consequences

- A fresh checkout of the repo will not start in production with
  the default `.env`. The operator must replace the
  `change...hars` placeholders with real tokens. This is the
  correct outcome.
- The `RELAY_AUTH_TOKEN` and `RELAY_ADMIN_TOKEN` are
  high-entropy secrets. They are not committed to the repo, not
  logged, and not surfaced in the public healthcheck. They live
  in `/opt/securechat/.../env` on the server and are rotated when
  an operator with access to that file changes.
- A non-HTTPS deployment requires the operator to set
  `REQUIRE_HTTPS_IN_PRODUCTION=false`. The default is
  HTTPS-only. This is a deliberate friction: a typo in a
  self-hosted setup that runs over plain HTTP will fail
  immediately, not silently.
- The audit log is sized by request volume, not by packet size.
  At 120 req/min per IP, the log volume is bounded. Operators
  with high traffic should set `SECURITY_AUDIT_LOG=false` and
  rely on a structured access log at the Caddy layer instead.
- The header set in the `onSend` hook is the minimum for the
  project's trust posture. We do not set `Strict-Transport-Security`
  in the relay itself because the termination happens at Caddy
  upstream; double-setting would create a confusing debugging
  story.

## Alternatives considered

- **Per-request rate limiting by peer ID.** Considered. The current
  rate limit is per-IP, which is simpler and is what the public
  deployment uses. A per-peer-id limit would defend against a
  single peer-id being used to flood the relay, but the relay
  already enforces a per-recipient storage cap (500 packets) and
  a global cap (10 000 packets), which is the same defence at
  the storage layer.
- **Strict-Transport-Security in the relay itself.** Rejected
  (see above).
- **A separate "audit log mode" that includes bodies.** Rejected.
  Logging bodies would defeat the zero-knowledge posture. If you
  need body-level debugging, run the dev mode with a fake store
  on a local machine.
- **A "dry-run" mode that simulates production but does not
  enforce the checks.** Considered and rejected. The dev mode
  (`NODE_ENV=development`) is the dry-run mode.
