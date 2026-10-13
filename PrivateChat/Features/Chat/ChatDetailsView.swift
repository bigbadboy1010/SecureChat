import SwiftUI
import UIKit

struct ChatDetailsView: View {
    @ObservedObject var service: ConversationService
    let conversationID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var editedTitle = ""
    @State private var showClearHistoryConfirmation = false
    @State private var showExport = false

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
            .sheet(isPresented: $showExport) {
                PrivateRoomTranscriptExportView(text: service.exportTranscript(for: conversationID))
            }
            .confirmationDialog("Verlauf auf diesem Gerät leeren?", isPresented: $showClearHistoryConfirmation, titleVisibility: .visible) {
                Button("Verlauf leeren", role: .destructive) {
                    service.clearConversationMessages(id: conversationID)
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Nachrichten und zugehörige lokale Anhänge werden entfernt. Bereits erhaltene Kopien beim Kontakt bleiben bestehen.")
            }
            .privateChatErrorAlert(service: service)
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
                        Label("Badge stumm", systemImage: "bell.slash.fill")
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
                LabeledContent("Identität") {
                    Text(peer.trustState == .verified ? "Von dir geprüft" : (peer.trustState == .blocked ? "Blockiert" : "Prüfung offen"))
                }
                LabeledContent("Peer ID") {
                    Text(String(peer.id.prefix(18)) + "…")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                LabeledContent("Sicherheitsnummer") {
                    Text(peer.safetyNumber)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                NavigationLink {
                    SafetyNumberView(service: service, peer: peer)
                } label: {
                    Label("Sicherheitsnummer vergleichen", systemImage: "checkmark.shield")
                }

                Button {
                    PrivateRoomClipboard.copy(peer.safetyNumber)
                } label: {
                    Label("Sicherheitsnummer lokal kopieren", systemImage: "doc.on.doc")
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
            Button {
                showExport = true
            } label: {
                Label("Klartext-Export ansehen", systemImage: "doc.text")
            }
        } header: {
            Text("Export")
        } footer: {
            Text("Ein Export enthält lesbare Nachrichten. Außerhalb von PrivateRoom gilt der App-Schutz nicht mehr.")
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
                Label(conversation?.isMuted == true ? "Ungelesen-Badge aktivieren" : "Ungelesen-Badge stummschalten", systemImage: conversation?.isMuted == true ? "bell" : "bell.slash")
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
                    Task { await service.retryPendingOutboundMessages(conversationID: conversationID) }
                } label: {
                    Label("Ausstehende in diesem Chat erneut senden", systemImage: "arrow.clockwise")
                }
            }

            Button(role: .destructive) {
                showClearHistoryConfirmation = true
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

private struct PrivateRoomTranscriptExportView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Label("Dieser Export ist unverschlüsselter Text.", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                        .foregroundStyle(PrivateChatDesign.warning)
                    Text("Prüfe den Inhalt vor dem Teilen. Andere Apps oder Personen können eine Kopie behalten. Die Verschlüsselung und Sperre von PrivateRoom gelten dort nicht.")
                        .font(.subheadline)
                        .foregroundStyle(PrivateChatDesign.textSecondary)
                    Text(text)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .privateChatGlassCard(padding: 18)
                    ShareLink(item: text) {
                        Label("Diesen Text teilen", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        PrivateRoomClipboard.copy(text)
                        didCopy = true
                    } label: {
                        Label(didCopy ? "Lokal kopiert · läuft nach 1 Minute ab" : "Nur auf diesem Gerät kopieren", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(24)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(PrivateChatDesign.pageGradient.ignoresSafeArea())
            .navigationTitle("Export prüfen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Schließen") { dismiss() } }
            }
        }
    }
}
