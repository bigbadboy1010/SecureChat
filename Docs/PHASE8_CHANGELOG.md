# PrivateChat Phase 8

Phase 8 baut auf dem stabilen Phase-7-Relay auf und verbessert Produktreife, UI-Workflow und Betriebsruhe.

## UI / UX

- Chat-interne Suche über Nachrichtentext, Status und Message-ID.
- Persistente lokale Entwürfe pro Chat über `UserDefaults`.
- Composer zeigt an, wenn ein Entwurf lokal gespeichert wird.
- Entwurf kann direkt aus dem Composer gelöscht werden.
- Chat-Details enthalten Exportfunktionen:
  - Chat als Text teilen
  - Chat-Export in Zwischenablage kopieren
- Export enthält Chat-Titel, Chat-ID, Peer, Zeitstempel, Richtung, Status und Markierung.

## Relay / Diagnose

- Relay-Erfolgslogs sind standardmäßig deaktiviert.
- Fehler werden weiterhin geloggt.
- Neuer Schalter in `Security > Transport`: `Relay-Erfolgslogs anzeigen`.
- Das reduziert laufendes Log-Rauschen bei stabilem Auto-Polling.

## Lokale Wartung

- Neuer Bereich `Lokale Wartung` in den Einstellungen.
- Anzeige von lokalem Relay-Paket-Ledger und Receipt-Ledger.
- Lokales Relay-Ledger kann kompaktiert werden.
- Lokales Relay-Ledger kann für Tests gelöscht werden.

## Sicherheitshinweis

Chat-Export erzeugt Klartext nur nach expliziter Benutzeraktion. Der Export ist nicht automatisch verschlüsselt und sollte nur bewusst geteilt oder gespeichert werden.

## Kompatibilität

- Relay-Protokoll bleibt kompatibel zu Phase 7.
- Keine Änderung an Transport-Payload v3.
- Alte Einstellungen bleiben durch Default-Decoding kompatibel.
