# SecureChat Incident Response Playbook

**Document version:** 1.0
**Effective:** 2026-06-24
**Owner:** François de Lattre (Verantwortlicher)
**Review cadence:** every 6 months, or after any actual incident

This playbook describes the steps the SecureChat project follows
when an actual or suspected security incident affects the
relay, the iOS app, or the supporting infrastructure. It is the
operational companion to the
[AVV](../avv.md) § 9 (Incident notification).

## 1. Definition of an incident

A *security incident* in the context of SecureChat is any
event that materially affects the confidentiality, integrity,
or availability of:

- The relay server and its TLS termination
- The sealed-envelope store
- The tombstone store
- The admin endpoints
- The iOS app's keychain or message-store
- The source code repository or the build pipeline
- The DNS / CDN configuration

A *personal-data breach* (DSGVO Art. 4 Nr. 12) is a security
incident that affects personal data. The two terms are not
synonymous; the playbook applies to both, but the
DSGVO-specific notification deadlines only apply to a
personal-data breach.

## 2. Severity classification

| Level | Definition | Examples | Response time |
|---|---|---|---|
| **SEV-1** | Active exploitation in progress, or confirmed breach of sealed envelopes / private keys | TLS private key compromise, signing key compromise, relay RCE, source-code tampering | ≤ 1 hour |
| **SEV-2** | Likely breach not yet exploited, or limited PII exposure | Single admin-token leak, single user-data-deletion request fulfilled to wrong recipient, single tombstone-store corruption | ≤ 4 hours |
| **SEV-3** | Potential vulnerability, no known exploitation, no data exposure | Disclosure of a CVE in a dependency, anonymous scan report, suspicious log entry | ≤ 24 hours |

## 3. First-hour checklist (SEV-1, SEV-2)

The following actions are taken in the first hour after an
incident is suspected, regardless of the suspected severity:

1. **Stop the bleed.** If the incident is active, take the
   affected system offline. For the relay: `docker compose stop
   securechat`. For the source-code repository: rotate
   collaborator tokens. For the iOS app: revoke the TestFlight
   build if necessary.
2. **Snapshot.** Capture the current state of logs, filesystem
   timestamps, and process state *before* changing anything.
   For the relay: `docker logs --timestamps securechat >
   /tmp/incident-<timestamp>.log`.
3. **Notify the controller.** The processor notifies the
   controller (Verantwortlicher) immediately. The controller is
   the single point of contact; the controller decides whether
   to escalate further.
4. **Classify.** Assign a severity level per § 2.
5. **Open a private incident channel.** A private channel is
   opened (encrypted email thread by default; Signal or
   Matrix in case of email compromise) to coordinate the
   response. The channel is restricted to the controller and
   to any sub-processor personnel required to remediate (e.g.
   Hetzner NOC for infrastructure incidents).

## 4. Investigation

The investigation phase has three parallel tracks:

### 4.1 Technical track
- Review of the captured snapshots (logs, filesystem, network)
- For TLS / signing-key compromise: rotate keys, force re-key
  on all clients, publish a security advisory with timeline and
  remediation
- For code tampering: review git log, identify the malicious
  commit, revert and re-publish
- For infrastructure incidents: engage Hetzner NOC, review
  hypervisor logs

### 4.2 Data-subject track
- Identify which users (peer IDs) are affected
- Determine the categories of personal data exposed (per AVV
  § 6)
- Determine the likely consequences for the data subjects
- Determine the measures taken or proposed to address the breach
  and mitigate adverse effects

### 4.3 Communication track
- Draft a security advisory in the project repository's
  `SECURITY.md` and on `https://securechat.team/status.html`
- Draft a notification to affected users (per the
  transparency policy in AVV § 11) — only if legally permitted
- Draft a notification to the supervisory authority (CNIL for
  French users; lead supervisory authority in other cases
  per Art. 56 DSGVO) within 72 hours of confirmation that
  the incident is a personal-data breach likely to result in
  a risk to the rights and freedoms of natural persons

## 5. Containment, eradication, recovery

The standard incident-response sequence (NIST SP 800-61):

1. **Containment.** Stop the bleed (per § 3.1) and prevent
   further damage. For SEV-1, the affected system may stay
   offline until eradication is complete.
2. **Eradication.** Remove the attacker's foothold: rotate
   keys, patch the vulnerable component, remove any backdoors
   or unauthorised accounts.
3. **Recovery.** Restore the system to normal operation from
   a known-good state. For the relay, this means a
   `docker compose up -d` from a freshly built image.
4. **Verification.** Confirm that the system is clean: review
   logs, run security scans, verify the integrity of the
   build pipeline.

## 6. Post-incident review

Within 7 days of incident closure:

1. **Lessons-learned document.** A markdown file is added to
   `docs/incidents/<date>-<short-slug>.md` describing the
   incident, the response, and the lessons learned. The file
   is public unless the post-incident review determines that
   public disclosure would harm the security of the project
   or its users.
2. **Process improvements.** Any process gaps identified
   during the response are added to the project backlog and
   assigned a priority.
3. **Documentation update.** This playbook and the AVV are
   updated if the incident revealed gaps in either document.
4. **Transparency report update.** The annual transparency
   report (per AVV § 11) includes a row for the incident with
   the date, severity, affected user count, and resolution.

## 7. Communication templates

### 7.1 Security advisory (public)

```markdown
# Security advisory: <short title>

**Date:** <ISO 8601>
**Severity:** <SEV-1 / SEV-2 / SEV-3>
**Affected versions:** <version range or "all">
**Patched versions:** <version or "mitigation steps below">
**CVE:** <CVE-YYYY-NNNNN> (if assigned)

## Summary

<one-paragraph summary>

## Affected

<who is affected and how to tell>

## Mitigation

<what users should do>

## Patch

<patch or upgrade instructions>

## Timeline

- <ISO 8601>: <event>
- <ISO 8601>: <event>
- ...

## Credits

<reporter, with permission>
```

### 7.2 Supervisory-authority notification (Art. 33 DSGVO)

The notification includes, per Art. 33(3):

1. The nature of the breach, including where possible the
   categories and approximate number of data subjects
   concerned
2. The name and contact details of the controller
3. The likely consequences of the breach
4. The measures taken or proposed to address the breach and
   mitigate adverse effects

The notification is sent to the lead supervisory authority
(for France: CNIL) within 72 hours. If the breach is likely
to result in a high risk to the rights and freedoms of
natural persons, affected data subjects are also notified
without undue delay (Art. 34 DSGVO).

## 8. Contact information

| Role | Contact |
|---|---|
| Verantwortlicher (Controller) | François de Lattre, privacy@securechat.team |
| Security contact | security@securechat.team |
| PGP fingerprint | (issued on request, see SECURITY.md) |
| Hetzner NOC | support@hetzner.com (24/7) |
| CNIL breach notification | https://www.cnil.fr/en/data-breach-notification |

## 9. Drills

This playbook is exercised at least once per year with a
tabletop drill. The drill is documented in
`docs/incidents/drills/<date>.md` and includes the scenario,
the response, the gaps identified, and the follow-up actions.

---

*This document is public. The full source is in the project
repository at `docs/INCIDENT-RESPONSE.md`.*
