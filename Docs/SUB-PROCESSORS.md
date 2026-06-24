# SecureChat Sub-Processors

This document is the canonical list of sub-processors that
process personal data on behalf of SecureChat under Art. 28
DSGVO. The same list is published at
`https://securechat.team/sub-processors.html` and is updated
in lockstep with the website version.

A *sub-processor* is any third party that processes personal
data on the controller's behalf. SecureChat minimises the
number of sub-processors; the current list is small.

## Current sub-processors

| Sub-processor | Purpose | Data processed | Region | Compliance |
|---|---|---|---|---|
| **Hetzner Online GmbH** | VPS hosting for the relay server | Sealed envelopes, server logs | DE (FSN1, NBG1) | ISO 27001, ISO 27017, ISO 27018, PCI-DSS |
| **GitHub, Inc.** | Public source-code hosting, public issue tracker, public roadmap | Public commits, public issues, public discussions. No message content. | USA (primary), EU mirror available | EU-US Data Privacy Framework certified; SOC 2 Type II |
| **Cloudflare, Inc.** | Authoritative DNS, edge CDN for the static marketing site | DNS query logs (anonymized), HTTP access logs for static pages. No message content. | Global anycast (EU nodes available) | EU-US Data Privacy Framework certified; ISO 27001, SOC 2 |
| **Apple, Inc.** | TestFlight distribution during the public-beta phase | Installation counts, session counts, crash counts per build. Free-text feedback if you submit it. | USA (Apple operates TestFlight globally) | SOC 2 Type II; Apple Privacy Policy applies |

## What is NOT a sub-processor

For clarity, these are **not** sub-processors because they
process no SecureChat data:

- No third-party analytics (no Google Analytics, no Plausible,
  no Fathom)
- No third-party error tracking (no Sentry, no Bugsnag, no
  Crashlytics)
- No third-party email marketing (no Mailchimp, no ConvertKit,
  no Sendgrid)
- No third-party payments (no Stripe, no PayPal — the app is
  free during the public-beta phase)
- No social-login SDKs (no Sign in with Apple, no Facebook, no
  Google)
- No third-party identity providers (the relay's admin endpoints
  use a per-deploy bearer token)

## Adding a new sub-processor

If we add a new sub-processor, we will:

1. Publish the change on the
   [status page](https://securechat.team/status.html) at least
   **30 days** before it takes effect.
2. Update this document and the
   [sub-processors page](https://securechat.team/sub-processors.html)
   with the sub-processor name, purpose, data processed, region,
   and compliance certifications.
3. Announce it in the iOS app on next launch.
4. Honour any data subject's right to object (Art. 21 DSGVO)
   by enabling them to self-host the relay.

You can request a copy of the sub-processor's data-processing
agreement by emailing
[privacy@securechat.team](mailto:privacy@securechat.team).

## Source of truth

The full source of this document is in the project repository
at
[`docs/SUB-PROCESSORS.md`](https://github.com/bigbadboy1010/SecureChat/blob/main/docs/SUB-PROCESSORS.md).
Changes are tracked via git history.

---

*Version 1.0 — Effective 2026-06-24*
*Authored by François de Lattre (Verantwortlicher)*
