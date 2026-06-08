# 🔐 SecureChat ("BIT Chat")

<p align="center">
  <img src="SecureChat/schat/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png" width="120" alt="SecureChat Icon">
</p>

<p align="center">
  <strong>iOS/macOS SwiftUI Messenger with E2E Encryption & Bluetooth Mesh</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#security">Security</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#installation">Installation</a> •
  <a href="#screenshots">Screenshots</a> •
  <a href="#roadmap">Roadmap</a>
</p>

---

## ✨ Features

### 🔒 Privacy-First Messaging
- **End-to-End Encryption** using Double Ratchet (X25519 + HKDF-SHA256 + AES-256-GCM)
- **Local Identity** based on Curve25519 signing keys
- **Peer ID** derived from SHA-256 of public key
- **Safety Numbers** for fingerprint verification

### 📡 Communication Modes
- **Bluetooth Mesh** (CoreBluetooth) - store-and-forward relay
- **Local Network** - peer discovery via MultipeerConnectivity
- **Relay Server** - optional encrypted packet upload
- **QR Code Invites** - easy channel joining

### 🛡️ Security Features
- **Biometric Authentication** (Face ID / Touch ID)
- **Trust States**: unverified → verified → blocked
- **Encrypted Local Store** (AES-GCM)
- **Keychain Storage** for keys and trust state
- **Message Padding** and Bloom Filters
- **Password-Protected Channels**
- **Security Copilot** - explains fingerprints, QR invites, biometrics

### 📱 Platform
- **iOS 16+** / **macOS 13+**
- **SwiftUI** with modern design
- **Watch App** companion
- **Widgets** support

---

## 🔐 Security Architecture

### Double Ratchet Implementation
```
X25519 Key Agreement
    ↓
HKDF-SHA256 (Root/Chain/Message Keys)
    ↓
AES-256-GCM with AAD binding
    ↓
Per-message keys + skipped-key window
```

### Key Components
- **IdentityManager** - Curve25519 key generation and storage
- **CryptoService** - Encryption/decryption operations
- **KeychainStore** - Secure key storage in iOS Keychain
- **PeerTrustStore** - Trust state management
- **DoubleRatchet** - Forward secrecy and future secrecy

See [README_SECURITY_V2.md](README_SECURITY_V2.md) for full details.

---

## 🏗️ Architecture

```
SecureChat/
├── 📱 iOS App (PrivateChat/)
│   ├── App/                    # App entry points
│   ├── Core/
│   │   ├── Security/           # Crypto, Identity, Keychain
│   │   ├── Transport/          # Relay, Local, Bluetooth
│   │   ├── Persistence/        # Encrypted stores
│   │   └── Models/             # Chat models
│   ├── Features/
│   │   ├── Chat/               # Chat UI
│   │   ├── Pairing/            # QR pairing
│   │   └── Settings/           # App settings
│   └── Features/Shared/        # Design system
│
├── 🖥️ Relay Server (RelayServer/)
│   ├── Node.js/TypeScript
│   ├── Docker support
│   └── Caddy reverse proxy
│
├── 🧪 Tests/
│   ├── Unit Tests
│   ├── Integration Tests
│   └── Security Tests
│
└── 📚 LegacyReference/         # Original BIT codebase
```

---

## 📲 Installation

### iOS App
1. Clone the repository
2. Open `PrivateChat.xcodeproj` in Xcode 15+
3. Select your team in Signing & Capabilities
4. Build & run on device (Bluetooth requires real device)

### Relay Server
```bash
cd RelayServer
cp .env.example .env
# Edit .env with your settings
docker compose up -d
```

See [RelayServer/README.md](RelayServer/README.md) for details.

---

## 📸 Screenshots

*Coming soon - App Store screenshots*

---

## 🗺️ Roadmap

See [Docs/SECURITY_ROADMAP.md](Docs/SECURITY_ROADMAP.md) for full roadmap.

### Phase 1 ✅ (Completed)
- [x] Basic E2E encryption
- [x] Bluetooth mesh
- [x] QR pairing
- [x] Biometric auth

### Phase 2 ✅ (Completed)
- [x] Double Ratchet v2
- [x] Relay server
- [x] Message padding
- [x] Bloom filters

### Phase 3 🚧 (In Progress)
- [ ] Group chats
- [ ] File sharing
- [ ] Voice messages
- [ ] Cross-platform sync

### Phase 4 📅 (Planned)
- [ ] Desktop app (macOS)
- [ ] Web client
- [ ] Federation
- [ ] Audits

---

## 🧪 Testing

```bash
# Run all tests
xcodebuild test -project PrivateChat.xcodeproj -scheme PrivateChat

# Run specific test suite
xcodebuild test -project PrivateChat.xcodeproj -scheme PrivateChat -only-testing:PrivateChatTests
```

---

## 📄 License

Some files include an Unlicense/public-domain header.
This project is open source - see individual file headers.

---

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 🙏 Acknowledgments

- [Signal Protocol](https://signal.org/docs/) for the Double Ratchet inspiration
- [libsodium](https://libsodium.gitbook.io/doc/) for crypto primitives
- Apple for CoreBluetooth and CryptoKit

---

<p align="center">
  <strong>🔐 Privacy is a right, not a privilege 🔐</strong>
</p>
