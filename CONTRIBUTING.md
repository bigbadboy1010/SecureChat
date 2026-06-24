# Contributing to SecureChat

Thanks for your interest in contributing to **SecureChat** — the
end-to-end encrypted iOS messenger with a hardened Fastify blind relay.

This project is open source under the **GNU Affero General Public License
v3 (AGPL-3.0)**. By contributing, you agree that your contributions will
be licensed under the same AGPL-3.0 license.

## 📜 Contributor License Agreement (CLA)

Before we can merge any **non-trivial** contribution, we ask that you sign
our **Contributor License Agreement**. This protects both you and the
project:

- **You retain copyright** to your contribution.
- **You grant us a license** to use your contribution under AGPL-3.0 and
  (optionally) under a separate commercial license, so we can offer
  commercial support to enterprise users without violating AGPL.
- **You confirm** that the contribution is your own original work, or that
  you have the right to submit it under these terms.

The CLA bot will comment on your PR with a link to the agreement. It is
short, plain-English, and standard for AGPL projects that also ship a
commercial offering.

> **Small contributions** (typo fixes, single-line clarifications, doc
> improvements of <50 lines) do **not** require a CLA — we accept them
> under the AGPL-3.0 only.

## 🚀 How to contribute

1. **Fork the repository** on GitHub.
2. **Create a topic branch** from `main`:
   ```bash
   git checkout main
   git pull origin main
   git checkout -b feat/my-contribution
   ```
3. **Make your changes** in small, well-scoped commits.
4. **Run the test suite** before pushing:
   ```bash
   # iOS
   xcodebuild -project PrivateChat.xcodeproj -scheme PrivateChat \
     -destination 'platform=iOS Simulator,name=iPhone 17' test
   # Relay
   cd RelayServer && npm run test:smoke && npm run test:e2e
   ```
5. **Push** your branch and **open a Pull Request** against `main`.

## 🎯 What we are looking for

| Area | Examples |
|---|---|
| **Cryptography** | ADR-style design proposals for new primitives; reviewed via `Docs/ADR-XXX-*.md` PRs |
| **Relay hardening** | Rate-limit / abuse-detection / DPoP-style sender-bound nonce improvements |
| **iOS UI/UX** | Accessibility, VoiceOver, Reduce-Motion, dynamic-type |
| **Doku** | `Docs/`, `RelayServer/site/`, `CHANGELOG.md` polish |
| **Build / CI** | SBOM reproducibility, reproducible TestFlight builds |

## 📋 Pull Request checklist

- [ ] Commit messages follow the pattern `feat(scope):`, `fix(scope):`,
      `docs:`, `chore:`, `refactor:`, `test:`.
- [ ] PR description links the relevant issue / ADR / sprint.
- [ ] Tests pass (iOS + relay).
- [ ] `CHANGELOG.md` updated under `## Unreleased` for user-visible changes.
- [ ] Doku updated (`README.md`, `Docs/`, `RelayServer/site/`) if the
      PR changes public endpoints or user-facing behavior.

## 🐛 Reporting security issues

**Do not file a public issue for security vulnerabilities.** See
[`SECURITY.md`](SECURITY.md) for the coordinated-disclosure policy and
the contact address.

## 💬 Code of Conduct

All participants are expected to follow our
[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). Please read it before your
first contribution.

## ❓ Questions?

Open a GitHub Discussion (preferred) or reach out to the maintainers via
the address in `SECURITY.md`.