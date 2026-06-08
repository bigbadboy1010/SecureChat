import SwiftUI
import UIKit

struct ChatDetailsView: View {
    @ObservedObject var service: ConversationService
    let conversationID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var editedTitle = ""

    private var storedConversation: StoredConversation? {
        service.conversations.first { $0.id == conversationID }
    }

    private var conversation: Conversation? {
        storedConversation?.conversation
    }

    private var peer: TrustedPeer? {
        guard let peerID = conversation?.peerID else { return nil }
        return service.trustedPeers.first { $0.id == peerID }
    }

    private var analytics: ConversationAnalyticsSnapshot {
        service.analytics(for: conversationID)
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                analyticsSection
                securitySection
                exportSection
                actionsSection
            }
            .navigationTitle("Chat-Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .onAppear {
                editedTitle = conversation?.title ?? ""
            }
        }
    }

    private var headerSection: some View {
        SwiftUI.Section {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(iconTint.opacity(0.16))
                        .frame(width: 58, height: 58)
                    Image(systemName: iconName)
                        .font(.title2)
                        .foregroundStyle(iconTint)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(conversation?.title ?? "Unbekannter Chat")
                        .font(.headline)
                    Text(peer?.displayName ?? (conversation?.peerID == nil ? "Lokaler Notiz-Chat" : "Kontakt nicht gefunden"))
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                    HStack(spacing: 8) {
                        if conversation?.isPinned == true {
                            Label("Fixiert", systemImage: "pin.fill")
                        }
                        if conversation?.isMuted == true {
                            Label("Stumm", systemImage: "bell.slash.fill")
                        }
                        if conversation?.isArchived == true {
                            Label("Archiv", systemImage: "archivebox.fill")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
                }
            }
            .padding(.vertical, 4)

            TextField("Chat-Name", text: $editedTitle)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(true)

            Button {
                service.renameConversation(id: conversationID, title: editedTitle)
            } label: {
                Label("Chat-Namen speichern", systemImage: "checkmark.circle")
            }
            .disabled(editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editedTitle == conversation?.title)
        }
    }

    private var analyticsSection: some View {
        SwiftUI.Section {
            LabeledContent("Nachrichten", value: "\(analytics.messageCount)")
            LabeledContent("Eingehend", value: "\(analytics.incomingCount)")
            LabeledContent("Ausgehend", value: "\(analytics.outgoingCount)")
            LabeledContent("Ungelesen", value: "\(analytics.unreadCount)")
            LabeledContent("Markiert", value: "\(analytics.starredCount)")
            LabeledContent("Ausstehend", value: "\(analytics.pendingCount)")
            LabeledContent("Fehler", value: "\(analytics.failedCount)")
        } header: {
            Text("Übersicht")
        }
    }

    private var securitySection: some View {
        SwiftUI.Section {
            if let peer {
                LabeledContent("Trust") {
                    Text(peer.trustState.rawValue)
                }
                LabeledContent("Peer ID") {
                    Text(String(peer.id.prefix(18)) + "…")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                LabeledContent("Safety Number") {
                    Text(peer.safetyNumber)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                Button {
                    UIPasteboard.general.string = peer.safetyNumber
                } label: {
                    Label("Safety Number kopieren", systemImage: "doc.on.doc")
                }
            } else {
                Label("Keine externe Gegenstelle. Dieser Chat bleibt lokal.", systemImage: "lock")
                    .foregroundStyle(Color.secondary)
            }
        } header: {
            Text("Sicherheit")
        }
    }

    private var exportSection: some View {
        SwiftUI.Section {
            ShareLink(item: service.exportTranscript(for: conversationID)) {
                Label("Chat als Text teilen", systemImage: "square.and.arrow.up")
            }

            Button {
                UIPasteboard.general.string = service.exportTranscript(for: conversationID)
            } label: {
                Label("Chat-Export kopieren", systemImage: "doc.on.doc")
            }
        } header: {
            Text("Export")
        } footer: {
            Text("Der Export ist Klartext und wird nur lokal nach deiner manuellen Aktion erzeugt.")
        }
    }

    private var actionsSection: some View {
        SwiftUI.Section {
            Button {
                service.toggleConversationPinned(id: conversationID)
            } label: {
                Label(conversation?.isPinned == true ? "Fixierung lösen" : "Oben fixieren", systemImage: conversation?.isPinned == true ? "pin.slash" : "pin")
            }

            Button {
                service.toggleConversationMuted(id: conversationID)
            } label: {
                Label(conversation?.isMuted == true ? "Benachrichtigung aktivieren" : "Chat stummschalten", systemImage: conversation?.isMuted == true ? "bell" : "bell.slash")
            }

            Button {
                service.markConversationRead(id: conversationID)
            } label: {
                Label("Als gelesen markieren", systemImage: "checkmark.circle")
            }

            Button {
                service.toggleConversationArchived(id: conversationID)
                dismiss()
            } label: {
                Label(conversation?.isArchived == true ? "Aus Archiv holen" : "Archivieren", systemImage: conversation?.isArchived == true ? "tray.and.arrow.up" : "archivebox")
            }

            if analytics.failedCount > 0 || analytics.pendingCount > 0 {
                Button {
                    Task { await service.retryPendingOutboundMessages() }
                } label: {
                    Label("Ausstehende Nachrichten erneut senden", systemImage: "arrow.clockwise")
                }
            }

            Button(role: .destructive) {
                service.clearConversationMessages(id: conversationID)
            } label: {
                Label("Nachrichtenverlauf leeren", systemImage: "trash")
            }
        } header: {
            Text("Aktionen")
        }
    }

    private var iconName: String {
        conversation?.peerID == nil ? "note.text" : "lock.shield"
    }

    private var iconTint: Color {
        guard conversation?.peerID != nil else { return .secondary }
        switch peer?.trustState {
        case .verified:
            return .green
        case .unverified:
            return .orange
        case .blocked:
            return .red
        case nil:
            return .red
        }
    }
}
