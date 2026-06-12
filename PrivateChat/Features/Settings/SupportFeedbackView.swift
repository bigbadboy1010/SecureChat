import SwiftUI
import UIKit

struct SupportFeedbackView: View {
    @ObservedObject var service: ConversationService

    var body: some View {
        List {
            SwiftUI.Section {
                SupportRow(
                    systemImage: "testtube.2",
                    title: "TestFlight Feedback",
                    message: "Öffne TestFlight, wähle PrivateChat und sende Feedback mit Screenshot und kurzer Beschreibung. Das ist der bevorzugte Beta-Kanal."
                )
                SupportRow(
                    systemImage: "doc.text.magnifyingglass",
                    title: "Diagnose ohne Chat-Texte",
                    message: "Der Diagnosebericht enthält technische Konfiguration, Runtime-Status und Relay-Zustand. Chat-Inhalte, private Schlüssel und Tokens werden nicht exportiert."
                )
                SupportRow(
                    systemImage: "exclamationmark.bubble",
                    title: "Was melden?",
                    message: "Bitte Build-Nummer, Gerät, iOS-Version, erwartetes Verhalten und tatsächliches Verhalten angeben."
                )
            } header: {
                Text("Support")
            }

            SwiftUI.Section {
                ShareLink(item: service.appDiagnosticsReport()) {
                    Label("Diagnosebericht teilen", systemImage: "square.and.arrow.up")
                }

                Button {
                    UIPasteboard.general.string = service.appDiagnosticsReport()
                } label: {
                    Label("Diagnosebericht kopieren", systemImage: "doc.on.doc")
                }

                Button {
                    UIPasteboard.general.string = Self.feedbackTemplate(versionString: Self.versionString)
                } label: {
                    Label("Feedback-Vorlage kopieren", systemImage: "clipboard")
                }
            } header: {
                Text("Feedback-Hilfen")
            } footer: {
                Text("Externe Support-URL und Privacy-Policy-URL müssen zusätzlich in App Store Connect hinterlegt werden. Diese App öffnet bewusst keinen ungeprüften Drittanbieter-Link.")
            }

            SwiftUI.Section {
                LabeledContent("Version") {
                    Text(Self.versionString)
                        .font(.caption.monospaced())
                }
                LabeledContent("Relay") {
                    Text(SecureChatProductionProfile.relayBaseURLString)
                        .font(.caption.monospaced())
                }
                LabeledContent("Status") {
                    Text("Production Candidate")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Build")
            }
        }
        .navigationTitle("Support & Feedback")
    }

    static var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    static func feedbackTemplate(versionString: String) -> String {
        """
PrivateChat Feedback

Build: \(versionString)
Gerät:
iOS-Version:
Bereich: Onboarding / Relay / Pairing / Chat / Security / Sonstiges

Erwartetes Verhalten:

Tatsächliches Verhalten:

Schritte zum Reproduzieren:
1.
2.
3.

Hinweis: Bitte keine Relay-Tokens, private Schlüssel oder Chat-Inhalte mitschicken.
"""
    }
}

private struct SupportRow: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}
