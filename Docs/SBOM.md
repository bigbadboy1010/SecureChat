# SecureChat Software Bill of Materials — Sprint 21 (2026-06-24)

## Scope

Design note for the SBOM + dependency-audit pipeline.
Mirrors Loupe's `docs/SBOM.md`. The two surfaces:

1. **Relay** (`RelayServer/`) — Fastify 5 + zod + pino
   + @fastify/rate-limit + @fastify/static.
2. **iOS app** (`ios/PrivateChat.xcodeproj`) — SwiftPM
   with one dep: `WebRTC` 120.0.0 (Google WebRTC M120,
   stasel mirror), shared with Loupe's host.

## What ships

- `scripts/sbom-generate.sh` (~ 100 lines) — emits
  CycloneDX 1.5 JSON for the relay + iOS surface plus a
  combined `combined.cdx.json`.
- `scripts/dep-audit.sh` (~ 90 lines) — wraps
  `npm audit`, exits non-zero at the configured severity
  threshold, writes `build/audit.json`.
- `.github/workflows/sbom.yml` — 2-job CI matrix:
  `sbom` (every push + tag + weekly Mon 06:00 UTC,
  uploads SBOM as 365-day artifact on release tags) and
  `audit` (every push, fails on high/critical, uploads
  90-day report).

## Current dependency posture

```
RelayServer production (4 deps):
  @fastify/rate-limit ^10.3.0  (MIT, Fastify ecosystem)
  @fastify/static      ^9.1.3   (MIT)
  fastify              ^5.2.1   (MIT)
  zod                  ^3.24.2  (MIT)

RelayServer dev (3 deps):
  @types/node ^22.13.1
  tsx         ^4.19.2
  typescript  ^5.7.3

iOS (1 dep):
  WebRTC      120.0.0  (BSD-3, stasel mirror of Google WebRTC M120)
```

`npm audit` last run: **0 vulnerabilities** (24 June 2026).

## Why no new tooling

Same rationale as Loupe: `package.json` + `Package.swift`
are the source of truth. Adding `cyclonedx-bom` / `syft` /
`grype` would mean another dep to audit + a heavier CI
image + risk of SBOM drift from the lock file. Reading
the same files npm/SwiftPM just parsed keeps the SBOM
honest.

## Running locally

```
scripts/sbom-generate.sh                # writes build/sbom/*.cdx.json
scripts/dep-audit.sh --fail-on=high     # writes build/audit.json
```

The audit exit code is the action: 0 = clean, 1 =
high/critical advisory found.

## CI matrix

| Job | Trigger | Action |
|---|---|---|
| `sbom` | every push + tag + weekly Mon 06:00 UTC | generates + validates JSON; uploads 365-day artifact on release tags |
| `audit` | every push to main | runs `npm audit`; fails on high/critical; uploads 90-day report |

## See also

- `scripts/sbom-generate.sh` — SBOM generator
- `scripts/dep-audit.sh` — vulnerability audit
- `.github/workflows/sbom.yml` — CI workflow
- Loupe's `docs/SBOM.md` — same design note for the
  Loupe side; the two pipelines are intentionally
  symmetric so a maintainer who learned one learns both.