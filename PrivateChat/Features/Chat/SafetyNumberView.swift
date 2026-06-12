import SwiftUI
import UIKit

struct SafetyNumberView: View {
    @ObservedObject var service: ConversationService
    let peer: TrustedPeer

    @Environment(\.dismiss) private var dismiss
    @State private var confirmedGroupIndexes: Set<Int> = []

    private var groups: [String] {
        let parts = peer.safetyNumber
            .split(separator: " ")
            .map(String.init)
        if parts.isEmpty == false {
            return parts
        }

        return stride(from: 0, to: min(peer.safetyNumber.count, 64), by: 4).map { offset in
            let start = peer.safetyNumber.index(peer.safetyNumber.startIndex, offsetBy: offset)
            let end = peer.safetyNumber.index(start, offsetBy: min(4, peer.safetyNumber.distance(from: start, to: peer.safetyNumber.endIndex)))
            return String(peer.safetyNumber[start..<end]).uppercased()
        }
    }

    private var allGroupsConfirmed: Bool {
        groups.isEmpty == false && confirmedGroupIndexes.count == groups.count
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        List {
            SwiftUI.Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Safety Number vergleichen", systemImage: "lock.shield")
                        .font(.headline)
                    Text("Vergleiche diese Gruppen mit deinem Kontakt über einen zweiten Kanal. Erst danach sollte der Kontakt als verifiziert markiert werden.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
                .padding(.vertical, 4)
            }

            SwiftUI.Section {
                LabeledContent("Kontakt") {
                    Text(peer.displayName)
                }
                LabeledContent("Trust") {
                    Text(peer.trustState.rawValue)
                }
                LabeledContent("Peer ID") {
                    Text(String(peer.id.prefix(18)) + "…")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            } header: {
                Text("Kontakt")
            }

            SwiftUI.Section {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                        Button {
                            toggleConfirmation(index)
                        } label: {
                            VStack(spacing: 6) {
                                Text(group)
                                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                Image(systemName: confirmedGroupIndexes.contains(index) ? "checkmark.circle.fill" : "circle")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .padding(.vertical, 6)
                            .background(confirmedGroupIndexes.contains(index) ? Color.green.opacity(0.14) : Color.secondary.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Safety-Gruppe \(index + 1): \(group)")
                    }
                }

                Button {
                    UIPasteboard.general.string = peer.safetyNumber
                } label: {
                    Label("Safety Number kopieren", systemImage: "doc.on.doc")
                }
            } header: {
                Text("Safety Number")
            } footer: {
                Text("Tippe jede Gruppe an, nachdem du sie verglichen hast. Das verhindert versehentliches Blind-Verifizieren.")
            }

            SwiftUI.Section {
                Button {
                    service.verifyPeer(id: peer.id)
                    dismiss()
                } label: {
                    Label(peer.trustState == .verified ? "Erneut als geprüft bestätigen" : "Kontakt als verifiziert markieren", systemImage: "checkmark.seal")
                }
                .disabled(allGroupsConfirmed == false)

                if allGroupsConfirmed == false {
                    Label("Noch nicht alle Gruppen bestätigt", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                }
            } header: {
                Text("Verifizierung")
            }
        }
        .navigationTitle("Safety Number")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") { dismiss() }
            }
        }
    }

    private func toggleConfirmation(_ index: Int) {
        if confirmedGroupIndexes.contains(index) {
            confirmedGroupIndexes.remove(index)
        } else {
            confirmedGroupIndexes.insert(index)
        }
    }
}
