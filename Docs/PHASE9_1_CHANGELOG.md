# PrivateChat Phase 9.1

Phase 9.1 stabilisiert das Verhalten bei temporär nicht erreichbarem lokalen Relay.

## Hintergrund

Ein einzelner `NSURLErrorDomain Code=-1004` bedeutet, dass das iPhone den Relay-Host kurzfristig nicht erreichen konnte. Typische Ursachen sind: Relay-Prozess gestoppt, Mac im Ruhezustand, Firewall, VPN/utun-Routing oder WLAN-Wechsel. Die App soll solche Aussetzer nicht als dauerhaften Fehler behandeln.

## Änderungen

- Relay-Connectivity-State in der App:
  - stabil
  - instabil
  - pausiert
- Automatischer Backoff bei transienten Relay-Fehlern:
  - Timeout
  - keine Netzwerkverbindung
  - cannot connect to host
  - network connection lost
- Auto-Sync erzeugt bei transientem Relay-Ausfall kein permanentes Fehler-Popup mehr.
- Manuelle Aktionen zeigen weiterhin konkrete Fehler.
- Health-Check setzt den Backoff bei Erfolg zurück.
- Erfolgreiche Relay-Aktionen setzen den Verbindungsstatus wieder auf stabil.
- Settings zeigen Relay-Verbindungsstatus, Fehlerfolge und Rest-Pausenzeit.
- Dashboard zeigt Relay-Verbindungsstatus in der Aktivitätskarte.
- Neuer Button: Relay-Backoff zurücksetzen.
- Diagnosebericht enthält Relay-Verbindungsstatus und Fehlerfolge.

## Kompatibilität

- Keine Relay-API-Änderung.
- Keine Transport-Payload-Änderung.
- Keine Breaking Changes im lokalen Store.
