# Relay Phase 3 test – historical compatibility note

This filename is retained for old links. The original local Phase 3 server
workflow is obsolete and must not be used for a Release/TestFlight build.

Current sources of truth:

- endpoints: [`CURRENT-ENDPOINTS.md`](CURRENT-ENDPOINTS.md);
- full iPhone acceptance: [`iphone-test-acceptance.md`](iphone-test-acceptance.md);
- release procedure: [`IOS-TESTFLIGHT-RUNBOOK.md`](IOS-TESTFLIGHT-RUNBOOK.md).

## Current production test

In SecureChat:

1. Open `Einstellungen`.
2. Select relay transport.
3. Use `https://securechat.team`.
4. Enter only the client `RELAY_AUTH_TOKEN` value.
5. Save the configuration.
6. Open `Einstellungen → Diagnose & Sicherheitsstatus` and refresh.

Expected behavior:

- relay health is reported as reachable;
- an enrolled, verified peer can send and receive;
- received packets are acknowledged;
- retry does not create duplicate messages;
- no request uses a legacy DDNS, LAN or plain-HTTP endpoint.

For local relay engineering, use an isolated development configuration and
the relay repository's current runbook. Never carry a development URL or
admin credential into the iOS Release configuration.
