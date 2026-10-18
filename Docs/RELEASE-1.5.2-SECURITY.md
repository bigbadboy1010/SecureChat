# Prepared security beta 1.5.2 (19)

NOT DISTRIBUTED. The user explicitly requires accepted forward secrecy before the next TestFlight upload. See `Config/SecurityReleaseGate.json` and [protocol/persistence design](FORWARD-SECRECY-2026-10-18.md).

Changes prepared together: exclusive Olm protocol 4, authenticated one-time bootstrap keys, durable retry/inbound journals, receiver-owned consent, inbox cursor pagination, sender/device capacity limits, stable packet IDs, Retry-After backoff, optional neutral push, clear device-loss guidance, and matching privacy notices. Relay 0.3 is required. Existing device identities and verified SC3 keys are preserved; no paid-branch source is overwritten.

Before distribution: complete independent integration review, physical two-device restart/offline/attachment test, updated Apple encryption declaration and privacy metadata, final Linux relay image/scan, coordinated receiver-consent/Olm rollout, protected push-worker deployment and real-device push acceptance. Monitor alerts currently exist on-host only; external operator notifications are not configured. No high-sensitivity or public security approval is given.
