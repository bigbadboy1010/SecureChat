# Relay Phase 3 Testablauf

## Server starten

```bash
cd ~/Desktop/Xcode/SecureChat/RelayServer
npm install
npm run dev
```

## iPhone-Konfiguration

In der App:

```text
Security > Transport
```

Relay-URL:

```text
http://192.168.178.229:8080
```

Danach:

```text
Relay speichern > Relay prüfen
```

## Erwartetes Verhalten

- `Relay erreichbar` erscheint.
- Nachrichten werden als `sent to relay` markiert.
- Empfänger holt Nachrichten automatisch per Auto-Polling ab.
- Abgeholte Relay-Pakete werden per ACK bestätigt.
- Wiederholte ACKs erzeugen keinen HTTP-500-Fehler mehr.
- Fehlgeschlagene Outbox-Nachrichten werden automatisch erneut versucht, sofern die Option aktiviert ist.

## Falls weiterhin DELETE/ACK-Fehler erscheinen

1. Laufenden Relay stoppen:

```bash
CTRL + C
```

2. Sicherstellen, dass der neue Relay-Server aus Phase 3 läuft:

```bash
cd ~/Desktop/Xcode/SecureChat/RelayServer
npm install
npm run dev
```

3. Nicht nur die iOS-App ersetzen, sondern auch den Ordner `RelayServer` aus dem ZIP übernehmen.
