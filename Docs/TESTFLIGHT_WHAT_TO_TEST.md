# TestFlight – What to Test

```text
Bitte testen:
1. Onboarding durchlaufen und Beta-Hinweis bestätigen.
2. Prüfen, dass die App mit „Chats“ startet und nur „Chats“, „Kontakte“ und „Einstellungen“ als Tabs zeigt.
3. Unter „Chats“ einen lokalen Chat anlegen, eine Nachricht senden, einen Entwurf stehen lassen und die App neu starten. Nachricht und Entwurf müssen erhalten bleiben.
4. Suche, Filter, ungelesene Markierung, Fixieren, Stummschalten und Archivieren testen.
5. Unter „Kontakte“ den Anzeigenamen ändern, den eigenen QR-Code neu laden und einen Kontakt per QR importieren.
6. Auf zwei Geräten die gleiche Safety Number vergleichen, den Kontakt verifizieren und Nachrichten in beide Richtungen senden.
7. Unter „Einstellungen“ den Production Relay https://securechat.team mit dem separat bereitgestellten RELAY_AUTH_TOKEN aktivieren.
8. Unter „Einstellungen → Diagnose & Sicherheitsstatus“ Relay-Zustand, Inbox-Sync und Diagnosebericht prüfen.
9. Offline senden, Verbindung wiederherstellen und Zustellung/ACK kontrollieren.

Hinweis: Für den lokalen Chat ist kein zweites Gerät erforderlich. Für echte E2E-/Relay-Tests werden zwei Geräte und der separate RELAY_AUTH_TOKEN benötigt. Bitte keine Tokens, Safety Numbers oder Chat-Inhalte im Feedback posten.
```

# Reviewer Notes

```text
PrivateChat ist ein Production-Candidate für TestFlight. Die App nutzt lokale Keychain-Schlüssel, verschlüsselten lokalen Speicher und optional einen selbst betriebenen HTTPS-Relay. Der Relay kann keine Nachrichtenklartexte lesen.

Für Tests ohne zweites Gerät kann direkt unter „Chats“ ein lokaler Chat angelegt werden. Für echte Peer-Tests bitte SecureChat auf zwei Geräten installieren und Kontakte per QR-Code koppeln.

Kein Demo-Account erforderlich. Relay-Token wird nicht öffentlich bereitgestellt und wird nur für interne TestFlight-Tester verteilt.
```
