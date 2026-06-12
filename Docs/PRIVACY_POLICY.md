# PrivateChat / SecureChat Datenschutzrichtlinie

Stand: Phase 14.6.2

PrivateChat ist ein Ende-zu-Ende-verschlüsselter Messenger-Kern. Die App verwendet keine Werbe-SDKs, keine Tracker und keine Analyse-Drittanbieter.

## Welche Daten lokal gespeichert werden

Nachrichteninhalte, Drafts und technische Chat-Metadaten werden lokal im App-Container gespeichert. Nachrichten- und Draft-Stores sind AES-GCM-verschlüsselt. Die zugehörigen Schlüssel liegen im iOS-Keychain. Lokale Stores werden vom iCloud-Backup ausgeschlossen.

Private Schlüssel verlassen das Gerät nicht.

## Welche Daten über den Relay laufen

Wenn der Relay-Modus aktiviert ist, überträgt die App verschlüsselte Pakete an:

```text
https://chatsecure.ddns.net
```

Der Relay verarbeitet technische Zustellmetadaten wie Sender-ID, Empfänger-ID, Paket-ID, Ablaufzeit, ACKs und Zustellstatus. Der Relay kann Nachrichteninhalte nicht lesen.

## Pairing

Pairing-Codes enthalten öffentliche Identity-Keys, Anzeigename und Erstellungszeitpunkt. Der lokale Anzeigename kann vom Nutzer geändert werden und wird bei neu erzeugten Pairing-Codes als öffentlicher Name geteilt.

## Berechtigungen

- Kamera: ausschließlich zum Scannen von Pairing-QR-Codes.
- Face ID / Touch ID: ausschließlich zur lokalen App-Entsperrung.
- Lokales Netzwerk: optional für lokale Relay-/Peer-Tests.

Biometrische Daten bleiben bei Apple/iOS und werden nicht von PrivateChat gelesen oder übertragen.

## Diagnoseberichte

Diagnoseberichte enthalten technische Konfiguration, Runtime-Sicherheitsstatus und Relay-Zustand. Sie enthalten keine Chat-Texte, keine privaten Schlüssel und keine Tokens.

## Beta-Hinweis

Status: Production Candidate. Ein externer Security-Audit steht noch aus. Die Beta-Version ist nicht für hochsensible Kommunikation empfohlen.

## App Store Connect

Dieser Text muss als öffentlich erreichbare HTTPS-URL veröffentlicht und in App Store Connect unter „Privacy Policy URL“ eingetragen werden.
