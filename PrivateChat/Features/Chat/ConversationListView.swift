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
    @State private var newConversationTitle = ""
    @State private var selectedPeerID = ""
    @State private var showCreateSheet = false
    @State private var searchText = ""
    @State private var filter: ConversationFilter = .active

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
                    if visibleConversations.isEmpty {
                        if service.conversations.isEmpty && filter == .active && isSearchActive == false {
                            FirstRunConversationHint {
                                _ = service.createSoloTestConversation()
                            }
                        }
                        EmptyConversationView(filter: filter, isSearching: isSearchActive)
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
                                    Label(storedConversation.conversation.isMuted ? "Benachrichtigung aktivieren" : "Stummschalten", systemImage: storedConversation.conversation.isMuted ? "bell" : "bell.slash")
                                }

                                Button {
                                    service.toggleConversationArchived(id: storedConversation.id)
                                } label: {
                                    Label(storedConversation.conversation.isArchived ? "Aus Archiv holen" : "Archivieren", systemImage: storedConversation.conversation.isArchived ? "tray.and.arrow.up" : "archivebox")
                                }

                                Button(role: .destructive) {
                                    service.deleteConversation(id: storedConversation.id)
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
                            indexSet.map { visibleConversations[$0].id }.forEach { service.deleteConversation(id: $0) }
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
            .privateChatErrorAlert(service: service)
        }
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
                    Text("Verifizierter Peer")
                } footer: {
                    Text("Nachrichten an Peers sind erst nach Safety-Number-Verifizierung möglich.")
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
                        service.createConversation(title: newConversationTitle, peerID: peerID)
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
    let createSoloTestChat: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Dein erster Chat")
                        .font(.headline.weight(.semibold))
                    Text("Starte lokal oder füge unter Kontakte eine Person hinzu.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                createSoloTestChat()
            } label: {
                Label("Lokalen Chat starten", systemImage: "message.badge")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
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
        case .active: return "Erstelle einen lokalen Chat oder verknüpfe zuerst einen Peer über Pairing."
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

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(storedConversation.conversation.peerID == nil ? Color.secondary.opacity(0.18) : Color.accentColor.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: storedConversation.conversation.peerID == nil ? "note.text" : "lock.shield")
                    .foregroundStyle(storedConversation.conversation.peerID == nil ? Color.secondary : Color.accentColor)
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
                    Text(peerName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
