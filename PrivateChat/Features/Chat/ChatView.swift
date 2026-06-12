import SwiftUI
import UIKit

struct ChatView: View {
    @ObservedObject var service: ConversationService
    let storedConversation: StoredConversation

    @State private var draft = ""
    @State private var messageSearchText = ""
    @State private var showDetails = false
    @State private var selectedMessage: ChatMessage?
    @State private var scrollUpdateTask: Task<Void, Never>?

    private let quickReplies = [
        "Bin dran.",
        "Ich melde mich gleich.",
        "Passt für mich.",
        "Bitte kurz bestätigen."
    ]

    private var currentConversation: StoredConversation {
        service.conversations.first { $0.id == storedConversation.id } ?? storedConversation
    }

    private var isPeerConversation: Bool {
        currentConversation.conversation.peerID != nil
    }

    private var displayedMessages: [ChatMessage] {
        let needle = messageSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.isEmpty == false else {
            return currentConversation.messages
        }
        return currentConversation.messages.filter { message in
            message.body.localizedCaseInsensitiveContains(needle)
                || message.status.localizedTitle.localizedCaseInsensitiveContains(needle)
                || message.id.uuidString.localizedCaseInsensitiveContains(needle)
        }
    }

    private var isMessageSearchActive: Bool {
        messageSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var legacyDraftStorageKey: String {
        "PrivateChat.Draft.\(currentConversation.id.uuidString)"
    }

    private var canSend: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        (currentConversation.conversation.peerID == nil || service.securityState.transportMode == .relayAllowed)
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { draft },
            set: { newValue in
                updateDraft(newValue, persist: true)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if isPeerConversation {
                SecurePeerBanner(service: service, peerID: currentConversation.conversation.peerID)
            } else {
                LocalNoteBanner()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if currentConversation.messages.isEmpty {
                            EmptyChatState(isPeerConversation: isPeerConversation)
                                .padding(.top, 80)
                        } else if displayedMessages.isEmpty {
                            EmptySearchState(query: messageSearchText)
                                .padding(.top, 80)
                        }

                        ForEach(displayedMessages) { message in
                            MessageBubble(
                                service: service,
                                conversationID: currentConversation.id,
                                message: message,
                                onShowDetails: { selectedMessage = message }
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 14)
                }
                .background(PrivateChatDesign.pageGradient)
                .task(id: currentConversation.messages.last?.id) {
                    scheduleDeferredScrollAndRead(proxy: proxy)
                }
                .task(id: currentConversation.id) {
                    restoreDraftIfAvailable()
                    deferMarkConversationRead()
                    guard isMessageSearchActive == false else { return }
                    scrollToBottom(proxy: proxy, animated: false)
                }
            }

            composer
        }
        .navigationTitle(currentConversation.conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $messageSearchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "In diesem Chat suchen")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if currentConversation.conversation.isMuted {
                    Image(systemName: "bell.slash.fill")
                        .foregroundStyle(Color.secondary)
                }
                if currentConversation.conversation.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(Color.secondary)
                }

                Button {
                    showDetails = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("Chat-Details")

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
        }
        .sheet(isPresented: $showDetails) {
            ChatDetailsView(service: service, conversationID: currentConversation.id)
        }
        .sheet(item: $selectedMessage) { message in
            MessageDetailView(service: service, conversationID: currentConversation.id, message: message)
        }
        .onDisappear {
            scrollUpdateTask?.cancel()
            scrollUpdateTask = nil
            persistDraftValue(draft)
            deferMarkConversationRead()
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            Divider()

            if currentConversation.conversation.peerID != nil && service.securityState.transportMode == .localOnly {
                Label("Relay ist deaktiviert. Aktiviere Security → Transport → Relay erlaubt.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            if service.securityState.reduceKeyboardSuggestions {
                Label("Keyboard-Vorschläge reduziert", systemImage: "keyboard")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickReplies, id: \.self) { reply in
                            Button(reply) {
                                updateDraft(reply, persist: true)
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal)
                }
            } else {
                HStack {
                    Label("Entwurf wird verschlüsselt lokal gespeichert", systemImage: "lock")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                    Spacer()
                    Button("Entwurf löschen") {
                        updateDraft("", persist: true)
                    }
                    .font(.caption2)
                }
                .padding(.horizontal)
            }

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .trailing, spacing: 4) {
                    composerInput

                    Text("\(draft.count) Zeichen")
                        .font(.caption2)
                        .foregroundStyle(draft.count > 1_500 ? Color.orange : Color.secondary)
                }

