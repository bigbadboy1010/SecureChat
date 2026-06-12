# Phase 14.6.2 – TestFlight Submission Prep

## Ziel

Die im Review genannten letzten TestFlight-Schritte wurden vorbereitet: Build-Nummer erhöhen, Privacy-/Support-Inhalte integrieren, TestFlight-Texte vorbereiten und Empty-State für neue Tester verbessern.

## Änderungen

- `CURRENT_PROJECT_VERSION` von `1` auf `2` erhöht.
- Neue In-App-Ansichten:
  - `PrivacyPolicyView`
  - `SupportFeedbackView`
  - `TestFlightSubmissionView`
- Neue Settings-Section: `TestFlight & App Store Connect`.
- Datenschutzrichtlinie als In-App-Text und in `Docs/PRIVACY_POLICY.md` ergänzt.
- Support-/Feedback-Hinweise in App und `Docs/SUPPORT_AND_FEEDBACK.md` ergänzt.
- TestFlight „What to Test“ und Reviewer Notes in App und `Docs/TESTFLIGHT_WHAT_TO_TEST.md` ergänzt.
- ConversationList Empty-State erweitert: Erstnutzer sehen direkt einen `Solo-Test-Chat starten` Button.
- Display-Name-Normalisierung gehärtet: Steuer-/Emoji-/HTML-ähnliche Sonderzeichen werden entfernt, Länge bleibt auf 80 Zeichen begrenzt.
- `IdentityManagerTests` um Display-Name-Sanitizing erweitert.

## Nicht erledigt

- Externe Privacy-Policy-URL und Support-URL können nicht im Code gehostet werden. Die Inhalte liegen vorbereitet in `Docs/` und müssen auf einer öffentlichen HTTPS-Seite veröffentlicht und in App Store Connect eingetragen werden.
- ConversationService-Split bleibt Phase 15.
- Push Notifications und Double Ratchet bleiben spätere Phasen.

## Erwarteter TestFlight-Status

Der Code ist für den ersten internen TestFlight-Build vorbereitet. Für App Store Connect müssen noch Privacy-Policy-URL und Support-URL extern gesetzt werden.
