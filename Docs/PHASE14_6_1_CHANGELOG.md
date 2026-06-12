# Phase 14.6.1 — Onboarding Compile Fix

## Fix

- `PrivateChat/Features/Onboarding/OnboardingView.swift` korrigiert.
- In `OnboardingPage` wurde die Property `body` in `message` umbenannt.
- Damit kollidiert sie nicht mehr mit `var body: some View` aus dem SwiftUI `View`-Protokoll.

## Hintergrund

Xcode meldete:

```text
Invalid redeclaration of 'body'
```

Ursache war eine Stored Property `let body: String` im selben `View`, das gleichzeitig `var body: some View` deklarieren muss.

## Verhalten

- Keine Änderung am Onboarding-Flow.
- Keine Änderung an Relay, Crypto, Store oder Nachrichtenformat.
- Nur Compile-Fix.
