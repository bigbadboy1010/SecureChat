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
}

struct ConversationListView: View {
    @ObservedObject var service: ConversationService
    @State private var newConversationTitle = ""
    @State private var selectedPeerID = ""
    @State private var showCreateSheet = false
    @State private var searchText = ""
    @State private var filter: ConversationFilter = .active

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
                dashboardHeader

                if service.totalUnreadCount() > 0 {
                    SwiftUI.Section {
                        Button {
                            service.markAllConversationsRead()
                        } label: {
                            Label("Alle Chats als gelesen markieren", systemImage: "checkmark.circle")
                        }
                    }
                }

                if let summary = service.lastRelaySyncSummary {
                    RelaySyncSummaryRow(summary: summary)
                }

                if let summary = service.lastOutboxRetrySummary {
                    OutboxRetrySummaryRow(summary: summary)
                }

                SwiftUI.Section {
                    if visibleConversations.isEmpty {
                        EmptyConversationView(filter: filter, isSearching: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
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
                    Text(filter.title)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(PrivateChatDesign.pageGradient.ignoresSafeArea())
            .navigationTitle("Chats")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Chats und Nachrichten suchen")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task { await service.syncRelayInbox() }
                    } label: {
                        if service.isRelaySyncRunning {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.down.circle")
                        }
                    }
                    .accessibilityLabel("Relay Inbox abrufen")
                    .disabled(service.isRelaySyncRunning || service.securityState.transportMode != .relayAllowed)
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        Task { await service.retryPendingOutboundMessages() }
                    } label: {
                        if service.isOutboxRetryRunning {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise.circle")
                        }
                    }
                    .accessibilityLabel("Outbox erneut senden")
                    .disabled(service.isOutboxRetryRunning || service.pendingOutboxCount() == 0)

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

    private var dashboardHeader: some View {
        SwiftUI.Section {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Filter", selection: $filter) {
                    ForEach(ConversationFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    MiniMetric(title: "Ungelesen", value: "\(service.totalUnreadCount())", systemImage: "bell.badge")
                    MiniMetric(title: "Outbox", value: "\(service.pendingOutboxCount())", systemImage: "tray.and.arrow.up")
                    MiniMetric(title: "Archiv", value: "\(service.archivedConversationCount())", systemImage: "archivebox")
                }

                HStack(spacing: 10) {
                    MiniMetric(title: "Markiert", value: "\(service.starredMessageCount())", systemImage: "star")
                    MiniMetric(title: "Stumm", value: "\(service.mutedConversationCount())", systemImage: "bell.slash")
                    MiniMetric(title: "Fehler", value: "\(service.failedMessageCount())", systemImage: "exclamationmark.triangle")
                }

                if service.securityState.hideMessagePreviews {
                    Label("Vorschau-Schutz aktiv", systemImage: "eye.slash")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(.vertical, 4)
            .privateChatGlassCard(padding: 14, cornerRadius: 22, highlighted: service.totalUnreadCount() > 0 || service.pendingOutboxCount() > 0)
        }
        .listRowBackground(Color.clear)
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

private struct MiniMetric: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(.headline.weight(.bold))
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PrivateChatDesign.subtleBorder, lineWidth: 1)
        }
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
