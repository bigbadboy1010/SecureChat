# PrivateChat Phase 7 Changelog

Phase 7 baut auf dem stabilen Phase-6.1-Relay auf und fokussiert Produktreife, UI-Qualität und tägliche Bedienbarkeit.

## UI / Produkt

- Neuer Chat-Details-Screen mit Kontakt-, Safety-Number- und Chat-Statistiken.
- Nachrichten-Details-Sheet mit Richtung, Status, Zeitstempel, Message-ID und Kopieraktionen.
- Markierte Nachrichten über das Nachrichten-Kontextmenü.
- Neuer Chat-Filter „Markiert“.
- Neuer Chat-Filter „Stumm“.
- Chats können stummgeschaltet werden.
- Chatliste zeigt Pin-, Stumm- und Star-Zustand direkt in der Row.
- Swipe-Aktionen in der Chatliste:
  - Pin
  - als gelesen markieren
  - archivieren
- Schnellantworten im Composer.
- Zeichenanzeige im Composer.
- Empty-State im Chat für neue Gespräche.
- Dashboard erweitert um Markierungen, stumme Chats, Fehlerstatus und Readiness-Indikatoren.

## Datenmodell / Migration

- `ChatMessage.isStarred` mit rückwärtskompatiblem Default `false`.
- `Conversation.isMuted` mit rückwärtskompatiblem Default `false`.
- Neue lokale Analyse-Struktur `ConversationAnalyticsSnapshot`.

## Service Layer

- `toggleMessageStarred`.
- `toggleConversationMuted`.
- `clearConversationMessages`.
- `markAllConversationsRead`.
- Aggregierte Zähler für markierte Nachrichten, stumme Chats und fehlgeschlagene Nachrichten.
- Conversation Analytics pro Chat.

## Relay

- Kein Protokollbruch gegenüber Phase 6.1.
- RelayServer unverändert kompatibel.
- `npm run typecheck` erfolgreich.

## Hinweis

Der iOS-Build wurde in dieser Umgebung nicht ausgeführt, weil kein Xcode/iOS-SDK verfügbar ist. Der RelayServer-Typecheck wurde ausgeführt.
