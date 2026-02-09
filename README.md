# SecureChat ("BIT Chat")

**BIT Chat** is an iOS/macOS SwiftUI chat app focused on **privacy**, **local-first communication**, and a **security-first UX**.

It is designed for nearby communication using a **Bluetooth mesh** (store-and-forward) and end-to-end encryption for private chats.

> App name in Info.plist: **BIT Chat**

---

## What this project does

- **Nearby / offline-ish messaging** via **Bluetooth mesh** (CoreBluetooth)
  - peer discovery + relaying (store-and-forward) for longer distance / multi-hop delivery
- **End-to-end encryption** for private chats using a **Double Ratchet** (Protocol v2 hard break)
- **QR code invites** for joining channels / exchanging minimal invite metadata
- **Local app protection** (Face ID / Touch ID) for protecting chats on the device
- Security UX helpers (“Security Copilot”) explaining fingerprints/verification, QR invites, biometrics, etc.

---

## Crypto (current)

Private chats are using a **full Double Ratchet (DH-ratchet)** implementation.
A short summary (see also `README_SECURITY_V2.md`):

- X25519 key agreement
- HKDF-SHA256 for root/chain/message keys
- Per-message keys + skipped-key window (out-of-order handling)
- AES-256-GCM with AAD binding

See:
- `README_SECURITY_V2.md`
- `SecureChat/BIT/Crypto/DoubleRatchet.swift`
- `SecureChat/BIT/Services/EncryptionService.swift`

---

## Permissions / platform capabilities

This app uses:

- **Bluetooth** (mesh networking)
- **Local Network** (peer discovery / transport helpers)
- **Camera** (QR invite scanning)
- **Biometrics** (Face ID / Touch ID) for local unlock

Permission strings live in:
- `Config/Info.plist`

---

## Project structure (high level)

- `SecureChat.xcodeproj/` – Xcode project
- `SecureChat/BIT/` – main app source
  - `Services/` – Bluetooth mesh, encryption, delivery tracking, security insights
  - `Crypto/` – Double Ratchet and related crypto utilities
  - `Views/` + `ViewModels/` – SwiftUI UI layer
  - `Models/` + `Protocols/` – packet formats / protocol types
- `Config/` – app configuration (Info.plist)
- `Tests/` – unit tests

---

## Build & run

1. Open `SecureChat.xcodeproj` in Xcode.
2. Select an iOS simulator/device target (or macOS if configured).
3. Build & run.

Notes:
- Bluetooth features require a real device for full testing.
- This repository is synced from local Xcode sources; review settings/targets as needed.

---

## Security notes / disclaimer

This project is security-focused, but **security is a process**.
Before relying on it for real-world sensitive use:

- review crypto implementation and threat model
- run your own audits and tests
- avoid shipping secrets in the repo

---

## License

Some files include an Unlicense/public-domain header.
If you want a single, repo-wide license statement, add a top-level `LICENSE` file.
