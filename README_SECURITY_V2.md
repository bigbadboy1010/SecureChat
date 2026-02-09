# BIT Chat – Security (Protocol v2)

## Status (Step 2)
This build enables **Protocol v2 (hard break)** with **Full Double Ratchet (DH-ratchet)** for private chats.

## Crypto in v2 (current)
- X25519 key agreement (ephemeral session)
- Root key derived via HKDF-SHA256
- Full Double Ratchet (DH-ratchet): X25519 + HKDF-SHA256
- Per-message keys (symmetric ratchet) + skipped-key window
- AES-256-GCM with AAD binding (version + counter)

## Next steps (planned v2)
- Full Double Ratchet (DH-ratchet) for PCS
- Sender Keys for channels
- Argon2id for password channels (memory-hard)
- Message header v2 (routing-minimal metadata + strict AAD audit)


## Step 4
- Unprotected channels generate a random 32-byte channel key.
- QR invites may embed the channel key (base64) for one-scan secure join.
- Channel messages use Sender-Keys format v2 (0x52 + counter + AES-GCM) with AAD.


## Step 5
- Channel invites are one-time tokens with expiry (default 10 minutes) to reduce key replays.
- Channel Sender-Keys packet upgraded to v3 header: counter + timestamp + messageId, bound via AAD.


## Step 6
- Optional passphrase-wrap for embedded channel keys in QR invites (MemoryHardKDF + AES-GCM + AAD).
- Replay protection for channel messages via msgId cache per sender/channel.
