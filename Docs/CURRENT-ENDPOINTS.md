# SecureChat Current Endpoints

This file is the source of truth for public SecureChat endpoints used
by the iOS client and release documentation.

## Canonical endpoints

| Purpose | URL | Auth |
|---|---|---|
| Product site | `https://securechat.team/` | none |
| Status | `https://securechat.team/status.html` | none |
| Privacy | `https://securechat.team/privacy.html` | none |
| Known issues | `https://securechat.team/known-issues.html` | none |
| Relay public health | `https://securechat.team/healthz` | none |
| Relay client API | `https://securechat.team/v1/relay/*` | client bearer token plus peer-bound signing where required |
| Relay admin API | `https://securechat.team/v1/admin/*` | operator/admin credentials |

The iOS production profile must use exactly:

```text
https://securechat.team
```

## Legacy endpoints

The following values are obsolete and must never be used by a
Release/TestFlight build:

- `https://relay.securechat.team`
- `http://relay.securechat.team`
- `https://chatsecure.ddns.net`
- `http://chatsecure.ddns.net`
- `http://192.168.178.229:8080`
- `http://localhost:8080`
- `http://127.0.0.1:8080`

The client migration layer converts the broken relay subdomain and old
DDNS/LAN configuration to
the canonical production relay and blocks insecure production HTTP.

## Distribution and source locations

| Artefact | Location |
|---|---|
| iOS client source | GitHub `bigbadboy1010/SecureChat` |
| iOS beta | Apple TestFlight |
| Relay implementation | private operator repository |
| Product/status pages | operator-managed `securechat.team` deployment |

The public repository does not contain the production relay
implementation. CI in this repository therefore builds/tests the iOS
client only.

## Client identity

- Display name: SecureChat
- Xcode target / scheme: `PrivateChat`
- Bundle ID: `org.francois.PrivateChat`
- Current candidate: 1.4.2 (Build 13)

## Operational rule

When an endpoint changes:

1. update this file
2. update `SecureChatProductionProfile.swift`
3. update release/privacy documentation
4. deploy the server-side change
5. test health, enrollment, SEND, inbox GET and ACK from a physical
   iPhone before distributing a new TestFlight build
