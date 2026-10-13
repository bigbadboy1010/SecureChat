import SwiftUI

private enum ConversationFilter: String, CaseIterable, Identifiable {
    case active
    case unread
    case starred
    case muted
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active:
            return "Aktiv"
        case .unread:
            return "Ungelesen"
        case .starred:
            return "Markiert"
        case .muted:
            return "Stumm"
        case .archived:
            return "Archiv"
        }
    }

    var systemImage: String {
        switch self {
        case .active:
            return "message"
        case .unread:
            return "message.badge"
        case .starred:
            return "star"
        case .muted:
            return "bell.slash"
        case .archived:
            return "archivebox"
        }
    }
}

struct ConversationListView: View {
    @ObservedObject var service: ConversationService
    var onAddContact: (() -> Void)? = nil
    @State private var newConversationTitle = ""
    @State private var selectedPeerID = ""
    @State private var showCreateSheet = false
    @State private var searchText = ""
    @State private var filter: ConversationFilter = .active
    @State private var showPairingSheet = false
    @State private var pendingDeletionIDs: [UUID] = []
    @State private var isConnecting = false

    private var isSearchActive: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var visibleConversations: [StoredConversation] {
        service.conversations.filter { storedConversation in
            switch filter {
            case .active:
                guard storedConversation.conversation.isArchived == false else { return false }
            case .unread:
                guard storedConversation.conversation.isArchived == false,
                      service.unreadCount(for: storedConversation.id) > 0 else { return false }
            case .starred:
                guard storedConversation.messages.contains(where: { $0.isStarred }) else { return false }
            case .muted:
                guard storedConversation.conversation.isMuted else { return false }
            case .archived:
                guard storedConversation.conversation.isArchived else { return false }
            }

            let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard needle.isEmpty == false else { return true }
            return storedConversation.conversation.title.localizedCaseInsensitiveContains(needle)
                || storedConversation.messages.contains { $0.body.localizedCaseInsensitiveContains(needle) }
                || (service.peerDisplayName(for: storedConversation.conversation.peerID)?.localizedCaseInsensitiveContains(needle) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                SwiftUI.Section {
                    roomHeader
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                SwiftUI.Section {
                    if visibleConversations.isEmpty {
                        if service.conversations.isEmpty && filter == .active && isSearchActive == false {
                            FirstRunConversationHint(
                                addContact: addContact,
                                createNote: { _ = service.createConversation(title: "Meine Notizen", peerID: nil) }
                            )
                        } else {
                            EmptyConversationView(filter: filter, isSearching: isSearchActive)
                        }
                    } else {
                        ForEach(visibleConversations) { storedConversation in
                            NavigationLink {
                                ChatView(service: service, storedConversation: storedConversation)
                            } label: {
                                ConversationRow(service: service, storedConversation: storedConversation)
                            }
                            .contextMenu {
                                Button {
                                    service.toggleConversationPinned(id: storedConversation.id)
                                } label: {
                                    Label(storedConversation.conversation.isPinned ? "Fixierung lösen" : "Oben fixieren", systemImage: storedConversation.conversation.isPinned ? "pin.slash" : "pin")
                                }

                                Button {
                                    service.markConversationRead(id: storedConversation.id)
                                } label: {
                                    Label("Als gelesen markieren", systemImage: "checkmark.circle")
                                }

                                Button {
                                    service.toggleConversationMuted(id: storedConversation.id)
                                } label: {
                                    Label(storedConversation.conversation.isMuted ? "Ungelesen-Badge aktivieren" : "Badge stummschalten", systemImage: storedConversation.conversation.isMuted ? "bell" : "bell.slash")
                                }

                                Button {
                                    service.toggleConversationArchived(id: storedConversation.id)
                                } label: {
                                    Label(storedConversation.conversation.isArchived ? "Aus Archiv holen" : "Archivieren", systemImage: storedConversation.conversation.isArchived ? "tray.and.arrow.up" : "archivebox")
                                }

                                Button(role: .destructive) {
                                    pendingDeletionIDs = [storedConversation.id]
                                } label: {
                                    Label("Chat löschen", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    service.toggleConversationPinned(id: storedConversation.id)
                                } label: {
                                    Label("Pin", systemImage: "pin")
                                }
                                .tint(.orange)

                                Button {
                                    service.markConversationRead(id: storedConversation.id)
                                } label: {
                                    Label("Gelesen", systemImage: "checkmark.circle")
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button {
                                    service.toggleConversationArchived(id: storedConversation.id)
                                } label: {
                                    Label("Archiv", systemImage: "archivebox")
                                }
                                .tint(.blue)
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                        }
                        .onDelete { indexSet in
                            pendingDeletionIDs = indexSet.map { visibleConversations[$0].id }
                        }
                    }
                } header: {
                    if filter != .active {
                        Text(filter.title)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(PrivateChatDesign.pageGradient.ignoresSafeArea())
            .navigationTitle("Chats")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Chats und Nachrichten suchen")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Picker("Chats anzeigen", selection: $filter) {
                            ForEach(ConversationFilter.allCases) { filter in
                                Label(filter.title, systemImage: filter.systemImage).tag(filter)
                            }
                        }

                        if service.totalUnreadCount() > 0 {
                            Divider()
                            Button {
                                service.markAllConversationsRead()
                            } label: {
                                Label("Alle als gelesen markieren", systemImage: "checkmark.circle")
                            }
                        }
                    } label: {
                        Image(systemName: filter == .active ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Chat-Filter: \(filter.title)")
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Chat erstellen")
                }
            }
            .refreshable {
                await service.syncRelayInbox()
            }
            .sheet(isPresented: $showCreateSheet) {
                createConversationSheet
            }
            .sheet(isPresented: $showPairingSheet) {
                PairingView(service: service)
            }
            .confirmationDialog("Chat lokal löschen?", isPresented: Binding(
                get: { pendingDeletionIDs.isEmpty == false },
                set: { if $0 == false { pendingDeletionIDs = [] } }
            ), titleVisibility: .visible) {
                Button(pendingDeletionIDs.count > 1 ? "\(pendingDeletionIDs.count) Chats löschen" : "Chat löschen", role: .destructive) {
                    let ids = pendingDeletionIDs
                    pendingDeletionIDs = []
                    ids.forEach { service.deleteConversation(id: $0) }
                }
                Button("Abbrechen", role: .cancel) { pendingDeletionIDs = [] }
            } message: {
                Text("Der Verlauf und lokale Anhänge werden von diesem Gerät entfernt. Bereits erhaltene Kopien bei Kontakten werden nicht gelöscht.")
            }
            .privateChatErrorAlert(service: service)
        }
    }

    private var roomHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                PrivateRoomMark().frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text("DEIN PRIVATER RAUM")
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(PrivateChatDesign.brandCyan)
                    Text("Für Gespräche. Für dich.")
                        .font(.headline)
                        .foregroundStyle(PrivateChatDesign.textPrimary)
                }
                Spacer(minLength: 0)
            }
            if service.securityState.transportMode == .localOnly {
                Text("Aktuell nur lokal. Verbinde den Relay, wenn du mit verifizierten Kontakten kommunizieren möchtest.")
                    .font(.subheadline)
                    .foregroundStyle(PrivateChatDesign.textSecondary)
                Button {
                    guard isConnecting == false else { return }
                    isConnecting = true
                    Task {
                        _ = await service.enablePrivateRoomRelay()
                        isConnecting = false
                    }
                } label: {
                    HStack(spacing: 10) {
                        if isConnecting { ProgressView() } else { Image(systemName: "network") }
                        Text(isConnecting ? "Verbindung wird eingerichtet …" : "PrivateRoom verbinden")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PrivateChatDesign.canvasBase)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(PrivateChatDesign.brandCyan, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isConnecting)
            } else {
                Label("Relay-Modus aktiviert", systemImage: "network")
                    .font(.caption)
                    .foregroundStyle(PrivateChatDesign.textSecondary)
                if service.pendingOutboxCount() > 0 {
                    Label("\(service.pendingOutboxCount()) Nachricht(en) noch ausstehend", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(PrivateChatDesign.warning)
                }
                if let summary = service.lastRelaySyncSummary {
                    Text("Zuletzt abgerufen: \(summary.receivedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(PrivateChatDesign.textSecondary)
                }
                Text("Nachrichten werden abgerufen, während die App geöffnet ist.")
                    .font(.caption)
                    .foregroundStyle(PrivateChatDesign.textSecondary)
            }
        }
        .privateChatGlassCard(padding: 20, cornerRadius: 24)
        .padding(.vertical, 6)
    }

    private func addContact() {
        if let onAddContact { onAddContact() } else { showPairingSheet = true }
    }

    private var createConversationSheet: some View {
        NavigationStack {
            Form {
                SwiftUI.Section {
                    TextField("Name", text: $newConversationTitle)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Chat")
                }

                SwiftUI.Section {
                    Picker("Kontakt", selection: $selectedPeerID) {
                        Text("Lokal / Notiz").tag("")
                        ForEach(service.verifiedPeers()) { peer in
                            Text(peer.displayName).tag(peer.id)
                        }
                    }
                } header: {
                    Text("Empfänger")
                } footer: {
                    Text("Nur geprüfte Kontakte stehen zur Auswahl. Eine lokale Notiz wird an niemanden gesendet.")
                }
            }
            .navigationTitle("Neuer Chat")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { showCreateSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Erstellen") {
                        let peerID = selectedPeerID.isEmpty ? nil : selectedPeerID
                        guard service.createConversation(title: newConversationTitle, peerID: peerID) != nil else { return }
                        newConversationTitle = ""
                        selectedPeerID = ""
                        showCreateSheet = false
                    }
                    .disabled(newConversationTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct FirstRunConversationHint: View {
    let addContact: () -> Void
    let createNote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Hier beginnt euer Gespräch.")
                        .font(.headline.weight(.semibold))
                    Text("Füge eine Person hinzu und vergleicht eure Sicherheitsnummern. Lokale Notizen bleiben nur auf diesem Gerät.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                addContact()
            } label: {
                Label("Kontakt hinzufügen", systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(PrivateChatDesign.brandCyan)
            .foregroundStyle(PrivateChatDesign.canvasBase)

            Button(action: createNote) {
                Label("Private Notiz anlegen", systemImage: "note.text")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
        .privateChatGlassCard(padding: 16, cornerRadius: 22, highlighted: true)
        .padding(.vertical, 4)
    }
}

private struct EmptyConversationView: View {
    let filter: ConversationFilter
    let isSearching: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private var icon: String {
        if isSearching { return "magnifyingglass" }
        switch filter {
        case .active: return "message.badge"
        case .unread: return "checkmark.message"
        case .starred: return "star"
        case .muted: return "bell.slash"
        case .archived: return "archivebox"
        }
    }

    private var title: String {
        if isSearching { return "Nichts gefunden" }
        switch filter {
        case .active: return "Noch keine aktiven Chats"
        case .unread: return "Alles gelesen"
        case .starred: return "Keine markierten Nachrichten"
        case .muted: return "Keine stummen Chats"
        case .archived: return "Archiv ist leer"
        }
    }

    private var subtitle: String {
        if isSearching { return "Passe den Suchbegriff oder den Filter an." }
        switch filter {
        case .active: return "Deine privaten Gespräche erscheinen hier, sobald du einen Kontakt hinzugefügt hast."
        case .unread: return "Neue eingehende Nachrichten erscheinen hier."
        case .starred: return "Markiere wichtige Nachrichten über das Nachrichten-Kontextmenü."
        case .muted: return "Stummgeschaltete Chats erscheinen hier."
        case .archived: return "Archivierte Chats kannst du über das Kontextmenü wiederherstellen."
        }
    }
}

private struct RelaySyncSummaryRow: View {
    let summary: RelayInboxSyncSummary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Relay Sync")
                    .font(.subheadline.weight(.semibold))
                Text("Empfangen: \(summary.processedCount), Duplikate: \(summary.duplicateCount), bestätigt: \(summary.deletedCount), Receipts: \(summary.deliveryReceiptSentCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(summary.receivedAt, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct OutboxRetrySummaryRow: View {
    let summary: OutboxRetrySummary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.circle")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Outbox Retry")
                    .font(.subheadline.weight(.semibold))
                Text("Gesendet: \(summary.sentCount), fehlgeschlagen: \(summary.failedCount), versucht: \(summary.attemptedCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(summary.completedAt, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ConversationRow: View {
    @ObservedObject var service: ConversationService
    let storedConversation: StoredConversation

    private var unreadCount: Int {
        service.unreadCount(for: storedConversation.id)
    }

    private var peer: TrustedPeer? {
        service.trustedPeers.first { $0.id == storedConversation.conversation.peerID }
    }

    private var peerIcon: String {
        if storedConversation.conversation.peerID == nil { return "note.text" }
        switch peer?.trustState {
        case .verified: return "checkmark.shield"
        case .blocked: return "hand.raised"
        case .unverified, nil: return "person.crop.circle.badge.questionmark"
        }
    }

    private var peerTint: Color {
        if storedConversation.conversation.peerID == nil { return PrivateChatDesign.textSecondary }
        switch peer?.trustState {
        case .verified: return PrivateChatDesign.brandCyan
        case .blocked: return PrivateChatDesign.danger
        case .unverified, nil: return PrivateChatDesign.warning
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(peerTint.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: peerIcon)
                    .foregroundStyle(peerTint)
                if unreadCount > 0 {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if storedConversation.conversation.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if storedConversation.conversation.isMuted {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(storedConversation.conversation.title)
                        .font(.headline)
                        .lineLimit(1)
                    if unreadCount > 0 {
                        Text("\(unreadCount)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.red, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Text(storedConversation.conversation.updatedAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    if let lastMessage = storedConversation.messages.last {
                        if lastMessage.isStarred {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.orange)
                        }
                        Text(service.securityState.hideMessagePreviews ? "Nachricht verborgen" : lastMessage.body)
                            .font(.subheadline)
                            .foregroundStyle(service.securityState.hideMessagePreviews ? Color.secondary : (unreadCount > 0 ? Color.primary : Color.secondary))
                            .lineLimit(1)

                        if lastMessage.isIncoming == false {
                            Label(lastMessage.status.localizedTitle, systemImage: lastMessage.status.systemImageName)
                                .labelStyle(.iconOnly)
                                .font(.caption2)
                                .foregroundStyle(statusColor(for: lastMessage.status))
                        }
                    } else {
                        Text("Keine Nachrichten")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let peerName = service.peerDisplayName(for: storedConversation.conversation.peerID) {
                    Text("\(peerName) · \(peer?.trustState == .verified ? "Identität geprüft" : (peer?.trustState == .blocked ? "Blockiert" : "Prüfung offen"))")
                        .font(.caption)
                        .foregroundStyle(peerTint)
                        .lineLimit(1)
                } else if storedConversation.conversation.peerID == nil {
                    Text("Nur auf diesem Gerät")
                        .font(.caption)
                        .foregroundStyle(PrivateChatDesign.textSecondary)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
        .privateChatGlassCard(padding: 10, cornerRadius: 20, highlighted: unreadCount > 0)
    }

    private func statusColor(for status: MessageDeliveryStatus) -> Color {
        switch status {
        case .queued, .sending:
            return .orange
        case .sentToRelay, .sent, .delivered:
            return .secondary
        case .failed:
            return .red
        }
    }
}
