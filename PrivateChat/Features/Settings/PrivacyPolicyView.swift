import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        List {
            SwiftUI.Section {
                VStack(alignment: .leading, spacing: 15) {
                    Label("PRIVATSPHÄRE VERSTEHEN", systemImage: "hand.raised")
                        .font(.caption.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(PrivateChatDesign.brandCyan)
                    Text("Weniger Daten.\nKlare Grenzen.")
                        .font(.title2.weight(.bold))
                    Text("PrivateRoom verzichtet auf Werbe- und Analyse-SDKs. Deine Identität entsteht auf deinem Gerät, ohne Telefonnummer oder E-Mail-Registrierung.")
                        .font(.subheadline)
                        .foregroundStyle(PrivateChatDesign.textSecondary)
                }
                .padding(.vertical, 8)
            }
            SwiftUI.Section {
                policy("Deine Inhalte", icon: "lock.shield", detail: "Nachrichten und Anhänge werden auf dem Gerät verschlüsselt. Beim Austausch vermittelt der Relay verschlüsselte Pakete; er erhält keinen Nachrichtenklartext.")
                policy("Deine lokalen Daten", icon: "iphone", detail: "Nachrichten, Entwürfe und Anhänge liegen verschlüsselt im App-Container. Private Schlüssel und Speicherschlüssel liegen mit gerätegebundenem Schutz in der Keychain. Die sensiblen Stores sind vom Cloud-Backup ausgeschlossen.")
                policy("Optionale Mitteilungen", icon: "bell", detail: "Nur wenn du sie aktivierst, erhält der Relay ein Geräte-Push-Token. Apple übermittelt einen neutralen Hinweis ohne Nachrichtentext oder Absender. Der Inhalt wird erst in der entsperrten App abgeholt und entschlüsselt.")
                policy("Dein öffentlicher Kontakt-Code", icon: "qrcode", detail: "Dein gewählter Anzeigename, öffentliche Signatur- und Verschlüsselungsschlüssel sowie Zeitstempel werden mit Personen geteilt, denen du deinen Kontakt-Code gibst.")
            } header: { Text("Was auf deinem Gerät passiert") }
            SwiftUI.Section {
                policy("Zustellmetadaten", icon: "network", detail: "Der Relay verarbeitet verschlüsselte Pakete, Geräte-/Sender-/Empfänger- und Paketkennungen, Zeit- und Ablaufangaben sowie technische Empfangsbestätigungen. Die Netzwerkverbindung kann IP-Adresse und technische Betriebsdaten sichtbar machen.")
                policy("Keine vollständige Anonymität", icon: "person.crop.circle", detail: "Verschlüsselte Inhalte bedeuten nicht unsichtbare Kommunikation. Betreiber können technische Verbindungs- und Zustellmetadaten sehen. Für erhöhte Anforderungen brauchst du ein eigenes geprüftes Bedrohungsmodell.")
                policy("Löschen und Sicherungen", icon: "trash", detail: "Lokales Löschen betrifft dieses Gerät. Kopien bei Kontakten oder bereits vorhandene verschlüsselte Serversicherungen verschwinden dadurch nicht sofort. Details zum Relay-Betrieb stehen in der veröffentlichten Datenschutzerklärung.")
            } header: { Text("Was eine Verbindung offenlegt") }
            SwiftUI.Section {
                policy("Kamera und Mikrofon", icon: "camera", detail: "Zugriff für von dir gestartete QR-, Foto- oder Videoaktionen. Das Mikrofon wird für Videoaufnahmen verwendet. Der Medienimport nutzt den systemeigenen Auswahldialog.")
                policy("Gerätesicherheit", icon: "lock.iphone", detail: "Die App-Sperre verwendet Apples Geräte-Authentifizierung. PrivateRoom bekommt keine biometrischen Daten. Du steuerst die Sperre in den Privatsphäre-Einstellungen.")
                policy("Kopieren und Teilen", icon: "square.and.arrow.up", detail: "Ein Chat-Export ist Klartext. Nach manuellem Teilen können andere Apps oder Empfänger Kopien behalten. PrivateRoom kopiert Textaktionen lokal und zeitbegrenzt; iOS und externe Apps haben eigene Regeln.")
                policy("Supportdiagnose", icon: "doc.text.magnifyingglass", detail: "Ein manuell geteilter Diagnosebericht enthält technische Metadaten, aber keine Chat-Texte, privaten Schlüssel oder Zugangstokens. Prüfe den Bericht vor dem Weitergeben.")
            } header: { Text("Deine bewussten Aktionen") }
            SwiftUI.Section {
                policy("Sicherheitsnummer prüfen", icon: "checkmark.shield", detail: "SC3 bindet die Signatur- und Verschlüsselungsschlüssel beider Geräte. Vergleicht sie über einen vertrauten zweiten Kanal. Eine Signatur allein bestätigt nicht, wer hinter dem Gerät steht.")
                policy("Forward Secrecy für neue Nachrichten", icon: "key", detail: "Der Olm Double Ratchet aus vodozemac wechselt Nachrichtenschlüssel und entfernt verbrauchte Schlüssel. Beide Geräte benötigen die neue Version. Frühere Nachrichten erhalten diesen Schutz nicht rückwirkend. Der unabhängige Audit der Bibliothek deckt unsere App-Einbindung nicht ab; deren externe Prüfung steht noch aus.")
                policy("Beta mit offenem Audit", icon: "info.circle", detail: "Ein unabhängiger Sicherheits-Audit steht aus. Kompromittierte Geräte, Screenshots und das Weitergeben durch Empfänger können Inhalte offenlegen. Keine Garantie absoluter Sicherheit; diese Beta ist nicht für hochsensible Kommunikation freigegeben.")
                policy("Geräteverlust", icon: "externaldrive.badge.exclamationmark", detail: "Die gerätegebundenen Schlüssel und ausgeschlossenen Backups können dazu führen, dass Chats nach Verlust, Neuinstallation oder Gerätewechsel nicht wiederherstellbar sind. Es gibt noch keinen geprüften Geräteumzug.")
            } header: { Text("Was PrivateRoom nicht verspricht") }
            SwiftUI.Section {
                Link(destination: URL(string: "https://securechat.team/privacy-de.html")!) {
                    Label("Vollständige Datenschutzerklärung", systemImage: "arrow.up.right.square")
                }
                Link(destination: URL(string: "https://securechat.team/security.html")!) {
                    Label("Sicherheitsmodell und bekannte Grenzen", systemImage: "arrow.up.right.square")
                }
                Link(destination: URL(string: "https://securechat.team/support.html")!) {
                    Label("Datenschutz- und Supportkontakt", systemImage: "arrow.up.right.square")
                }
            } header: { Text("Mehr erfahren") }
            footer: {
                Text("Diese Ansicht erklärt die Datenflüsse der App. Die vollständige veröffentlichte Erklärung enthält die Betreiberangaben, Rechtsgrundlagen, Speicherfristen und Kontaktmöglichkeiten.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(PrivateChatDesign.pageGradient.ignoresSafeArea())
        .navigationTitle("Datenschutz")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func policy(_ title: String, icon: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(PrivateChatDesign.brandCyan)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(PrivateChatDesign.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 7)
    }

    static let fullPolicyText = """
PrivateRoom – Datenschutz-Kurzfassung

Keine Werbe- oder Analyse-SDKs. Die Identität entsteht auf dem Gerät ohne Telefon- oder E-Mail-Registrierung. Kontakt-Codes teilen Anzeigenamen, öffentliche Signatur- und Verschlüsselungsschlüssel sowie Zeitstempel; private Schlüssel bleiben gerätegebunden.

Nachrichten, Entwürfe und Anhänge werden lokal verschlüsselt gespeichert. Sensible Stores sind vom Cloud-Backup ausgeschlossen. Geräteverlust, Neuinstallation oder Gerätewechsel können Datenverlust bedeuten. Ein geprüfter Geräteumzug steht noch nicht zur Verfügung.

Der Relay vermittelt verschlüsselte Pakete und verarbeitet technische Zustellmetadaten wie Geräte-, Sender-, Empfänger- und Paketkennungen, Zeitangaben und Empfangsbestätigungen. Die Verbindung macht technische Netzwerkdaten wie IP-Adressen sichtbar. Verschlüsselung ist kein Versprechen vollständiger Anonymität. Lokales Löschen entfernt keine Kopien bei Kontakten und löscht bereits vorhandene verschlüsselte Serversicherungen nicht sofort.

Kamera und Mikrofon werden für von dir ausgelöste QR-, Foto- und Videoaktionen verwendet. Apples Geräte-Authentifizierung gibt keine biometrischen Daten an PrivateRoom weiter. Manuelle Exporte sind Klartext; externe Apps und Empfänger können Kopien behalten. Supportberichte enthalten technische Metadaten, aber keine Nachrichtenklartexte, privaten Schlüssel oder Tokens.

Neue Nachrichten verwenden Olm mit Forward Secrecy. Alte Aufzeichnungen werden dadurch nicht rückwirkend geschützt. Unabhängiger Audit der App-Einbindung offen. Diese Beta ist nicht für hochsensible Kommunikation freigegeben. Kompromittierte Geräte und Empfänger können Inhalte offenlegen.

Vollständige Erklärung und Betreiberkontakt: https://securechat.team/privacy-de.html
"""
}
