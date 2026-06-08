# PrivateChat Phase 2.1 Changelog

## Runtime-Stabilisierung

- SwiftUI-Warnung `Publishing changes from within view updates is not allowed` entschärft.
- Pairing-Code wird nicht mehr als berechnete View-Property aus dem ObservableObject erzeugt.
- Fehleranzeige wurde in einen zentralen `ServiceErrorAlertModifier` ausgelagert.
- Error-State wird beim Alert-Dismissal asynchron zurückgesetzt, damit keine ObservableObject-Publishes während SwiftUI-View-Updates entstehen.
- Settings-Bindings ignorieren idempotente Setter-Aufrufe.

## QR-Scanner

- QR-Scanner-Callback wird auf den nächsten Main-Runloop verschoben.
- Capture-Session wird vor dem Import gestoppt.
- Im Simulator ist der Kamera-Scanner deaktiviert, um massive CMIO/VFX-Systemlogs zu vermeiden. Manuelles Einfügen des Pairing-Codes bleibt möglich.
- Auf echtem iPhone bleibt der Kamera-basierte QR-Scanner aktiv.
