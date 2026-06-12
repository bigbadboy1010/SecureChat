# Phase 14.5.2 — SwiftUI Update Coalescing

## Fixes

- `ChatView.swift`: Scroll-to-bottom and mark-as-read updates are now coalesced through a cancellable `Task` instead of being executed directly inside the message-count `onChange` handler.
- `ServiceErrorAlert.swift`: Error alert presentation is now deferred by one main-actor turn and coalesced through a cancellable `Task`.

## Goal

Reduce SwiftUI runtime warnings such as:

```text
onChange(of: ReceiverData) action tried to update multiple times per frame.
```

## Notes

The remaining `PointerUI`, `linkd.autoShortcut`, `LSPrefs`, `CSInlineDonation`, and `ViewBridge` messages are Apple/Xcode runtime noise and are not Relay or application logic errors.
