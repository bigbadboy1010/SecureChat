# SecureChat End-to-End Test Coverage — Sprint 20 (2026-06-24)

## Scope

This document is the design note for the automated
end-to-end test suite that ships with the SecureChat
relay, iOS app, and the macOS pairing-host (for the
self-hosted mode). It is written for the next maintainer
who needs to add a regression test or to debug a failing
CI run.

## What ships

The Sprint 20 pipeline produces:

- `RelayServer/test/smoke.ts` (250 lines) — boots an
  ephemeral Fastify instance on a random port, runs
  through the v1 relay API end-to-end, exits with
  `SC SMOKE TEST PASSED` on success.
- `scripts/e2e-acceptance.sh` (110 lines) — bash wrapper
  that runs the policy check, the `/healthz` check, and
  the smoke test against a reachable relay at
  `$RELAY_BASE_URL` (default `http://127.0.0.1:3000`).
  Refuses to run against a `productionMode=true` relay.
- `.github/workflows/e2e.yml` — CI workflow. Three jobs:
  `smoke` (every PR + push), `ios-controller-build`
  (release tag only), `acceptance` (release tag only,
  spins up a docker-compose relay for the test).

## Why a `buildServer` factory

The relay's `src/index.ts` was a top-level script that
called `app.listen()` at module load. That made it
impossible to import the Fastify instance from a test
without binding a TCP port. Sprint 20 splits the module
into:

- `buildServer(overrides)` — returns a `FastifyInstance`
  with all routes, hooks, and stores wired. No listener.
- `startServer()` — calls `buildServer()` and then
  `app.listen()`. Used by the production entry point and
  by the smoke test for its "ephemeral" instance.
- An `isEntryPoint` guard (using `process.argv[1]` vs
  `import.meta.url`) that only calls `startServer()` when
  the module is the program entry point, not when it is
  imported by the smoke test.

The guard is the same pattern as Loupe's `LoupeHostApp`
CLI mode: detect "am I being imported or am I the
program?" via the resolved entry URL.

## Smoke test coverage

```
SC smoke test (test/smoke.ts):
  1) GET  /healthz                              → 200, status=ok
  2) GET  /v1/relay/security/policy            → 200, store=memory
  3) POST /v1/relay/messages (Alice → Bob)      → 202, accepted=true
  4) GET  /v1/relay/messages?recipientID=...   → 200, packets array contains the packet
  5) POST /v1/relay/messages/:id/ack           → 200, deleted=true
  6) Replay protection (same headers twice)    → second request NOT 202
  7) Bad-signature tolerance (verifier parses) → status < 500
```

Run it with `cd RelayServer && npx tsx test/smoke.ts`.
It runs in ~ 0.5 s on a CI runner.

## CI workflow

`.github/workflows/e2e.yml` has three jobs:

| Job | Trigger | Runner | Time |
|---|---|---|---|
| smoke | every PR + push | ubuntu-latest | ~30 s |
| ios-controller-build | release tag only | macos-14 | ~5 min |
| acceptance | release tag only | ubuntu-latest + docker | ~1 min |

The `smoke` job also publishes `build/e2e-result.json`
as a workflow artifact (30-day retention) so the next
maintainer can inspect what the acceptance test last
saw.

## What the acceptance test deliberately does NOT do

- It does **not** simulate network failures — the
  smoke test assumes a healthy ephemeral relay.
- It does **not** drive the iOS controller from CI.
  That is Sprint 20.1 (`xcrun simctl install` +
  `launch` + grep on the device's log).
- It does **not** test rate-limiting exhaustively. The
  Loupe smoke test has a burst test; SC's relay shares
  the Fastify rate-limit middleware so the assertion is
  inherited.
- It does **not** run against a real TURN server. The
  relay's TURN-host config is plumbed but the test
  doesn't allocate relay candidates.

## Verified locally

```
$ cd RelayServer && npx tsc --noEmit     → OK
$ cd RelayServer && npx tsx test/smoke.ts → SC SMOKE TEST PASSED
$ bash -n scripts/e2e-acceptance.sh        → OK
$ python3 -c "import yaml; ..." e2e.yml    → OK
```

## See also

- `RelayServer/src/index.ts` — `buildServer` + `startServer`
- `RelayServer/src/peerAuth.ts` — peer-bound request signing
- `RelayServer/src/schemas.ts` — wire-format Zod schemas
- `docs/SBOM.md` — Sprint 21 design note for the dependency tree