# TestFlight – What to Test

```text
Bitte testen:
1. Onboarding durchlaufen und Beta-Hinweis bestätigen.
2. Display-Name im Pairing-Tab ändern und Pairing-Code neu laden.
3. Dashboard → Solo-Test-Chat anlegen und lokale verschlüsselte Speicherung prüfen.
4. Security → Transport: Production Relay https://chatsecure.ddns.net aktivieren und RELAY_AUTH_TOKEN eintragen.
5. Relay prüfen, Inbox abrufen und Diagnosebericht teilen/kopieren.
6. Pairing mit zweitem Gerät testen: QR scannen, Safety Number vergleichen, Kontakt verifizieren, Nachricht senden.
7. Chat-Details → Safety Number vergleichen: Gruppen aktiv bestätigen und Peer verifizieren.

Hinweis: Für Solo-Test ist kein zweites Gerät erforderlich. Für Relay-Tests wird der separate RELAY_AUTH_TOKEN benötigt. Bitte keine Tokens oder Chat-Inhalte im Feedback posten.
```

# Reviewer Notes

```text
PrivateChat ist ein Production-Candidate für TestFlight. Die App nutzt lokale Keychain-Schlüssel, verschlüsselten lokalen Speicher und optional einen selbst betriebenen HTTPS-Relay. Der Relay kann keine Nachrichtenklartexte lesen.

Für Tests ohne zweites Gerät gibt es im Dashboard einen Solo-Test-Modus. Für echte Peer-Tests bitte zwei Geräte installieren und Pairing per QR-Code durchführen.

Kein Demo-Account erforderlich. Relay-Token wird nicht öffentlich bereitgestellt und wird nur für interne TestFlight-Tester verteilt.
```
