# miggu69.info catalogue addition - 18 October 2026

This is a **delta overlay**, not the full website generator. It was applied to the exact existing 9-app static website image `sha256:4ac4eb73251f175d6c83f61ebbd0f32af4ddc6452f345c0ebe1f90448869d51e`. It adds PrivateRoom and ParaRoam product, support and privacy pages, imagery and a separate stylesheet. Four existing indexes/sitemap were extended. Fifty other existing files remained byte-identical.

Both apps are explicitly beta/invitation products. No App Store purchase button or public TestFlight link is invented. ParaRoam CloudKit messaging is not described as end-to-end encrypted. PrivateRoom build 18 and unreleased build 19 are distinguished.

Production uses a dedicated internal Docker network and Caddy's narrow `miggu69.info` upstream. No public container port is required. Local paths in the compose file are operator examples, not a reusable public credential. All 66 final public files were fetched over HTTPS and matched the full local static snapshot; CSP headers were present. Responsive checks passed at 390 px with no broken images or horizontal overflow.

The delta manifest records the final public-file hashes. A complete editable static-site archive is preserved in the owner's 18 October delivery dossier. Do not regenerate the current site using an older six-app generator, and do not treat this overlay as a replacement for the complete existing site.
