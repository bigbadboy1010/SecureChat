import SwiftUI

struct SafetyNumberView: View {
    @ObservedObject var service: ConversationService
    let peer: TrustedPeer
    @Environment(\.dismiss) private var dismiss
    @State private var confirmedGroupIndexes: Set<Int> = []
    @State private var comparedOnTrustedChannel = false

    private var currentPeer: TrustedPeer {
        service.trustedPeers.first(where: { $0.id == peer.id }) ?? peer
    }
    private var groups: [String] {
        currentPeer.safetyNumber.split(separator: " ").map(String.init)
    }
    private var allGroupsConfirmed: Bool {
        groups.isEmpty == false && confirmedGroupIndexes.count == groups.count && comparedOnTrustedChannel
    }

    var body: some View {
        List {
            SwiftUI.Section {
                VStack(alignment: .leading, spacing: 14) {
                    Label("VERTRAUEN PRÜFEN", systemImage: "person.crop.circle.badge.questionmark")
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(PrivateChatDesign.brandCyan)
                    Text("Ist das wirklich\n\(currentPeer.displayName)?")
                        .font(.title2.weight(.bold))
                    Text("Vergleicht diese SC3-Gruppen auf beiden Geräten, persönlich oder über einen bereits vertrauten zweiten Kanal. Die Nummer bindet die Signatur- und Verschlüsselungsschlüssel beider Geräte.")
                        .font(.subheadline)
                        .foregroundStyle(PrivateChatDesign.textSecondary)
                }
                .padding(.vertical, 8)
            }
            SwiftUI.Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                        Button {
                            if confirmedGroupIndexes.contains(index) { confirmedGroupIndexes.remove(index) }
                            else { confirmedGroupIndexes.insert(index) }
                        } label: {
                            VStack(spacing: 8) {
                                Text(group).font(.body.monospaced().weight(.semibold))
                                Image(systemName: confirmedGroupIndexes.contains(index) ? "checkmark.circle.fill" : "circle")
                                    .font(.caption)
                            }
                            .foregroundStyle(confirmedGroupIndexes.contains(index) ? PrivateChatDesign.brandCyan : PrivateChatDesign.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 72)
                            .background(PrivateChatDesign.canvasHigh, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Gruppe \(index + 1): \(group)")
                        .accessibilityValue(confirmedGroupIndexes.contains(index) ? "Verglichen" : "Noch nicht verglichen")
                    }
                }
                .padding(.vertical, 8)
                Text("\(confirmedGroupIndexes.count) von \(groups.count) Gruppen verglichen")
                    .font(.footnote)
                    .foregroundStyle(PrivateChatDesign.textSecondary)
                Button {
                    PrivateRoomClipboard.copy(currentPeer.safetyNumber)
                } label: {
                    Label("Nummer lokal kopieren", systemImage: "doc.on.doc")
                        .frame(minHeight: 44)
                }
            } header: { Text("Sicherheitsnummer") }
            footer: { Text("Tippe jede Gruppe an, nachdem sie übereinstimmt. Kopierte Nummern bleiben nur auf diesem Gerät und laufen nach einer Minute ab.") }
            SwiftUI.Section {
                Toggle("Wir haben beide Geräte über einen vertrauten zweiten Kanal verglichen.", isOn: $comparedOnTrustedChannel)
                    .font(.subheadline)
                Button {
                    guard service.verifyPeer(id: currentPeer.id) else { return }
                    dismiss()
                } label: {
                    Label("Identität bestätigen", systemImage: "checkmark.seal")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .disabled(allGroupsConfirmed == false)
            } footer: {
                Text("Eine passende Nummer bestätigt eure Geräte-Schlüssel. Sie schützt nicht vor einem kompromittierten Gerät oder dem Weitergeben von Inhalten durch Empfänger.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(PrivateChatDesign.pageGradient.ignoresSafeArea())
        .navigationTitle("Identität prüfen")
        .navigationBarTitleDisplayMode(.inline)
        .privateChatErrorAlert(service: service)
        .onChange(of: currentPeer.safetyNumber) { _ in
            confirmedGroupIndexes = []
            comparedOnTrustedChannel = false
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Schließen") { dismiss() }
            }
        }
    }
}
