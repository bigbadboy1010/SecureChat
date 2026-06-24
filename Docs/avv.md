# SecureChat Auftragsverarbeitungsvertrag (AVV) — Sprint 25 (2026-06-24)

## Scope

This document is the **Auftragsverarbeitungsvertrag** (AVV) the
SecureChat service makes available to enterprise customers and to
the relevant Datenschutzbehörde on request, in line with
Art. 28 DSGVO (Regulation (EU) 2016/679).

SecureChat is operated by a single individual (Verantwortlicher
under § 1 below). The relay server is hosted on a virtual
machine in a German data centre (Hetzner FSN1 / NBG); that
hosting relationship qualifies as Auftragsverarbeitung and is
the subject of this document.

The structure follows the model clauses in the
"Standardvertragsklauseln" published by the European Commission
(Decision (EU) 2021/915), adapted for the SecureChat
single-operator case.

**Versioning.** This document is the canonical reference. A
machine-readable mirror lives at
`https://securechat.team/avv.html` and at
`https://github.com/bigbadboy1010/SecureChat/blob/main/docs/avv.md`.
Material changes will be announced on the
[status page](https://securechat.team/status.html) at least
30 days in advance.

## § 1 — Verantwortlicher (Controller)

| Field | Value |
|---|---|
| Name | François de Lattre |
| Country of establishment | France (FR), with EU representative available on request |
| E-Mail (general) | hello@securechat.team |
| E-Mail (privacy) | privacy@securechat.team |
| E-Mail (security) | security@securechat.team |
| PGP fingerprint | (issued on request, see SECURITY.md) |
| Supervisory authority | CNIL (Commission Nationale de l'Informatique et des Libertés), 3 place de Fontenoy, TSA 80715, 75334 Paris Cedex 07 |

## § 2 — Auftragsverarbeiter (Processor)

The relay server is operated on a virtual private server
(VPS) leased from Hetzner Online GmbH. Hetzner acts as
**Unterauftragsverarbeiter** (Sub-Processor) under the same
Art. 28 obligations.

| Field | Value |
|---|---|
| Provider | Hetzner Online GmbH, Industriestr. 25, 91710 Gunzenhausen, Germany |
| Data centre | FSN1 (Falkenstein) and NBG1 (Nuremberg), Germany |
| Certifications | ISO 27001; ISO 27017; ISO 27018; PCI-DSS |
| GDPR posture | EU-based provider; no third-country transfers |
| Hosting model | Single-tenant VPS, dedicated to SecureChat |
| Data location | EU/EEA only (FSN1/NBG1) |
| Provider's role | Unterauftragsverarbeiter (Art. 28 Abs. 2 DSGVO) |

The Hetzner Auftragsverarbeitungsvertrag (Hetzner AVV) is
countersigned and is available under NDA on request to
privacy@securechat.team.

## § 3 — Gegenstand und Dauer der Verarbeitung

**Gegenstand.** Hosting and operating the SecureChat relay
server, which stores and forwards opaque, client-encrypted,
client-signed message envelopes between two devices whose
operators have exchanged a peer ID.

**Dauer.** The processing relationship begins on the date the
user installs the SecureChat app and ends 30 days after the
user uninstalls the app and requests data deletion, after
which all user-derived data is removed per § 8.

For the public-beta phase specifically, the relay retains
sealed packets for at most 24 hours and tombstones for the
lifetime of the sender's last known peer ID, both of which
fall under this AVV.

## § 4 — Art und Zweck der Verarbeitung

The processing is limited to what is **strictly necessary** to
operate the SecureChat service:

1. **Envelope relay.** Store and forward opaque, client-signed
   sealed message envelopes (Curve25519/XChaCha20-Poly1305) in
   volatile memory; route them between the two paired peers.
2. **Tombstone recording.** Mark delivered envelopes as
   delivered so they are not re-delivered.
3. **Admin operations.** A single bearer-token-gated admin
   endpoint (POST /v1/admin) for health monitoring and abuse
   investigation. All admin access is logged.
4. **Log rotation.** Standard server logs (timestamps, IP
   addresses, user agents, request paths, status codes) are
   written to stdout via pino and rotated daily. Used for
   rate-limit enforcement, abuse mitigation, and incident
   investigation only.

The processor will not:
- Decrypt or attempt to decrypt any sealed envelope.
- Inspect, classify, or fingerprint message contents.
- Correlate envelope metadata across users.
- Combine SecureChat data with any other data set the
  processor holds.
- Use SecureChat data for any purpose other than operating
  the SecureChat service.
- Disclose sealed envelopes to any third party, including
  law enforcement, without a binding legal order (see § 11
  for the transparency policy).

## § 5 — Kategorien betroffener Personen

| Category | Source | Notes |
|---|---|---|
| SecureChat users (sender + recipient) | App installation and use | Each user controls their own keypair; the service does not collect identity beyond the public Curve25519 key and the random 64-hex peer ID |
| Visitors of securechat.team (marketing pages) | HTTP request | IPs in logs only; no fingerprinting |
| TestFlight beta testers | TestFlight install | Apple processes standard TestFlight metadata (see § 7 below) |

The processor does **not** collect any data from minors.
SecureChat's age rating is enforced by Apple's TestFlight /
App Store (rated 17+).

## § 6 — Kategorien personenbezogener Daten

| Category | Data | Where stored |
|---|---|---|
| **IP-Adresse** | The IP address that connected to the relay | Server log files, 14-day rotation, then deleted |
| **Zeitstempel** | Request start/end timestamps | Server log files, 14-day rotation |
| **User-Agent** | iOS / TestFlight build / app version string | Server log files, 14-day rotation |
| **Peer-ID** | Random 64-hex peer ID of sender/recipient (NOT linked to any identity) | In-memory only, max 24 hours |
| **Sealed envelope** | Sealed Curve25519/XChaCha20-Poly1305 message envelopes | In-memory + on-disk store, max 24 hours, then deleted |
| **Tombstone** | Marker indicating a peer ID has received a given envelope | On-disk store, deleted when peer ID is deleted |

**Data the processor NEVER collects:**
- Plaintext message contents (always client-encrypted)
- Curve25519 private keys (live in iOS Keychain only)
- Contact lists, phone numbers, email addresses, names
- Location, microphone, camera, photos
- Account credentials, financial data
- IDFA, advertising identifiers
- Crash reports, analytics events (no SDK of any kind)
- Behavioural or cross-app tracking data

## § 7 — Pflichten des Auftragsverarbeiters

The processor (and the sub-processor Hetzner) undertakes to:

1. Process personal data only on documented instructions from
   the controller, including with regard to transfers of
   personal data to a third country or international
   organisation. There are no third-country transfers in the
   current design.
2. Ensure that persons authorised to process the personal
   data have committed themselves to confidentiality or are
   under an appropriate statutory obligation of
   confidentiality.
3. Implement all technical and organisational measures
   required pursuant to Art. 32 DSGVO. The current TOM
   (Technisch-Organisatorische Maßnahmen) catalogue is
   documented in `docs/SECURITY.md` and includes:
   - non-root container execution
   - TLS 1.3 only, HSTS with `max-age=31536000`
   - sealed-envelope-only design (no plaintext in any
     pipeline)
   - 14-day log rotation with explicit deletion
   - bearer-token admin access, audit-logged
4. Engage sub-processors only with the prior specific or
   general written authorisation of the controller. The
   current sub-processors are listed at
   `https://securechat.team/sub-processors.html`. Changes are
   announced 30 days in advance.
5. Assist the controller in fulfilling its obligation to
   respond to requests for exercising the data subject's
   rights (Chapter III DSGVO): access, rectification,
   erasure, restriction, portability, objection, complaint.
6. At the choice of the controller, delete or return all
   personal data after the end of the provision of services
   relating to processing (see § 8).
7. Make available to the controller all information
   necessary to demonstrate compliance with Art. 28
   obligations and allow audits.

## § 8 — Datenlöschung und Rückgabe

After termination of the SecureChat service or upon a
data-deletion request from a data subject, the controller
will:

- Delete all sealed envelopes (within 24 hours of their
  TTL, by design).
- Delete all tombstones associated with the deleted peer
  IDs (within 30 days of the deletion request).
- Delete all server log entries older than 14 days (by
  automated rotation).
- Confirm the deletion in writing within 30 days of the
  request.

**No backup retention.** SecureChat does not keep offline
backups of envelope or tombstone data. A user who requests
deletion can be confident that no copy of their data is held
in a backup or in cold storage.

## § 9 — Sicherheitsvorfall (Art. 33 DSGVO)

The processor will notify the controller without undue
delay, and in any case within **24 hours**, of becoming aware
of a personal data breach affecting SecureChat data. The
notification will include the information required by
Art. 33(3) DSGVO to the extent then known, and will be
updated as the investigation proceeds.

The controller will notify the competent supervisory
authority within 72 hours of becoming aware of the breach,
where the breach is likely to result in a risk to the rights
and freedoms of natural persons.

The transparency policy (§ 11) governs whether and how
affected users are informed.

A detailed incident-response playbook is in
`docs/INCIDENT-RESPONSE.md`.

## § 10 — Sub-Processor Management

The current sub-processors are documented in
`docs/SUB-PROCESSORS.md` and at
`https://securechat.team/sub-processors.html`. The current
list is:

| Sub-processor | Purpose | Data | Region |
|---|---|---|---|
| Hetzner Online GmbH | VPS hosting (relay server) | Sealed envelopes, logs | DE (FSN1, NBG1) |
| GitHub, Inc. | Source code hosting, public issue tracker | Public commits, public issues only | USA (EU mirror available) |
| Cloudflare, Inc. | Authoritative DNS, edge CDN for static marketing site | DNS query logs (anonymized) | Global anycast (EU nodes) |
| Apple, Inc. | TestFlight distribution during public-beta phase | Installation counts, crash counts | USA (Apple's global infrastructure) |

The controller commits to giving the data subjects at
least 30 days' advance notice via the
[status page](https://securechat.team/status.html) before
adding a new sub-processor, and to honour any data subject's
right to object (Art. 21 DSGVO) by enabling them to
self-host the relay.

## § 11 — Transparenz und Auskunftsanfragen

The processor publishes an annual transparency report on
`https://securechat.team/status.html` covering:

- Number of government data requests received and the
  response given (in jurisdictions where such publication
  is legal — see the EFF and Access Now transparency
  guidelines).
- Number of data-deletion requests fulfilled and the
  average response time.
- Number of personal-data breaches (if any) and their
  resolution.

The processor will resist, in court if necessary, any
government request to disclose sealed envelopes, on the
basis that the relay holds no plaintext and therefore the
disclosure of an envelope cannot provide a government with
the plaintext content of a message. Where disclosure of
metadata (peer IDs, timestamps) is compelled by a binding
legal order, the processor will:

1. Challenge the order on the basis of proportionality
   and jurisdiction if it has legal standing to do so.
2. Notify affected users in advance if legally permitted.
3. Publish the request in the next transparency report if
   legally permitted.

## § 12 — Haftung (Liability)

The processor's liability is limited as set out in the
underlying terms of service between the controller and the
end user. Nothing in this AVV limits any statutory liability
of the controller or the processor under Art. 82 DSGVO.

## § 13 — Änderungen dieses AVV (Changes to this AVV)

Material changes to this AVV will be announced:

- On the [status page](https://securechat.team/status.html)
  at least 30 days in advance.
- In the iOS SecureChat app on next launch.
- Via a CHANGELOG entry in the public GitHub repository.

The full version history of this document is available at
`https://github.com/bigbadboy1010/SecureChat/commits/main/docs/avv.md`.

**In case of conflict** between this document and the
Standardvertragsklauseln (Decision (EU) 2021/915), the
Standardvertragsklauseln take precedence.

---

*Version 1.0 — Effective 2026-06-24*
*Authored by François de Lattre (Verantwortlicher)*
*License: CC-BY-SA-4.0 (so enterprises can re-use the structure)*
