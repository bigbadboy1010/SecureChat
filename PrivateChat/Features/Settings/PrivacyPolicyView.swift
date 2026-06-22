import SwiftUI
import UIKit

struct PrivacyPolicyView: View {
    var body: some View {
        List {
            SwiftUI.Section {
                PolicyRow(
                    systemImage: "hand.raised.fill",
                    title: "Keine Tracker",
                    message: "PrivateChat nutzt keine Werbe-SDKs, kein Tracking und keine Analyse-Drittanbieter."
                )
                PolicyRow(
                    systemImage: "lock.shield.fill",
                    title: "Ende-zu-Ende verschlüsselte Inhalte",
                    message: "Nachrichteninhalte werden lokal verschlüsselt gespeichert und als verschlüsselte Relay-Envelopes übertragen. Der Relay-Server sieht keine Klartexte."
                )
                PolicyRow(
                    systemImage: "externaldrive.fill",
                    title: "Lokaler Speicher",
                    message: "Chats, Drafts und Metadaten werden im App-Container gespeichert. Nachrichten- und Draft-Stores sind AES-GCM-verschlüsselt und vom iCloud-Backup ausgeschlossen."
                )
                PolicyRow(
                    systemImage: "key.fill",
                    title: "Schlüsselmaterial",
                    message: "Private Schlüssel und Store-Keys liegen im iOS-Keychain mit ThisDeviceOnly-Schutz. Private Keys verlassen das Gerät nicht."
                )
            } header: {
                Text("Kurzfassung")
            } footer: {
                Text("Diese Ansicht dient als In-App-Zusammenfassung. Für TestFlight/App Store Connect muss derselbe Inhalt zusätzlich als öffentliche Privacy-Policy-URL veröffentlicht werden.")
            }

            SwiftUI.Section {
                LabeledContent("Produkt") {
                    Text("PrivateChat / SecureChat")
                }
                LabeledContent("Bundle ID") {
                    Text("org.francois.PrivateChat")
                        .font(.caption.monospaced())
                }
                LabeledContent("Relay") {
                    Text(SecureChatProductionProfile.relayBaseURLString)
                        .font(.caption.monospaced())
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Status") {
                    Text("Production Candidate")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("App-Information")
            }

            SwiftUI.Section {
                PolicyRow(
                    systemImage: "person.crop.circle.badge.questionmark",
                    title: "Anzeigename",
                    message: "Der lokale Anzeigename wird im Keychain gespeichert und in Pairing-Codes als öffentlicher Name geteilt."
                )
                PolicyRow(
                    systemImage: "qrcode.viewfinder",
                    title: "Pairing-Daten",
                    message: "Pairing-Codes enthalten öffentliche Identity-Keys, Anzeigename und Zeitstempel. Private Schlüssel werden nicht exportiert."
                )
                PolicyRow(
                    systemImage: "network",
                    title: "Relay-Metadaten",
                    message: "Der Relay verarbeitet verschlüsselte Pakete, Empfänger-ID, Sender-ID, Ablaufzeit, ACKs und technische Zustellmetadaten."
                )
                PolicyRow(
                    systemImage: "doc.text.magnifyingglass",
                    title: "Diagnoseberichte",
                    message: "Diagnoseberichte enthalten technische Konfiguration, Security-Status und Relay-Zustand, aber keine Chat-Texte und keine Tokens."
                )
            } header: {
                Text("Welche Daten verarbeitet werden")
            }

            SwiftUI.Section {
                PolicyRow(
                    systemImage: "wifi.router",
                    title: "SecureChat Relay",
                    message: "Bei aktivem Relay werden verschlüsselte Pakete an securechat.team übertragen. Authentifizierung erfolgt mit RELAY_AUTH_TOKEN."
                )
                PolicyRow(
                    systemImage: "camera.viewfinder",
                    title: "Kamera",
                    message: "Die Kamera wird nur zum Scannen von Pairing-QR-Codes verwendet. Es erfolgt keine dauerhafte Speicherung von Kamerabildern."
                )
                PolicyRow(
                    systemImage: "faceid",
                    title: "Biometrie",
                    message: "Face ID oder Touch ID entsperrt nur die lokale App. Biometrische Daten bleiben bei Apple/iOS und werden nicht von PrivateChat gelesen."
                )
            } header: {
                Text("Berechtigungen")
            }

            SwiftUI.Section {
                Text(Self.fullPolicyText)
                    .font(.footnote)
                    .textSelection(.enabled)

                Button {
                    UIPasteboard.general.string = Self.fullPolicyText
                } label: {
                    Label("Policy-Text kopieren", systemImage: "doc.on.doc")
                }
            } header: {
                Text("Veröffentlichungsfassung")
            } footer: {
                Text("Für App Store Connect muss dieser Text auf einer öffentlich erreichbaren HTTPS-Seite veröffentlicht und als Privacy Policy URL eingetragen werden.")
            }
        }
        .navigationTitle("Datenschutz")
    }

    static let fullPolicyText = """
PrivateChat / SecureChat Datenschutzrichtlinie

PrivateChat ist ein Ende-zu-Ende-verschlüsselter Messenger-Kern. Die App verwendet keine Werbe-SDKs, keine Tracker und keine Analyse-Drittanbieter.

Nachrichteninhalte werden lokal auf dem Gerät verschlüsselt gespeichert. Drafts und Nachrichtenstores verwenden AES-GCM und Schlüssel aus dem iOS-Keychain. Lokale Stores werden vom iCloud-Backup ausgeschlossen. Private Schlüssel verlassen das Gerät nicht.

Wenn der Relay-Modus aktiviert ist, überträgt die App verschlüsselte Pakete an den SecureChat Relay unter https://securechat.team. Der Relay verarbeitet technische Zustellmetadaten wie Sender-ID, Empfänger-ID, Paket-ID, Ablaufzeit, ACKs und Zustellstatus. Der Relay kann Nachrichteninhalte nicht lesen.

Pairing-Codes enthalten öffentliche Identity-Keys, Anzeigename und Erstellungszeitpunkt. Der lokale Anzeigename kann vom Nutzer geändert werden und wird bei neu erzeugten Pairing-Codes als öffentlicher Name geteilt.

Die Kamera wird ausschließlich zum Scannen von Pairing-QR-Codes verwendet. Face ID oder Touch ID wird nur zur lokalen App-Entsperrung verwendet; biometrische Daten werden nicht von PrivateChat gelesen oder übertragen.

Diagnoseberichte enthalten technische Metadaten, Runtime-Sicherheitsstatus und Relay-Konfiguration, jedoch keine Chat-Texte, keine privaten Schlüssel und keine Tokens.

Status: Production Candidate. Ein externer Security-Audit steht noch aus. Die Beta-Version ist nicht für hochsensible Kommunikation empfohlen.
"""
}

private struct PolicyRow: View {
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