                Button {
                    sendDraft()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.45))
                .disabled(canSend == false)
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PrivateChatDesign.subtleBorder)
                .frame(height: 1)
        }
    }


    @ViewBuilder
    private var composerInput: some View {
        if service.securityState.reduceKeyboardSuggestions {
            PrivacyComposerTextField(
                text: draftBinding,
                placeholder: "Nachricht",
                onSubmit: {
                    if canSend {
                        sendDraft()
                    }
                }
            )
            .frame(minHeight: 24)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PrivateChatDesign.subtleBorder, lineWidth: 1)
            }
        } else {
            TextField("Nachricht", text: draftBinding, axis: .vertical)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
                .submitLabel(.send)
                .lineLimit(1...6)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PrivateChatDesign.subtleBorder, lineWidth: 1)
            }
        }
    }

    private func sendDraft() {
        let body = draft
        updateDraft("", persist: true)
        Task { await service.sendMessage(conversationID: currentConversation.id, body: body) }
    }

    private func restoreDraftIfAvailable() {
        guard draft.isEmpty else { return }
        let legacyValue = UserDefaults.standard.string(forKey: legacyDraftStorageKey)
        let restoredDraft = service.loadDraft(conversationID: currentConversation.id, legacyUserDefaultsValue: legacyValue)
        if legacyValue != nil {
            UserDefaults.standard.removeObject(forKey: legacyDraftStorageKey)
        }
        updateDraft(restoredDraft, persist: false)
    }

    private func updateDraft(_ newValue: String, persist: Bool) {
        guard draft != newValue else { return }
        draft = newValue
        if persist {
            persistDraftValue(newValue)
        }
    }

    private func persistDraftValue(_ value: String) {
        let trimmedDraft = value.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.removeObject(forKey: legacyDraftStorageKey)
        if trimmedDraft.isEmpty {
            service.deleteDraft(conversationID: currentConversation.id)
        } else {
            service.saveDraft(value, conversationID: currentConversation.id)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        guard let lastID = currentConversation.messages.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.22)) { proxy.scrollTo(lastID, anchor: .bottom) }
        } else {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }

    private func scheduleDeferredScrollAndRead(proxy: ScrollViewProxy) {
        guard isMessageSearchActive == false else { return }
        let conversationID = currentConversation.id
        let lastMessageID = currentConversation.messages.last?.id
        scrollUpdateTask?.cancel()
        scrollUpdateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard Task.isCancelled == false else { return }
            guard currentConversation.id == conversationID else { return }
            if let lastMessageID {
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(lastMessageID, anchor: .bottom)
                }
            }
            service.markConversationRead(id: conversationID)
        }
    }

    private func deferMarkConversationRead() {
        let conversationID = currentConversation.id
        DispatchQueue.main.async {
            service.markConversationRead(id: conversationID)
        }
    }
}

private struct EmptyChatState: View {
    let isPeerConversation: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isPeerConversation ? "lock.bubble.left.right" : "note.text")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Color.secondary)
            Text(isPeerConversation ? "Sicherer Chat bereit" : "Lokale Notiz bereit")
                .font(.headline)
            Text(isPeerConversation ? "Nachrichten werden lokal verschlüsselt, signiert und über den Relay nur als geschützte Pakete übertragen." : "Dieser Chat bleibt lokal auf diesem Gerät.")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}

private struct EmptySearchState: View {
    let query: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.secondary)
            Text("Keine Treffer")
                .font(.headline)
            Text("Für „\(query.trimmingCharacters(in: .whitespacesAndNewlines))“ wurde in diesem Chat nichts gefunden.")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}

private struct LocalNoteBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
            Text("Lokaler Notiz-Chat. Keine Netzwerkübertragung.")
                .font(.caption)
            Spacer()
        }
        .foregroundStyle(Color.secondary)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08))
    }
}

