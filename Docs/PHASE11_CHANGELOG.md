# PrivateChat Phase 11 – App Hardening & Anti-Tamper Baseline

Phase 11 ergänzt PrivateChat um eine lokale App-Härtungsschicht. Das Nachrichtenformat, die Crypto-Payloads und die Relay-API bleiben unverändert.

## Neu

- Runtime-Security-Evaluator
  - Simulator-Erkennung
  - Debug-Build-Erkennung
  - Debugger-Erkennung über Darwin/sysctl
  - Jailbreak-Indikatoren über bekannte Pfade und Sandbox-Schreibprobe
  - DYLD-Injection-Indikator
- Neue Runtime-Security-Ansicht in der App
  - Status
  - Risiko-Level
  - Findings
  - Policy-Schalter
- Optionale Relay-Sperre bei kritischem Runtime-Risiko
  - blockiert Relay-Sync, Relay-Stats, Relay-Purge, Relay-Health und Senden über Relay
  - greift nur bei kritischen Signalen wie Debugger, Jailbreak-Indikatoren oder DYLD-Injection
  - Simulator/Debug werden als Development erkannt, aber nicht automatisch blockiert
- Diagnosebericht erweitert um Runtime-/Hardening-Status
- Production-Readiness-Ansicht erweitert um Phase-11-Hardening
- Dashboard zeigt Runtime-Risikostatus

## Security-Hinweis

App-Härtung ersetzt keine Kryptografie. Die Ende-zu-Ende-Sicherheit darf nicht von geheimem App-Code abhängen. Die Härtung erschwert Analyse, Manipulation und Relay-Missbrauch, kann einen starken lokalen Angreifer aber nicht mathematisch ausschließen.

## Unverändert

- Kein neues Relay-Protokoll
- Kein neues Nachrichtenformat
- Kein neues Crypto-Payload-Format
- Keine Änderung an Pairing-/Safety-Number-Logik
