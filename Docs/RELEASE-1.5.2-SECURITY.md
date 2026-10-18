# Prepared security beta 1.5.2 (19)

NOT DISTRIBUTED. On 18 October the owner explicitly requested uploading build 19 for testing after being informed of the remaining gates. A build-specific **upload-only** authorization now permits staging the binary in App Store Connect, with the non-exempt encryption flag unchanged. This is not tester availability or security acceptance. The default distribution gate remains closed. See `Config/SecurityReleaseGate.json` and [protocol/persistence design](FORWARD-SECRECY-2026-10-18.md).

Changes prepared together: exclusive Olm protocol 4, authenticated one-time bootstrap keys, durable retry/inbound journals, receiver-owned consent, inbox cursor pagination, sender/device capacity limits, stable packet IDs, Retry-After backoff, optional neutral push, clear device-loss guidance, and matching privacy notices. Relay 0.3 is required. Existing device identities and verified SC3 keys are preserved; no paid-branch source is overwritten.

Before distribution: complete independent integration review, physical two-device restart/offline/attachment test, updated Apple encryption declaration and privacy metadata, final Linux relay image/scan, coordinated receiver-consent/Olm rollout, protected push-worker deployment and real-device push acceptance. Monitor alerts currently exist on-host only; external operator notifications are not configured. No high-sensitivity or public security approval is given.

## Actual upload attempt, 18 October 2026

The Release archive and App Store export succeeded. Exported version/build/bundle, strict code signing, production APNs entitlement, App Store provisioning, non-exempt encryption=true and absence of any fabricated export code were verified. The compiled app and crypto sources are unchanged from the recorded 179 passing native tests.

Apple rejected the upload with ContentDelivery error **90592, Invalid Export Compliance Code**: the absent key is rendered as `[]` in its diagnostic. Inspection of the actual upload payload confirms that Xcode did not insert an empty `ITSEncryptionExportComplianceCode` field. No successful upload or installable TestFlight build 19 is claimed. The valid Apple-issued code/documentation remains outstanding; do not retry by asserting no encryption, reusing another app's code or changing intended countries. Existing build 18 and the compatible production relay are unchanged.
