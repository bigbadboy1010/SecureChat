# SecureChat Datenschutzrichtlinie

Stand: 2026-06-22

SecureChat ist ein Ende-zu-Ende-verschlüsselter Messenger für iOS. Die
App verwendet keine Werbe-SDKs, keine Tracker und keine
Analyse-Drittanbieter. Diese Richtlinie beschreibt, welche Daten die
App **lokal** speichert, welche Daten über den **Relay** laufen und
welche Daten der **Beta-Vertrieb** über TestFlight sieht.

## 1. Welche Daten lokal gespeichert werden

Nachrichteninhalte, Drafts und technische Chat-Metadaten werden lokal
im App-Container gespeichert. Nachrichten- und Draft-Stores sind
AES-GCM-verschlüsselt. Die zugehörigen Schlüssel liegen im iOS-Keychain.
Lokale Stores werden vom iCloud-Backup ausgeschlossen.

Private Schlüssel verlassen das Gerät nicht.

## 2. Welche Daten über den Relay laufen

Wenn der Relay-Modus aktiviert ist, überträgt die App verschlüsselte
Pakete an:

```text
https://relay.securechat.team
```

Der Relay verarbeitet **technische Zustellmetadaten** wie Sender-ID,
Empfänger-ID, Paket-ID, Ablaufzeit, ACKs und Zustellstatus. Der Relay
**kann Nachrichteninhalte nicht lesen** und nicht beweisen, dass ein
bestimmter Absender ein bestimmtes Paket geschickt hat — die
Signaturprüfung erfolgt auf dem Empfänger-Gerät (siehe
`Docs/ADR-002-envelope-and-crypto.md` für das Vertrauensmodell).

## 3. Pairing

Pairing-Codes enthalten öffentliche Identity-Keys, Anzeigename und
Erstellungszeitpunkt. Der lokale Anzeigename kann vom Nutzer geändert
werden und wird bei neu erzeugten Pairing-Codes als öffentlicher Name
geteilt.

## 4. Self-hosting

Nutzer können ihren eigenen Relay betreiben. Die offizielle
Self-host-Anleitung liegt unter
`https://securechat.team/docs/self-host.html` und in `Docs/`.
Ein Self-host-Relay erhält nur die Pakete, die seine Nutzer explizit
über ihn leiten.

## 5. TestFlight Beta (Public Beta Phase)

Während der TestFlight-Beta kann Apple dem Entwickler standardmäßige
TestFlight-Diagnostik anzeigen, zum Beispiel:

- Anzahl der TestFlight-Sessions
- App-Crashes
- Installationsdatum
- zuletzt installierte Build-Version
- Anzahl der aktiven Tester

Diese Daten werden von Apple erhoben, nicht von SecureChat. Sie sind
in Apples TestFlight-Bedingungen beschrieben (siehe
<https://developer.apple.com/testflight/>).

**SecureChat selbst enthält keine eigenen Analytics-, Tracking- oder
Crash-Reporting-SDKs.** Wir können von der App aus keine Crash-Reports,
Installation Events oder Nutzungsstatistiken einsehen.

## 6. App-Store-Verbindung

Die App nimmt im Betrieb keine Verbindungen zu Apple-Apple-Analytics,
Google-Analytics, Facebook-SDK, Adjust, Branch, AppsFlyer, Firebase,
Sentry oder vergleichbaren Diensten auf. Es gibt keine
Werbe-Identifikatoren, IDFA-Zugriffe oder Ad-Tracking-Frameworks.

## 7. Auskunftsrecht

Da wir lokal keine Nutzer-Accounts führen, gibt es auf unserer Seite
keine personenbezogenen Daten, die wir ausgeben könnten. Anfragen
richten Sie bitte an `privacy@securechat.team`.

## 8. Kontakt

- Privacy: privacy@securechat.team
- Security: security@securechat.team
- Allgemein: hello@securechat.team

PGP-Schlüssel für vertrauliche Anfragen sind in `SECURITY.md` gelistet
(siehe <https://github.com/bigbadboy1010/SecureChat/blob/main/SECURITY.md>).

## 9. Änderungen an dieser Richtlinie

Wir kennzeichnen jede Änderung mit Datum im Changelog
(`CHANGELOG.md`). Wesentliche Änderungen werden in der App und auf
der Website angekündigt.
