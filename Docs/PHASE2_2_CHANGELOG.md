# PrivateChat Phase 2.2 Changelog

## Zweck

Phase 2.2 behebt die auf echtem iPhone sichtbare Meldung `Transport ist nicht verfügbar` durch eindeutigere Transportdiagnose und iPhone-sichere Relay-Konfiguration.

## Änderungen

- Relay-Transport validiert jetzt spezifisch:
  - Relay deaktiviert
  - Relay nicht konfiguriert
  - ungültige URL
  - `localhost`/`127.0.0.1` auf echtem iPhone
  - HTTP-Statusfehler vom Relay
- `TransportCoordinator` wirft bei `localOnly` jetzt `localTransportUnavailable` statt generischem `transportUnavailable`.
- Settings UI ergänzt:
  - `Relay prüfen`
  - Statusanzeige `Nur lokal` / `Relay fehlt` / `Relay aktiv`
  - iPhone-Hinweis: Mac-WLAN-IP statt localhost verwenden
- `Relay speichern` aktiviert den Relay-Modus automatisch, sobald eine URL eingetragen ist.
- `RelayTransport.checkHealth()` ruft `/health` auf und erwartet `{ "status": "ok" }`.

## Erwarteter iPhone-Setup

1. Relay am Mac starten:

```bash
cd ~/Desktop/Xcode/SecureChat/RelayServer
npm install
npm run dev
```

2. Mac-IP ermitteln:

```bash
ipconfig getifaddr en0
```

3. In der App unter `Security > Transport` eintragen:

```text
http://<MAC-WLAN-IP>:8080
```

4. `Relay speichern` drücken.
5. `Relay prüfen` drücken.
