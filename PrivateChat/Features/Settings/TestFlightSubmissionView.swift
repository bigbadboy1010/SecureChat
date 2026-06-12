import SwiftUI
import UIKit

struct TestFlightSubmissionView: View {
    var body: some View {
        List {
            SwiftUI.Section {
                ChecklistRow(isDone: true, title: "Bundle ID", detail: "org.francois.PrivateChat")
                ChecklistRow(isDone: true, title: "Build-Nummer", detail: "CURRENT_PROJECT_VERSION = 2")
                ChecklistRow(isDone: true, title: "AppIcon", detail: "iPhone, iPad, Mac und Marketing-Icon vorhanden")
                ChecklistRow(isDone: true, title: "PrivacyInfo", detail: "UserDefaults + FileTimestamp deklariert")
                ChecklistRow(isDone: true, title: "Onboarding", detail: "3 Screens + Beta-Hinweis")
                ChecklistRow(isDone: false, title: "Privacy-Policy-URL", detail: "In App Store Connect als öffentliche HTTPS-URL eintragen")
                ChecklistRow(isDone: false, title: "Support-URL", detail: "In App Store Connect eintragen")
            } header: {
                Text("TestFlight Checkliste")
            }

            SwiftUI.Section {
                Text(Self.whatToTestText)
                    .font(.footnote)
                    .textSelection(.enabled)

                Button {
                    UIPasteboard.general.string = Self.whatToTestText
                } label: {
                    Label("What to Test kopieren", systemImage: "doc.on.doc")
                }
            } header: {
                Text("App Store Connect: What to Test")
            }

            SwiftUI.Section {
                Text(Self.reviewerNotes)
                    .font(.footnote)
                    .textSelection(.enabled)

                Button {
                    UIPasteboard.general.string = Self.reviewerNotes
                } label: {
                    Label("Reviewer Notes kopieren", systemImage: "clipboard")
                }
            } header: {
                Text("Reviewer Notes")
            }
        }
        .navigationTitle("TestFlight Vorbereitung")
    }

    static let whatToTestText = """
Bitte testen:
1. Onboarding durchlaufen und Beta-Hinweis bestätigen.
2. Display-Name im Pairing-Tab ändern und Pairing-Code neu laden.
3. Dashboard → Solo-Test-Chat anlegen und lokale verschlüsselte Speicherung prüfen.
4. Security → Transport: Production Relay https://chatsecure.ddns.net aktivieren und RELAY_AUTH_TOKEN eintragen.
5. Relay prüfen, Inbox abrufen und Diagnosebericht teilen/kopieren.
6. Pairing mit zweitem Gerät testen: QR scannen, Safety Number vergleichen, Kontakt verifizieren, Nachricht senden.
7. Chat-Details → Safety Number vergleichen: Gruppen aktiv bestätigen und Peer verifizieren.

Hinweis: Für Solo-Test ist kein zweites Gerät erforderlich. Für Relay-Tests wird der separate RELAY_AUTH_TOKEN benötigt. Bitte keine Tokens oder Chat-Inhalte im Feedback posten.
"""

    static let reviewerNotes = """
PrivateChat ist ein Production-Candidate für TestFlight. Die App nutzt lokale Keychain-Schlüssel, verschlüsselten lokalen Speicher und optional einen selbst betriebenen HTTPS-Relay. Der Relay kann keine Nachrichtenklartexte lesen.

Für Tests ohne zweites Gerät gibt es im Dashboard einen Solo-Test-Modus. Für echte Peer-Tests bitte zwei Geräte installieren und Pairing per QR-Code durchführen.

Kein Demo-Account erforderlich. Relay-Token wird nicht öffentlich bereitgestellt und wird nur für interne TestFlight-Tester verteilt.
"""
}

private struct ChecklistRow: View {
    let isDone: Bool
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? Color.green : Color.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
