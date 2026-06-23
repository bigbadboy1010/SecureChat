# 🔐 SecureChat

> **End-to-end encrypted messaging for iOS** — built with Swift, secured by Curve25519 & AES-GCM, relayed by a hardened TypeScript/Fastify blind relay.

**Status:** Public Beta ⚠️ — external security audit still recommended before high-assurance claims. See [`KNOWN_ISSUES`](https://securechat.team/known-issues.html) for the open gaps and [`SECURITY.md`](SECURITY.md) for the coordinated-disclosure policy.

> **Note on the legacy name `PrivateChat`:** the bundle identifier, code target, and the source tree still use the original `PrivateChat` (and `org.francois.PrivateChat`) names — they are internal and not user-visible. The product name is **SecureChat**. The Code-Signing & Distribution scripts (`build-host-app.sh`, `build-and-upload-testflight.sh`) and the App-Store-Connect entry already use `org.francois.PrivateChat` and the `SecureChat` display name side by side. Do not rename the bundle without re-registering the App-Store-Connect entry; the relay URLs and the `CURRENT-ENDPOINTS.md` source of truth depend on the existing name.

---

## 📖 Project Overview

SecureChat (legacy code name `PrivateChat`) is a privacy-first iOS messenger built from the ground up with end-to-end encryption at its core. It is designed as a **hardened, production-oriented baseline** for secure messaging, not as a feature-complete consumer app.

The project follows a phased development approach (currently at **Phase 14.6.2**), with each phase adding hardening, UX improvements, or security features while keeping the core cryptographic layer stable.

### Key Design Principles

- **Zero-knowledge relay** — the relay server never sees plaintext, keys, or decrypted payloads.
- **Client-side cryptography** — all encryption/decryption happens on-device using Apple's CryptoKit.
- **No phone number required** — identity is based on Curve25519 keypairs, not phone numbers or email.
- **Local-first data** — messages are stored encrypted locally; iCloud backup is explicitly excluded for sensitive stores.
- **Trust, but verify** — manual Safety Number verification workflow for peer identity confirmation.

---

## ✨ Features

### Core Messaging
- 🔐 **End-to-end encryption** using Curve25519 key agreement + AES-GCM
- 📝 **Encrypted local persistence** — messages and drafts stored with AES-GCM, keys in iOS Keychain
- 🔑 **Curve25519 identity keys** — signing + key agreement keypairs per device
- 🛡️ **Safety Number verification** — manual fingerprint comparison for out-of-band trust establishment
- 🔄 **Relay transport** — encrypted packet dropbox for offline/remote messaging
- 📬 **Delivery receipts & ACK tombstones** — reliable delivery tracking with deduplication
- 🔍 **Chat search, drafts, export** — local-only, encrypted-at-rest

### Security & Privacy
- 🔒 **Biometric app lock** — Face ID / Touch ID gate with device-owner authentication
- 🚫 **Screenshot/Preview protection** — optional chat-list preview masking
- ⌨️ **Privacy composer** — reduced keyboard suggestions to minimize system-side leakage
- 🏃 **Runtime security** — debug/simulator/jailbreak/injection detection with optional relay blocking
- 🤖 **Privacy Sentinel** — on-device security scoring (0–100) with typed findings and recommendations; rule-based, fully local, no telemetry, no ML model (see [ADR-004](Docs/ADR-004-security-sentinel.md))
- 📋 **Diagnostics reports** — technical summary without chat plaintext, shareable for support
- 🧹 **Local retention cleanup** — manual purge controls for messages and relay ledger

### UI / UX (Phase 14)
- 🎨 **Modern glass-card design system** — professional iOS 16+ UI
- 📊 **Command Center Dashboard** — relay stats, security score, privacy status at a glance
- 💬 **Refined chat bubbles** — with message actions, quick reply, editing history
- 📌 **Pinned & archived chats** — with unread counters
- 🔗 **QR pairing** — scan or share pairing codes for contact discovery
- 🗂️ **Chat organization** — searchable list, chat details, local rename, mute

### Relay Server
- 🐳 **Dockerized Fastify backend** with TypeScript
- 🔒 **Bearer-token auth** — separate client (`RELAY_AUTH_TOKEN`) and admin (`RELAY_ADMIN_TOKEN`) tokens
- 🛡️ **Production hardening** — HTTPS enforcement, rate limiting, clock-skew validation, sanitized audit logs
- 📦 **File-backed persistence** — `STORE_TYPE=file` with TTL and size limits
- 🧹 **Admin-only purge** — clients cannot purge inboxes in production
- 📊 **Public stats endpoint** — unauthenticated aggregate counters (v1 / v2 envelope request split, v2 health, packet totals); admin `/v1/admin/relay/stats` adds per-peer detail (see [`CURRENT-ENDPOINTS.md`](Docs/CURRENT-ENDPOINTS.md))

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         iOS Client (Swift)                       │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │   UI Layer  │  │  App Layer   │  │    Security Layer    │  │
│  │ (SwiftUI)   │  │ (Services)   │  │ (CryptoKit + Keychain)│  │
│  └──────┬──────┘  └──────┬───────┘  └──────────┬───────────┘  │
│         │                │                      │              │
│  ┌──────▼──────┐  ┌──────▼───────┐  ┌───────────▼───────────┐  │
│  │  Features   │  │   Core       │  │    Persistence        │  │
│  │ Chat/Pairing│  │ Models/Sec   │  │ EncryptedMessageStore │  │
│  │ Settings    │  │ Transport    │  │ EncryptedDraftStore   │  │
│  └─────────────┘  └──────┬───────┘  │ RelayPacketLedgerStore│  │
│                          │           └───────────────────────┘  │
└──────────────────────────┼──────────────────────────────────────┘
                           │
                           ▼ HTTPS / WSS
┌─────────────────────────────────────────────────────────────────┐
│                      Relay Server (TypeScript/Fastify)           │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │   Health    │  │  /v1/relay/* │  │    /v1/admin/*      │  │
│  │   (public)  │  │ (client auth)│  │  (admin auth)       │  │
│  └─────────────┘  └──────────────┘  └──────────────────────┘  │
│                              │                                  │
│                    ┌─────────▼──────────┐                      │
│                    │   File Store (WAL)   │                      │
│                    │   /data (Docker vol) │                      │
│                    └─────────────────────┘                      │
└─────────────────────────────────────────────────────────────────┘
```

### Client Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI (iOS 16+) |
| Crypto | Apple CryptoKit (Curve25519, AES-GCM, Ed25519) |
| Keys | iOS Keychain |
| Persistence | Encrypted file stores (AES-GCM), WAL mode |
| Transport | URLSession → Relay HTTPS |
| Language | Swift |
| IDE | Xcode |

### Relay Stack

| Layer | Technology |
|-------|-----------|
| Runtime | Node.js + Fastify |
| Language | TypeScript |
| Auth | Bearer token (constant-time comparison) |
| Store | File-backed (production) / In-memory (dev) |
| Container | Docker + Docker Compose |
| Reverse Proxy | Caddy (HTTPS, auto-certs) |
| Host | Linux VPS (production) |

---

## 🔐 Security Features

### Cryptography
- **Identity**: Curve25519 keypair (signing + key agreement) per device
- **Peer ID**: SHA-256 of signing public key (64 hex chars)
- **Message encryption**: AES-GCM with authenticated additional data (AAD)
- **Packet signatures**: Ed25519 signatures over canonical envelope
- **Local storage**: AES-GCM encrypted stores, keys in Keychain
- **Password-channel KDF**: Custom memory-hard KDF (not Argon2id — documented honestly)

### Relay Security (Phase 13+)
- Separate client and admin bearer tokens
- Production fail-fast for missing auth / file-store / HTTPS
- Client purge disabled by default; admin-only purge endpoint
- Per-recipient packet cap + global packet cap
- Clock-skew validation (±5 min)
- Rate limiting per IP
- Sanitized audit logs (no query strings, no plaintext)
- Security headers (`no-store`, `X-Content-Type-Options`, etc.)
- Docker hardening: `read_only`, `no-new-privileges`, `cap_drop: ALL`

### App Runtime Security (Phase 11–12)
- Debugger / debug-build / simulator detection
- Jailbreak / injection indicator checks
- Optional relay transport blocking on critical runtime risks
- **Privacy Sentinel** — on-device rule-based security scoring (0–100) with typed findings and recommendations; fully local, deterministic, no ML model, no telemetry. See [`Docs/ADR-004-security-sentinel.md`](Docs/ADR-004-security-sentinel.md) for the canonical spec.
- Privacy composer to reduce iOS keyboard-side data exposure

### Privacy
- No advertising SDKs, trackers, or analytics third-parties
- Diagnostic reports contain NO chat plaintext, NO private keys, NO tokens
- Local stores excluded from iCloud backup
- Camera permission ONLY for QR pairing
- Biometric data never leaves Apple Secure Enclave

---

## 🚀 Setup Instructions

### Prerequisites
- macOS with Xcode 14+
- iOS 16+ device or simulator
- (Optional) Docker for relay server testing

### iOS App

1. Clone the repository:
   ```bash
   git clone https://github.com/bigbadboy1010/SecureChat.git
   cd SecureChat
   ```

2. Open in Xcode:
   ```bash
   open PrivateChat.xcodeproj
   ```

3. Select target `PrivateChat`

4. Configure signing:
   - Select your Team in Signing & Capabilities
   - Bundle ID: `org.francois.PrivateChat` (the team's registered identifier; for a private fork, use your own)

5. Build and run on iOS Simulator or physical device

### Relay Server (Local Testing)

```bash
cd RelayServer
cp .env.example .env
# Edit .env with your tokens and domain

docker compose up -d --build

# Verify (Sprint 14A: /healthz is the public healthcheck; /health is operator-only)
curl http://127.0.0.1:8080/healthz
```

### Production Relay Deployment

See [`RelayServer/README_PRODUCTION.md`](RelayServer/README_PRODUCTION.md) for:
- Recommended `.env` configuration
- Caddy reverse proxy setup
- Token generation (`openssl rand -base64 48`)
- Hardened Docker controls
- Admin API usage

Production relay: `https://relay.securechat.team` (marketing site at `https://securechat.team`)

---

## 📡 API Documentation

### Relay API (Client)

All client routes require `Authorization: Bearer <RELAY_AUTH_TOKEN>`.

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/healthz` | `GET` | Public health check (no auth). Returns `{status, uptimeSeconds, version}`. |
| `/healthz/internal` | `GET` | Operator-only health check. Requires `X-Securechat-Ops-Token`. Returns store type, max packet bytes, max TTL, etc. |
| `/v1/relay/security/policy` | `GET` | Current relay policy metadata |
| `/v1/relay/messages` | `POST` | Store encrypted packet (peer-bound signature recommended) |
| `/v1/relay/messages` | `GET` | Fetch inbox for recipient (peer-bound signature recommended) |
| `/v1/relay/messages/:id` | `DELETE` | Delete specific packet (recipient-only) |
| `/v1/relay/stats` | `GET` | Public aggregate counters (v1 / v2 envelope request split, first / last v2 timestamp). |
| `/v1/relay/v2-health` | `GET` | Public v2-envelope health dashboard (`ready` flag, `v2SharePercent`, `warnings[]`). |

#### Store Packet (POST)

```json
POST /v1/relay/messages
Content-Type: application/json
Authorization: Bearer <token>

{
  "protocolVersion": 2,
  "id": "uuid-v4",
  "senderID": "64-hex-chars",
  "recipientID": "64-hex-chars",
  "sealedPayloadBase64": "base64-aes-gcm-payload",
  "signatureBase64": "base64-ed25519-signature",
  "createdAt": "2026-06-12T12:00:00Z",
  "expiresAt": "2026-06-13T12:00:00Z"
}
```

Response `202`:
```json
{
  "accepted": true,
  "packetID": "uuid-v4"
}
```

#### Fetch Inbox (GET)

```
GET /v1/relay/messages?recipientID=<64-hex>&limit=50
Authorization: Bearer <token>
```

Response:
```json
{
  "packets": [...]
}
```

#### Delete Packet (DELETE)

```
DELETE /v1/relay/messages/:packetID
Authorization: Bearer <token>
```

### Relay API (Admin)

Requires `Authorization: Bearer <RELAY_ADMIN_TOKEN>`.

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/v1/admin/relay/stats` | `GET` | Relay statistics |
| `/v1/admin/relay/messages/purge` | `POST` | Admin-only inbox purge |

**Note:** `RELAY_ADMIN_TOKEN` must NEVER be embedded in the iOS app.

### Full API Contract

See [`Docs/RELAY_API_CONTRACT.md`](Docs/RELAY_API_CONTRACT.md)

---

## 📂 Project Structure

```
SecureChat/
├── PrivateChat/               # Active iOS app target (Swift)
│   ├── App/                   # App entry, container, device info
│   ├── Core/
│   │   ├── Models/            # Chat models, production profile
│   │   ├── Security/          # Identity, crypto, keychain, trust store
│   │   ├── Persistence/       # Encrypted stores (messages, drafts, ledger)
│   │   ├── Services/          # Conversation, biometric gate
│   │   └── Transport/         # Relay transport, local transport, models
│   ├── Features/
│   │   ├── Chat/              # Chat views, dashboard, conversation list
│   │   ├── Pairing/           # QR pairing, manual pairing
│   │   ├── Settings/          # Settings, privacy policy, support
│   │   ├── Onboarding/        # Onboarding flow
│   │   └── Shared/            # Shared UI components
│   ├── Assets.xcassets/       # App icons (universal + macOS sizes)
│   └── PrivacyInfo.xcprivacy  # Apple privacy manifest
├── RelayServer/               # TypeScript/Fastify relay backend
│   ├── src/                   # Server source
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── Caddyfile
│   └── README_PRODUCTION.md
├── Docs/                      # Changelogs, privacy policy, API docs, roadmap
├── Tests/                     # Unit tests (PrivateChatTests target)
├── Config/                    # Info.plist
└── README.md                  # This file
```

---

## 🗺️ Development Phases

| Phase | Focus |
|-------|-------|
| 1 | Stabilized baseline, identity, encrypted store |
| 2 | QR pairing, Safety Number, relay transport scaffold |
| 3–5 | Relay ACKs, delivery receipts, deduplication, stats |
| 6–7 | Messenger UI: chat list, bubbles, search, pinned |
| 8 | Chat search, drafts, export, relay ledger maintenance |
| 9 | Privacy composer, preview protection, diagnostics, backoff |
| 10 | Production relay: Docker, Caddy, HTTPS, bearer auth |
| 11 | App hardening: runtime integrity checks |
| 12 | Security Sentinel: local AI security scoring |
| 13 | Relay hardening: production fail-fast, rate limits, sanitized logs |
| 14 | Professional UI refresh: glass cards, Command Center, refined composer |
| 14.1–14.6 | Security UX calibration, App Store cleanup, encrypted drafts, tests |

See `Docs/PHASE*_CHANGELOG.md` for detailed per-phase notes.

---

## 🧪 Testing

The `PrivateChatTests` target is present but still being expanded. Required before strong production claims:

- [ ] `PrivateChat/Core/Security` unit tests
- [ ] `PrivateChat/Core/Transport` tests
- [ ] Encrypted store migration tests
- [ ] Relay configuration migration tests
- [ ] External security audit

Run existing tests:
```bash
# In Xcode: Cmd+U with PrivateChatTests target selected
```

---

## ⚠️ Production Caveats

- **Not independently audited** — suitable for moderate-risk messaging, not yet for high-sensitivity use.
- **Custom KDF** — the password-channel KDF is documented as custom memory-hard, not Argon2id. Do not market as formally reviewed password hashing.
- **No Double Ratchet yet** — the legacy Double Ratchet exists in history but is not integrated into the active `PrivateChat` target.
- **No group sender keys yet** — group messaging is on the roadmap but not implemented in the active target.
- **Test on physical hardware** — simulator behavior differs for keychain, biometric, and runtime security.

---

## 📄 License & Legal

- Privacy Policy: [`Docs/PRIVACY_POLICY.md`](Docs/PRIVACY_POLICY.md)
- App Store Connect: Privacy Policy URL must be publicly reachable HTTPS
- Export compliance must be reviewed for App Store submission
- No analytics SDKs or trackers are integrated

---

## 🤝 Contributing & Support

- See [`Docs/SUPPORT_AND_FEEDBACK.md`](Docs/SUPPORT_AND_FEEDBACK.md)
- Security roadmap: [`Docs/SECURITY_ROADMAP.md`](Docs/SECURITY_ROADMAP.md)
- For security issues, please report via the app's diagnostic report or contact channels

---

## 🔗 Links

- **Repository:** https://github.com/bigbadboy1010/SecureChat
- **Marketing site:** https://securechat.team
- **Production Relay:** https://relay.securechat.team
- **Relay Docs:** [`RelayServer/README_PRODUCTION.md`](RelayServer/README_PRODUCTION.md)

---

*Built with ❤️ for privacy by default.*
