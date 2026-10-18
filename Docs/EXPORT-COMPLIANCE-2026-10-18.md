# Encryption declaration - candidate 1.5.2 (19)

Status: technical dossier prepared; not a government approval, signed filing, Apple export-compliance code or legal classification. No new build has been uploaded. Build 18's OS-only answer must not be reused for build 19. The owner has instructed that all declarations be completed accurately before publication.

## Factual answers supported by this source tree

- Product: PrivateRoom (technical repository/app binary name SecureChat / PrivateChat), iPhone and iPad, bundle `org.francois.PrivateChat`.
- Encryption: **yes**. Confidential private communications and protected local storage are core functions. It is not merely HTTPS, authentication, signature verification, copyright protection, medical or banking functionality.
- External implementations of published standard algorithms: **yes**. The app statically links vodozemac 0.11.1 and its pinned Rust cryptographic dependencies. It therefore does not qualify as "Apple operating system encryption only".
- New traffic uses the published Olm 1:1 Double Ratchet protocol, not a proprietary primitive. It is wrapped in an application-specific, signed protocol-4 envelope. This must be disclosed; the app must not be described as an unmodified or Signal-interoperable implementation. No proprietary secret cipher algorithm is asserted.
- External primitives in the used Olm session: X25519 (32-byte keys), AES-256-CBC, HMAC-SHA-256 (256-bit MAC key; Olm v1 transmits an 8-byte truncated tag), HKDF-SHA-256 and SHA-256. Every complete envelope is additionally authenticated by a 64-byte Ed25519 signature through Apple's CryptoKit, checked before Olm processing.
- Apple CryptoKit also provides AES-GCM with 256-bit keys for local protected state/history/attachments, SHA-256 and existing device X25519/Ed25519 keys. Legacy cryptographic helpers remain in the source tree but are not a network fallback for the new client. URLSession provides HTTPS/TLS; negotiated TLS suites are OS-dependent.
- The relay receives public identity/one-time keys, signed routing metadata and encrypted packets. It receives no account/session/one-time private key or content decryption key. The operator controls beta admission and can revoke access, not decrypt client content.
- APNs provider authentication uses ES256 / P-256 on the server, outside the app binary. Optional notifications contain only a constant neutral alert. This is distinct from message encryption.
- `ITSAppUsesNonExemptEncryption` is **true**. No `ITSEncryptionExportComplianceCode` is invented or added before Apple issues one.

## Required process and unresolved evidence

Apple's current table requires a French encryption declaration when externally implemented standard encryption is distributed on the French App Store. The owner has not supplied an existing ANSSI receipt/approval. Keep the intended release countries unchanged; do not answer "no France" solely to bypass the requirement. The actual questionnaire and any requested U.S. BIS classification/self-classification obligations must be resolved for this specific product and distributor. This document does not assign an unverified ECCN or claim an exemption/CCATS.

The ANSSI procedure currently uses [Démarche numérique](https://demarche.numerique.gouv.fr/commencer/declaration-relative-a-un-moyen-de-cryptologie). It requires an authenticated declarant account; its public checklist requests an organization presentation/registration equivalent, product brochure, technical brochure and any available user/administrator guides. The operator is an Austrian individual software developer according to the public imprint, with no commercial-register number asserted. The appropriate supporting identity/registration document for that legal situation must be established rather than invented.

Before filing: confirm the declarant's legal capacity and required evidence; use the prepared technical dossier and existing user/operator guides; record the actual filing receipt/reference. A filing receipt must not be represented as product security certification. Upload the actual document requested by Apple and wait for Apple's determination. A self-authored technical brochure is not a substitute for an ANSSI declaration receipt.

## Official references checked 18 October 2026

- [Apple: export compliance overview](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)
- [Apple: required encryption documentation](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/)
- [Apple: determine and upload documentation](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation/)
- [ANSSI: current declaration procedure](https://cyber.gouv.fr/reglementation/reglementation-identite-confiance-numerique/controles-reglementaires-cryptographie/controle-moyen-de-cryptologie/controle-reglementaire-cryptographie-formulaires/)
- [Published Olm specification](https://spec.matrix.org/latest/olm/)
- [Pinned implementation source](https://github.com/matrix-org/vodozemac/tree/v0.11.1)

Tester distribution/release remains blocked by the unresolved declaration and security acceptance gates in `Config/SecurityReleaseGate.json`. A later explicit owner request authorizes uploading candidate 19 to Apple only, with `ITSAppUsesNonExemptEncryption=true`, no invented exemption/code/document and no assertion that it is installable. Apple documents a distinct Missing Compliance state after upload.

## Actual App Store Connect questionnaire evidence

On 18 October 2026, the app-level upload flow was opened for this app. Its purpose field described Olm messaging/local encryption. Only the externally implemented standard algorithm checkbox was selected. With France = yes, step 3 explicitly required **French encryption declaration approval** and a file attachment. No existing approval was available, so the incomplete form was cancelled without saving or uploading a substitute. The owner was asked whether an authenticated ANSSI/Démarche numérique account exists. No country was removed, no approval code entered and no declaration marked complete.

The owner subsequently created their own government account and authenticated. The authenticated draft is saved with seven algorithm entries and five supporting documents. It is not submitted or approved: the owner will personally date/sign the official attestation. The technical PDF is supporting material, not the required French approval document. The intended market date supplied by the owner is 1 December 2026, explicitly prospective.

## Blank official form checked

The current public seven-page blank ANSSI form explicitly offers **personne physique / particulier** and **personne morale** paths. Its company-presentation and recent K-bis/equivalent requirements are explicitly scoped to legal entities; do not invent a company registration or request one from an individual solely because the broad landing-page checklist lists it. The individual path asks for the actual legal name, nationality, address and contacts. Nationality is not inferred from residence or language. The form also requests a product description, algorithms/key sizes/modes, product and technical brochures, available guides and an attestation concerning the submitted information. The owner must verify their own identity/legal capacity and the actual attestation before formal submission. No attestation has been signed or filed. Private declarant details and the prefilled documents remain outside this public repository.
