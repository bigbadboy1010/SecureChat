# PrivateChat Tests

Phase 14.5 startet die Test-Migration von den alten, nicht aktiven `schatTests` zu echten `PrivateChatTests`.

Vorhanden:
- `PrivateChatTests/SecureChatProductionProfileTests.swift`
- `PrivateChatTests/EncryptedDraftStoreTests.swift`
- `PrivateChatTests/CryptoServiceTests.swift`
- `PrivateChatTests/EncryptedMessageStoreTests.swift`
- `PrivateChatTests/TestSupport.swift`
- `PrivateChatTests/IdentityManagerTests.swift`

Abgedeckt:
- Production-Relay-Migration und Token-Validation.
- EncryptedDraftStore Roundtrip, Delete und Legacy-Draft-Migration.
- CryptoService AES-GCM mit AAD, Tamper-Detection, Sign/Verify, Pairwise-Key-Determinismus, Peer-ID/Safety-Number-Stabilität.
- EncryptedMessageStore Roundtrip, fehlender Store, korrupter Store.
- IdentityManager Display-Name-Persistenz und PairingPayload-Export mit aktualisiertem Namen.

Nächste Test-Prioritäten:
- `ConversationServiceEnvelopeTests` für Outbound→Inbound Roundtrip mit Mock-Transport.
- `RelayTransportTests` für HTTP-Status-Mapping, 401/426/-1004.
- `SafetyNumberView` Snapshot/UI-State-Tests, sobald das UI-Testtarget ergänzt wird.
