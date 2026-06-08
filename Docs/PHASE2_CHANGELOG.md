# PrivateChat Phase 2 Changelog

## Ziel

Phase 2 macht aus der stabilisierten Phase-1-Basis einen nutzbaren Secure-Messenger-Prototyp mit verifizierten Kontakten, QR-Pairing und aktivem Relay-Inbox-Flow.

## Implementiert

- QR-Code-Erzeugung für lokale Pairing Payloads.
- Kamera-basierter QR-Code-Scanner für Kontaktimport.
- Pairing-URI-Format `privatechat://pairing/<payload>`.
- Harte Trust-Regel: Nachrichten an Peers nur bei `verified`.
- Key-Rotation-Erkennung: geänderte Peer-Keys blockieren den Kontakt.
- Relay-Sendepfad auf ISO-8601-Date-Encoding korrigiert.
- Relay-Fetch via `GET /v1/relay/messages`.
- Relay-Acknowledge/Delete via `DELETE /v1/relay/messages/:packetID`.
- Eingehende Relay-Pakete werden nur verarbeitet, wenn der Sender verifiziert ist.
- Transport-Envelope wird mit Ed25519 signiert.
- Payload bleibt per X25519/HKDF/AES-GCM verschlüsselt.
- Lokales HTTP im Netzwerk für Entwicklungs-Relay erlaubt (`NSAllowsLocalNetworking`).
- Camera Permission für QR-Scanner ergänzt.

## Noch bewusst offen

- Kein Double Ratchet mit Forward Secrecy pro Nachricht.
- Kein automatisches Background Polling.
- Kein Push Notification Flow.
- Kein produktiver HTTPS/VPS-Deployment-Stack.
- Kein BLE/Multipeer-Reimport aus Legacy-Code.

## Bedienung

1. Gerät A: Pairing Tab öffnen und QR-Code anzeigen.
2. Gerät B: Pairing Tab öffnen, `QR scannen`, Kontakt importieren.
3. Beide Geräte Safety Number über zweiten Kanal vergleichen.
4. Kontakt manuell als `Verified` markieren.
5. In Settings `Relay erlaubt` aktivieren und lokale Relay-URL speichern.
6. Chat mit verifiziertem Peer erstellen.
7. Nachrichten senden.
8. Auf dem Empfänger `Inbox abrufen` verwenden.
