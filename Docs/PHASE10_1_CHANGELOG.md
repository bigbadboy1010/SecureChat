# PrivateChat Phase 10.1

## Ziel

Phase 10.1 ist ein Kompatibilitäts-Hotfix für SF Symbols auf iOS/macCatalyst-Targets mit Deployment Target iOS 16.

## Änderung

Einige neuere SF-Symbolnamen wurden durch konservativere System-Symbole ersetzt, damit Xcode/iOS keine Runtime-Warnungen wie diese ausgibt:

```text
No symbol named 'shippingbox.and.arrow.forward' found in system symbol set
```

## Betroffene Bereiche

- Production Readiness UI
- Dashboard
- Chat Composer Hinweis
- Settings Persistenz-/Produktionshinweise

## Nicht geändert

- Relay-Protokoll
- Crypto-/Payload-Format
- lokale Stores
- Produktions-Relay Docker-/Caddy-Dateien