private struct SecurePeerBanner: View {
    @ObservedObject var service: ConversationService
    let peerID: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 9)
        .background(color.opacity(0.10))
    }

    private var peer: TrustedPeer? {
        guard let peerID else { return nil }
        return service.trustedPeers.first(where: { $0.id == peerID })
    }

    private var title: String {
        guard let peer else { return "Kontakt nicht gefunden" }
        switch peer.trustState {
        case .verified:
            return "Verifizierter E2E-Chat mit \(peer.displayName)"
        case .unverified:
            return "Kontakt ist noch nicht verifiziert"
        case .blocked:
            return "Kontakt ist blockiert"
        }
    }

    private var subtitle: String? {
        guard let peer else { return nil }
        return "Safety: " + String(peer.safetyNumber.prefix(23)) + "…"
    }

    private var icon: String {
        switch peer?.trustState {
        case .verified:
            return "lock.shield.fill"
        case .unverified:
            return "questionmark.shield"
        case .blocked:
            return "hand.raised.fill"
        case nil:
            return "exclamationmark.triangle"
        }
    }

    private var color: Color {
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

private struct MessageBubble: View {
    @ObservedObject var service: ConversationService
    let conversationID: UUID
    let message: ChatMessage
    let onShowDetails: () -> Void

    var body: some View {
        HStack(alignment: .bottom) {
            if message.isIncoming == false {
                Spacer(minLength: 48)
            }

            VStack(alignment: message.isIncoming ? .leading : .trailing, spacing: 5) {
                VStack(alignment: message.isIncoming ? .leading : .trailing, spacing: 4) {
                    if message.isStarred {
                        Label("Markiert", systemImage: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(message.isIncoming ? Color.orange : Color.white.opacity(0.86))
                    }

                    Text(message.body)
                        .font(.body)
                        .foregroundStyle(message.isIncoming ? Color.primary : Color.white)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = message.body
                    } label: {
                        Label("Kopieren", systemImage: "doc.on.doc")
                    }

                    Button {
                        service.toggleMessageStarred(messageID: message.id, conversationID: conversationID)
                    } label: {
                        Label(message.isStarred ? "Markierung entfernen" : "Markieren", systemImage: message.isStarred ? "star.slash" : "star")
                    }

                    Button {
                        onShowDetails()
                    } label: {
                        Label("Details", systemImage: "info.circle")
                    }

                    if message.isIncoming == false && (message.status == .failed || message.status == .queued) {
                        Button {
                            Task { await service.retryMessage(messageID: message.id, conversationID: conversationID) }
                        } label: {
                            Label("Erneut senden", systemImage: "arrow.clockwise")
                        }
                    }

                    Button(role: .destructive) {
                        service.deleteMessage(messageID: message.id, conversationID: conversationID)
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }

                HStack(spacing: 5) {
                    Text(message.createdAt, style: .time)
                    if message.isIncoming == false {
                        Image(systemName: message.status.systemImageName)
                        Text(message.status.localizedTitle)
                    } else if message.readAt != nil {
                        Image(systemName: "eye")
                    }
                }
                .font(.caption2)
                .foregroundStyle(Color.secondary)
            }

            if message.isIncoming {
                Spacer(minLength: 48)
            }
        }
    }

    private var bubbleBackground: some ShapeStyle {
        if message.isIncoming {
            return AnyShapeStyle(Color.secondary.opacity(0.15))
        }
        switch message.status {
        case .failed:
            return AnyShapeStyle(Color.red.opacity(0.82))
        case .queued, .sending:
            return AnyShapeStyle(Color.orange.opacity(0.82))
        case .sentToRelay, .sent, .delivered:
            return AnyShapeStyle(Color.accentColor)
        }
    }
}

private struct MessageDetailView: View {
    @ObservedObject var service: ConversationService
    let conversationID: UUID
    let message: ChatMessage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                SwiftUI.Section {
                    Text(message.body)
                        .textSelection(.enabled)
                    LabeledContent("Richtung", value: message.isIncoming ? "Eingehend" : "Ausgehend")
                    LabeledContent("Status", value: message.status.localizedTitle)
                    LabeledContent("Erstellt") {
                        Text(message.createdAt, format: .dateTime.day().month().year().hour().minute().second())
                    }
                    if let readAt = message.readAt {
                        LabeledContent("Gelesen") {
                            Text(readAt, format: .dateTime.day().month().year().hour().minute().second())
                        }
                    }
                    LabeledContent("Message ID") {
                        Text(message.id.uuidString)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("Nachricht")
                }

                SwiftUI.Section {
                    Button {
                        UIPasteboard.general.string = message.body
                    } label: {
                        Label("Text kopieren", systemImage: "doc.on.doc")
                    }

                    Button {
                        service.toggleMessageStarred(messageID: message.id, conversationID: conversationID)
                        dismiss()
                    } label: {
                        Label(message.isStarred ? "Markierung entfernen" : "Nachricht markieren", systemImage: message.isStarred ? "star.slash" : "star")
                    }

                    if message.isIncoming == false && (message.status == .failed || message.status == .queued) {
                        Button {
                            Task {
                                await service.retryMessage(messageID: message.id, conversationID: conversationID)
                                dismiss()
                            }
                        } label: {
                            Label("Erneut senden", systemImage: "arrow.clockwise")
                        }
                    }
                } header: {
                    Text("Aktionen")
                }
            }
            .navigationTitle("Nachricht")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}


private struct PrivacyComposerTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.borderStyle = .none
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.smartInsertDeleteType = .no
        textField.textContentType = nil
        textField.keyboardType = .default
        textField.returnKeyType = .send
        textField.clearButtonMode = .never
        textField.enablesReturnKeyAutomatically = true
        textField.adjustsFontForContentSizeCategory = true
        textField.font = UIFont.preferredFont(forTextStyle: .body)
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.placeholder = placeholder

        // Do not trigger focus changes from updateUIView.
        // Doing so can cause SwiftUI AttributeGraph cycles during view updates.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String
        private let onSubmit: () -> Void
        private var pendingText: String?
        private var isUpdateScheduled = false

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self._text = text
            self.onSubmit = onSubmit
        }

        @objc func textDidChange(_ sender: UITextField) {
            let newValue = sender.text ?? ""
            guard newValue != text else { return }
            pendingText = newValue
            guard isUpdateScheduled == false else { return }
            isUpdateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let nextValue = self.pendingText ?? ""
                self.pendingText = nil
                self.isUpdateScheduled = false
                if nextValue != self.text {
                    self.text = nextValue
                }
            }
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            // Keep UIKit focus state local to avoid SwiftUI binding cycles.
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            // Keep UIKit focus state local to avoid SwiftUI binding cycles.
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            DispatchQueue.main.async {
                self.onSubmit()
            }
            return false
        }
    }
}
