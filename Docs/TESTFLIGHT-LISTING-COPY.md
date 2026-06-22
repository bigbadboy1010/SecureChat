# TestFlight & App Store Connect listing copy

> Single source of truth for the user-facing strings shown on
> [TestFlight](https://testflight.apple.com/join/wsJeRw1M) and
> (later) the App Store listing for the SecureChat iOS app.
>
> Every change to App Name, Subtitle, Description, What's New,
> or Marketing URL must be applied here **and** in App Store Connect
> in the same change. Drift between the two is a public-beta trust
> regression.

> ⚠️ **Drift alert — last verified 22 June 2026.**
> The current TestFlight description in App Store Connect reads
> the placeholder from the Loupe-era listing. The
> reviewer-recommended replacement is in the **Description** block
> below. The action item is in App Store Connect (UI), not in the
> repo. Apply it, then update the verification line above.

**Bundle ID:** `org.francois.securechat`
**App Store Connect app name:** `SecureChat`
**Primary locale:** `en-US`
**Last updated:** 2026-06-22

---

## App Name (max 30 chars)

```
SecureChat
```

> 10 characters. Do NOT rename to "Loupe" or anything Loupe-related
> — SecureChat is a separate product with a separate code path,
> separate distribution, and separate Security disclosure.

## Subtitle (max 30 chars)

```
End-to-end encrypted chat
```

> 24 characters. Avoid dashes, slashes, or punctuation — App Store
> Connect strips them silently in some locales.

## Promotional Text (max 170 chars; can be updated without a new build)

```
Privacy-first iOS messenger. Curve25519 + AES-GCM, on-device only.
The relay is a blind packet dropbox: it never sees your messages.
```

## Description

```
SecureChat is a privacy-first iOS messenger. The cryptography runs
on-device — Curve25519 key agreement, AES-GCM message encryption,
Ed25519 envelope signatures — and the relay is a blind packet
dropbox: it stores and forwards opaque, client-sealed, client-signed
envelopes. It never sees your plaintext, your keys, or your message
bodies.

• End-to-end encryption. The relay cannot read your messages.
• No phone number. No email. Your identity is your Curve25519 keypair.
• No analytics. No tracking. No third-party SDKs. No push-notification
  content reaches the relay; only opaque packets.
• Source-available. Self-host the relay on a $5/month VPS and point
  the app at it. About 20 minutes if DNS and firewall are ready.
• Local-first. Messages are stored encrypted on your device; iCloud
  backup is explicitly excluded for sensitive stores.
• Safety Number verification. Compare a 60-digit fingerprint with
  your peer out of band to defend against key substitution.
• Biometric app lock. Face ID / Touch ID gate on launch.

The relay is built on Fastify (Node 22) and stores sealed packets
for at most 24 hours. The protocol is documented at
https://securechat.team/docs/architecture.html. The current public
beta runs at https://relay.securechat.team.

Status, current build, and known issues are listed on
https://securechat.team/status.html. To report a vulnerability,
email security@securechat.team (PGP key in SECURITY.md).
```

## Keywords (max 100 chars, comma-separated)

```
e2e,encrypted,chat,messenger,curve25519,aes-gcm,privacy,no phone,free,no analytics
```

## Support URL

```
https://securechat.team/
```

## Marketing URL

```
https://securechat.team/
```

## Privacy Policy URL

```
https://securechat.team/privacy.html
```

## What's New (this build)

> Keep tight — App Store Connect caps this at 4000 chars but the
> visible area on TestFlight is ~150 chars before "more".

```
First public beta of SecureChat for iOS. Pair with another iPhone
running SecureChat via Safety Number verification, send sealed
messages through the public relay at relay.securechat.team, or
self-host the relay on your own VPS. See https://securechat.team/
status.html for current build, known issues, and roadmap.
```

## What's New (subsequent builds)

Use the format:

```
<VERSION> — <short feature sentence>. See https://securechat.team/CHANGELOG.md
for the full change list.
```

---

## Common reviewer traps to avoid

- **Do not** use "Iphone" (capital I only). Use "iPhone". TestFlight
  displays the raw subtitle and description verbatim in most locales,
  and Apple has historically flagged the typo.
- **Do not** describe SecureChat as "the most secure messenger" or
  any superlative without a citation. App Store Review Guideline 4.3
  ("spam and misleading metadata") is the usual rejection reason.
  Use the verifiable form: "end-to-end encryption with on-device
  Curve25519 + AES-GCM".
- **Do not** claim "no data is ever sent" — the relay receives
  opaque envelopes. The verifiable claim is "the relay never sees
  message plaintext or keys; it can only forward opaque envelopes".
- **Do not** promise features that are still on the roadmap. The
  status page is the canonical "what works today" answer; if a
  feature is listed there as `Planned`, it must not appear in the
  TestFlight description as a current capability.
- **Do not** add analytics SDKs. The privacy posture is
  "no analytics, no tracking, no third-party scripts". Adding
  Firebase, Sentry, or any SDK invalidates the privacy claim on
  the marketing site.
- **Do not** call the iOS app "Loupe" or otherwise refer to the
  Loupe product. They are separate apps with separate bundle ids
  and separate TestFlight listings.

## Drift detection

After every release, run a quick manual check from the TestFlight
iOS app (or `xcrun altool --validate-app`):

1. Open the public beta page and read the description out loud.
2. Compare every sentence against this file.
3. If anything diverges, edit this file **and** the App Store
   Connect listing in the same change.
