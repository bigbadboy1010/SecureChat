import SwiftUI

struct PairingView: View {
    @ObservedObject var service: ConversationService
    @State private var inboundPairingCode = ""
    @State private var localPairingCode = ""
    @State private var localDisplayName = ""
    @State private var showScanner = false
    @State private var showProfile = false
    @State private var importMessage: String?
    @State private var chatToOpen: StoredConversation?
    @State private var peerToBlock: TrustedPeer?

    var body: some View {
        NavigationStack {
            List {
                SwiftUI.Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Ein Kontakt.\nEin bewusster Anfang.")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(PrivateChatDesign.textPrimary)
                        Text("Tauscht eure Codes aus. Danach vergleicht ihr die SC3-Sicherheitsnummer auf beiden Geräten über einen vertrauten zweiten Kanal.")
                            .font(.subheadline)
                            .foregroundStyle(PrivateChatDesign.textSecondary)
                        Button {
                            showScanner = true
                        } label: {
                            Label("Kontakt-Code scannen", systemImage: "qrcode.viewfinder")
                                .font(.headline)
                                .foregroundStyle(PrivateChatDesign.canvasBase)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(PrivateChatDesign.brandCyan, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        DisclosureGroup("Code einfügen") {
                            TextEditor(text: $inboundPairingCode)
                                .frame(minHeight: 100)
                                .font(.caption.monospaced())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .accessibilityLabel("Kontakt-Code")
                            Button("Kontakt übernehmen") { importInboundPairingCode() }
                                .frame(minHeight: 44)
                                .disabled(inboundPairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        if let importMessage {
                            Label(importMessage, systemImage: "person.crop.circle.badge.checkmark")
                                .font(.footnote)
                                .foregroundStyle(PrivateChatDesign.brandCyan)
                        }
                    }
                    .privateChatGlassCard(padding: 20, cornerRadius: 24)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                SwiftUI.Section {
                    if service.trustedPeers.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Noch ganz für dich.").font(.headline)
                            Text("Hier erscheinen deine Kontakte. Ein importierter Code ist noch keine bestätigte Identität.")
                                .font(.subheadline)
                                .foregroundStyle(PrivateChatDesign.textSecondary)
                        }
                        .padding(.vertical, 12)
                    } else {
                        ForEach(service.trustedPeers) { peer in
                            contactRow(peer)
                        }
                    }
                } header: { Text("Deine Kontakte") }
                SwiftUI.Section {
                    DisclosureGroup("Mein QR-Code · \(service.localIdentity.displayName)") {
                        VStack(spacing: 14) {
                            if localPairingCode.isEmpty {
                                Text("Code noch nicht verfügbar")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(height: 180)
                            } else {
                                QRCodeImageView(payload: localPairingCode)
                                    .frame(width: 210, height: 210)
                                    .padding(16)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 20))
                            }
                            Text("Dein öffentlicher Name und deine öffentlichen Schlüssel. Private Schlüssel bleiben auf diesem Gerät.")
                                .font(.footnote)
                                .foregroundStyle(PrivateChatDesign.textSecondary)
                                .multilineTextAlignment(.center)
                            ShareLink(item: localPairingCode) {
                                Label("Meinen Code teilen", systemImage: "square.and.arrow.up")
                                    .frame(minHeight: 44)
                            }
                            .disabled(localPairingCode.isEmpty)
                            Button("Code neu laden", action: refreshLocalPairingCode)
                                .font(.footnote)
                                .frame(minHeight: 44)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    Button {
                        localDisplayName = service.localIdentity.displayName
                        showProfile = true
                    } label: {
                        Label("Meinen Anzeigenamen bearbeiten", systemImage: "person.crop.circle")
                    }
                } header: { Text("Das bist du") }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(PrivateChatDesign.pageGradient.ignoresSafeArea())
            .navigationTitle("Kontakte")
            .privateChatErrorAlert(service: service)
            .onAppear { refreshLocalPairingCode() }
            .sheet(isPresented: $showScanner) {
                NavigationStack {
                    QRScannerView { code in
                        inboundPairingCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
                        showScanner = false
                        Task { @MainActor in importInboundPairingCode() }
                    }
                    .navigationTitle("Kontakt-Code scannen")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Schließen") { showScanner = false }
                        }
                    }
                }
            }
            .sheet(isPresented: $showProfile) { profileSheet }
            .sheet(item: $chatToOpen) { stored in
                NavigationStack {
                    ChatView(service: service, storedConversation: stored)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Schließen") { chatToOpen = nil }
                            }
                        }
                }
            }
            .confirmationDialog("Kontakt blockieren?", isPresented: Binding(
                get: { peerToBlock != nil },
                set: { if $0 == false { peerToBlock = nil } }
            ), titleVisibility: .visible) {
                Button("Blockieren", role: .destructive) {
                    if let peerToBlock { service.blockPeer(id: peerToBlock.id) }
                    peerToBlock = nil
                }
                Button("Abbrechen", role: .cancel) { peerToBlock = nil }
            } message: {
                Text("An diesen Kontakt wird nicht mehr gesendet. Der lokale Verlauf bleibt erhalten. Zum erneuten Freigeben ist eine neue Prüfung nötig.")
            }
        }
    }

    private func contactRow(_ peer: TrustedPeer) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(String(peer.displayName.prefix(1)).uppercased())
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(PrivateChatDesign.brandCyan)
                    .frame(width: 44, height: 44)
                    .background(PrivateChatDesign.canvasHigh, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(peer.displayName).font(.headline)
                    Label(trustTitle(peer.trustState), systemImage: trustIcon(peer.trustState))
                        .font(.caption)
                        .foregroundStyle(trustTint(peer.trustState))
                }
                Spacer(minLength: 0)
                Menu {
                    if peer.trustState == .blocked {
                        Button("Zur erneuten Prüfung freigeben") { service.unblockPeerAsUnverified(id: peer.id) }
                    } else {
                        if peer.trustState == .verified {
                            Button("Verifizierung zurücknehmen") { service.unblockPeerAsUnverified(id: peer.id) }
                        }
                        Button("Kontakt blockieren", role: .destructive) { peerToBlock = peer }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Aktionen für \(peer.displayName)")
            }
            if peer.trustState == .verified {
                Button { openChat(with: peer) } label: {
                    Label("Chat öffnen", systemImage: "bubble.left.and.bubble.right")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            } else if peer.trustState == .unverified {
                NavigationLink {
                    SafetyNumberView(service: service, peer: peer)
                } label: {
                    Label("Sicherheitsnummer vergleichen", systemImage: "checkmark.shield")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var profileSheet: some View {
        NavigationStack {
            Form {
                SwiftUI.Section {
                    TextField("Dein Anzeigename", text: $localDisplayName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Der Name wird mit deinem öffentlichen Kontakt-Code geteilt. Bis zu 80 Zeichen; nicht unterstützte Sonderzeichen werden beim Speichern entfernt.")
                }
            }
            .navigationTitle("Dein Anzeigename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { showProfile = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        guard service.updateLocalDisplayName(localDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
                        localDisplayName = service.localIdentity.displayName
                        refreshLocalPairingCode()
                        showProfile = false
                    }
                    .disabled(localDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func refreshLocalPairingCode() {
        do { localPairingCode = try service.makeLocalPairingCode() }
        catch { localPairingCode = ""; service.reportError(error) }
    }

    private func importInboundPairingCode() {
        let code = inboundPairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.isEmpty == false else { return }
        guard service.importPeer(from: code) else { importMessage = nil; return }
        inboundPairingCode = ""
        importMessage = "Code übernommen. Vergleicht jetzt eure Sicherheitsnummern."
    }

    private func openChat(with peer: TrustedPeer) {
        guard peer.trustState == .verified else { return }
        if let existing = service.conversations.first(where: { $0.conversation.peerID == peer.id }) {
            if existing.conversation.isArchived { service.toggleConversationArchived(id: existing.id) }
            chatToOpen = service.conversations.first(where: { $0.id == existing.id })
        } else if let id = service.createConversation(title: peer.displayName, peerID: peer.id) {
            chatToOpen = service.conversations.first(where: { $0.id == id })
        }
    }

    private func trustTitle(_ state: TrustState) -> String {
        switch state {
        case .verified: return "Identität von dir geprüft"
        case .unverified: return "Prüfung noch offen"
        case .blocked: return "Kontakt blockiert"
        }
    }

    private func trustIcon(_ state: TrustState) -> String {
        switch state {
        case .verified: return "checkmark.seal"
        case .unverified: return "person.crop.circle.badge.questionmark"
        case .blocked: return "hand.raised"
        }
    }

    private func trustTint(_ state: TrustState) -> Color {
        switch state {
        case .verified: return PrivateChatDesign.brandCyan
        case .unverified: return PrivateChatDesign.warning
        case .blocked: return PrivateChatDesign.danger
        }
    }
}
