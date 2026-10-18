import SwiftUI

struct DeviceSafetyView: View {
    @ObservedObject var service: ConversationService
    var body: some View {
        List {
            SwiftUI.Section {
                LabeledContent("Name", value: service.localIdentity.displayName)
                Text("Gerät \(service.localIdentity.id.prefix(12))").font(.headline.monospaced())
                Text("Der Name kann auf mehreren Geräten gleich sein. Die öffentliche Gerätekennung unterscheidet sie; die SC3-Sicherheitsnummer bestätigt zusätzlich beide Kontaktschlüssel.")
                ShareLink(item: "PrivateRoom öffentliche Gerätekennung: \(service.localIdentity.id)") {
                    Label("Öffentliche Gerätekennung teilen", systemImage: "square.and.arrow.up")
                }
            } header: { Text("Dieses Gerät") }
            SwiftUI.Section {
                Text("1. Sperre das verlorene Gerät über Apples ‚Wo ist?‘, sofern verfügbar.")
                Text("2. Bitte den Betreiber um die Sperre genau dieser öffentlichen Gerätekennung. Ein vertrauter Kontakt kann die Kennung des verlorenen Geräts aus seinem Kontakt-Code bereitstellen.")
                Text("3. Informiere deine Kontakte über einen vertrauten zweiten Kanal. Sie sollten den bisherigen Kontakt blockieren und einen neuen Code erneut prüfen.")
                Text("Eine Relay-Sperre stoppt weitere Serverzugriffe. Sie löscht keine Schlüssel oder bereits gespeicherten Inhalte auf dem verlorenen Gerät und ruft bereits zugestellte Pakete nicht zurück.")
                    .foregroundStyle(.secondary)
            } header: { Text("Gerät verloren") }
            SwiftUI.Section {
                Text("Auf einem neuen Gerät entsteht eine neue Identität. Lass dieses Gerät für die Beta freigeben und tausche neue Kontakt-Codes aus. Vergleicht die neue SC3-Sicherheitsnummer, bevor ihr weiter kommuniziert.")
                Text("Chats und Schlüssel sind vom Cloud-Backup ausgeschlossen und gerätegebunden. Es gibt in dieser Beta keinen geprüften Schlüssel- oder Chatumzug. Verlust, Neuinstallation oder Gerätewechsel können daher endgültigen Datenverlust bedeuten.")
                Text("Kopiere keine privaten Schlüssel in E-Mails, Notizen, Kontakt-Codes oder Supportberichte. Das Neuladen deines Kontakt-Codes erzeugt keine neue Geräteidentität.")
                    .foregroundStyle(.secondary)
            } header: { Text("Gerätewechsel und Wiederherstellung") }
            SwiftUI.Section {
                Link("Hilfe zu Geräteverlust und Sperrung", destination: URL(string: "https://securechat.team/device-help.html")!)
                Link("Betreiber kontaktieren", destination: URL(string: "mailto:miggu69@gmail.com")!)
            }
        }
        .navigationTitle("Geräte & Wiederherstellung")
    }
}
