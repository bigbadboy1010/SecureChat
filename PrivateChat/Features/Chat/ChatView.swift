import CoreTransferable
import PhotosUI
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ChatView: View {
    @ObservedObject var service: ConversationService
    let storedConversation: StoredConversation

    @State private var draft = ""
    @State private var messageSearchText = ""
    @State private var showDetails = false
    @State private var selectedMessage: ChatMessage?
    @State private var scrollUpdateTask: Task<Void, Never>?
    @State private var selectedLibraryItem: PhotosPickerItem?
    @State private var pendingMedia: PendingMedia?
    @State private var showCamera = false
    @State private var mediaErrorMessage: String?
    @State private var previewAttachment: ChatAttachment?

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
                || (message.attachment?.fileName.localizedCaseInsensitiveContains(needle) ?? false)
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
        (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || pendingMedia != nil) &&
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
                                onShowDetails: { selectedMessage = message },
                                onPreviewAttachment: { previewAttachment = $0 }
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
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showDetails = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("Chat-Details")
            }
        }
        .sheet(isPresented: $showDetails) {
            ChatDetailsView(service: service, conversationID: currentConversation.id)
        }
        .sheet(item: $selectedMessage) { message in
            MessageDetailView(service: service, conversationID: currentConversation.id, message: message)
        }
        .sheet(isPresented: $showCamera) {
            CameraMediaPicker(
                onCancel: { showCamera = false },
                onResult: { result in
                    showCamera = false
                    handleCameraResult(result)
                }
            )
            .ignoresSafeArea()
        }
        .sheet(item: $previewAttachment) { attachment in
            AttachmentPreviewSheet(service: service, attachment: attachment)
        }
        .alert("Medien konnten nicht vorbereitet werden", isPresented: Binding(
            get: { mediaErrorMessage != nil },
            set: { if $0 == false { mediaErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { mediaErrorMessage = nil }
        } message: {
            Text(mediaErrorMessage ?? "Unbekannter Fehler")
        }
        .onChange(of: selectedLibraryItem) { item in
            guard let item else { return }
            Task { await loadLibraryItem(item) }
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

            if let pendingMedia {
                HStack(spacing: 10) {
                    Image(systemName: pendingMedia.kind == .image ? "photo.fill" : "video.fill")
                        .foregroundStyle(PrivateChatDesign.brandCyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pendingMedia.fileName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(pendingMedia.data.count), countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(PrivateChatDesign.textSecondary)
                    }
                    Spacer()
                    Button {
                        self.pendingMedia = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(PrivateChatDesign.textSecondary)
                }
                .padding(.horizontal)
            }

            HStack(alignment: .bottom, spacing: 10) {
                Menu {
                    PhotosPicker(
                        selection: $selectedLibraryItem,
                        matching: .any(of: [.images, .videos])
                    ) {
                        Label("Foto oder Video auswählen", systemImage: "photo.on.rectangle")
                    }

                    Button {
                        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                            mediaErrorMessage = "Auf diesem Gerät ist keine Kamera verfügbar."
                            return
                        }
                        showCamera = true
                    } label: {
                        Label("Kamera öffnen", systemImage: "camera")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 30, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(PrivateChatDesign.brandCyan)
                .accessibilityLabel("Foto oder Video hinzufügen")

                composerInput

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
        let media = pendingMedia
        updateDraft("", persist: true)
        pendingMedia = nil
        Task {
            if let media {
                await service.sendAttachment(
                    conversationID: currentConversation.id,
                    body: body,
                    data: media.data,
                    kind: media.kind,
                    fileName: media.fileName,
                    mimeType: media.mimeType
                )
            } else {
                await service.sendMessage(conversationID: currentConversation.id, body: body)
            }
        }
    }

    @MainActor
    private func loadLibraryItem(_ item: PhotosPickerItem) async {
        defer { selectedLibraryItem = nil }
        do {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                guard let transfer = try await item.loadTransferable(type: VideoTransfer.self) else {
                    throw PrivateChatError.attachmentUnavailable
                }
                let contentType = item.supportedContentTypes.first(where: { $0.conforms(to: .movie) })
                let fileExtension = contentType?.preferredFilenameExtension ?? "mov"
                pendingMedia = try PendingMedia.video(
                    data: transfer.data,
                    fileName: "Video-\(Self.mediaTimestamp()).\(fileExtension)",
                    mimeType: contentType?.preferredMIMEType ?? "video/quicktime"
                )
            } else {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw PrivateChatError.attachmentUnavailable
                }
                pendingMedia = try PendingMedia.image(
                    data: data,
                    fileName: "Foto-\(Self.mediaTimestamp()).jpg"
                )
            }
        } catch {
            mediaErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func handleCameraResult(_ result: Result<CameraCapture, Error>) {
        do {
            switch try result.get() {
            case .image(let image):
                pendingMedia = try PendingMedia.image(
                    image: image,
                    fileName: "Kamera-\(Self.mediaTimestamp()).jpg"
                )
            case .video(let data):
                pendingMedia = try PendingMedia.video(
                    data: data,
                    fileName: "Kamera-\(Self.mediaTimestamp()).mov"
                )
            }
        } catch {
            mediaErrorMessage = error.localizedDescription
        }
    }

    private static func mediaTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
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
            Text(isPeerConversation ? "Schreibe deine erste Nachricht." : "Schreibe deine erste Notiz.")
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

private struct MessageBubble: View {
    @ObservedObject var service: ConversationService
    let conversationID: UUID
    let message: ChatMessage
    let onShowDetails: () -> Void
    let onPreviewAttachment: (ChatAttachment) -> Void
    @State private var attachmentImage: UIImage?

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

                    if let attachment = message.attachment {
                        Button {
                            onPreviewAttachment(attachment)
                        } label: {
                            attachmentLabel(attachment)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(attachment.kind == .image ? "Foto" : "Video") öffnen")
                    }

                    if message.body.isEmpty == false {
                        Text(message.body)
                            .font(.body)
                            .foregroundStyle(PrivateChatDesign.textPrimary)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(message.isIncoming ? Color.white.opacity(0.16) : Color.white.opacity(0.10), lineWidth: 1)
                }
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
                            .accessibilityLabel(message.status.localizedTitle)
                    } else if message.readAt != nil {
                        Image(systemName: "eye")
                    }
                }
                .font(.caption2)
                .foregroundStyle(Color.secondary)
            }
            .task(id: message.attachment?.id) {
                guard let attachment = message.attachment, attachment.kind == .image else {
                    attachmentImage = nil
                    return
                }
                attachmentImage = (try? service.attachmentData(for: attachment)).flatMap { UIImage(data: $0) }
            }

            if message.isIncoming {
                Spacer(minLength: 48)
            }
        }
    }

    private var bubbleBackground: some ShapeStyle {
        if message.isIncoming {
            return AnyShapeStyle(PrivateChatDesign.canvasHigh)
        }
        switch message.status {
        case .failed:
            return AnyShapeStyle(Color.red.opacity(0.82))
        case .queued, .sending:
            return AnyShapeStyle(Color.orange.opacity(0.82))
        case .sentToRelay, .sent, .delivered:
            return AnyShapeStyle(Color(red: 0.02, green: 0.43, blue: 0.56))
        }
    }

    @ViewBuilder
    private func attachmentLabel(_ attachment: ChatAttachment) -> some View {
        if attachment.kind == .image, let attachmentImage {
            Image(uiImage: attachmentImage)
                .resizable()
                .scaledToFill()
                .frame(width: 220, height: 165)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        } else {
            HStack(spacing: 12) {
                Image(systemName: attachment.kind == .image ? "photo" : "play.rectangle.fill")
                    .font(.title2)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.fileName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file))
                        .font(.caption)
                        .opacity(0.78)
                }
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
                    .opacity(0.72)
            }
            .foregroundStyle(PrivateChatDesign.textPrimary)
            .frame(maxWidth: 220, alignment: .leading)
            .padding(.vertical, 4)
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
                    if let attachment = message.attachment {
                        LabeledContent("Anhang", value: attachment.fileName)
                        LabeledContent("Medientyp", value: attachment.kind == .image ? "Foto" : "Video")
                        LabeledContent(
                            "Größe",
                            value: ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file)
                        )
                    }
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

private struct PendingMedia: Identifiable {
    let id = UUID()
    let data: Data
    let kind: ChatAttachmentKind
    let fileName: String
    let mimeType: String

    static func image(data: Data, fileName: String) throws -> PendingMedia {
        guard let image = UIImage(data: data) else {
            throw PrivateChatError.unsupportedAttachment
        }
        return try Self.image(image: image, fileName: fileName)
    }

    static func image(image: UIImage, fileName: String) throws -> PendingMedia {
        let maximumDimension: CGFloat = 2_048
        let scale = min(1, maximumDimension / max(image.size.width, image.size.height))
        let targetSize = CGSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let normalized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        var quality: CGFloat = 0.84
        var encoded = normalized.jpegData(compressionQuality: quality)
        while let current = encoded,
              current.count > ConversationService.maximumAttachmentBytes,
              quality > 0.34 {
            quality -= 0.10
            encoded = normalized.jpegData(compressionQuality: quality)
        }
        guard let encoded, encoded.count <= ConversationService.maximumAttachmentBytes else {
            throw PrivateChatError.attachmentTooLarge(maximumBytes: ConversationService.maximumAttachmentBytes)
        }
        return PendingMedia(data: encoded, kind: .image, fileName: fileName, mimeType: "image/jpeg")
    }

    static func video(
        data: Data,
        fileName: String,
        mimeType: String = "video/quicktime"
    ) throws -> PendingMedia {
        guard data.isEmpty == false else {
            throw PrivateChatError.attachmentUnavailable
        }
        guard data.count <= ConversationService.maximumAttachmentBytes else {
            throw PrivateChatError.attachmentTooLarge(maximumBytes: ConversationService.maximumAttachmentBytes)
        }
        return PendingMedia(data: data, kind: .video, fileName: fileName, mimeType: mimeType)
    }
}

private struct VideoTransfer: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .movie) { data in
            VideoTransfer(data: data)
        }
    }
}

private enum CameraCapture {
    case image(UIImage)
    case video(Data)
}

private enum CameraCaptureError: LocalizedError {
    case missingResult

    var errorDescription: String? {
        "Die Kameraaufnahme konnte nicht gelesen werden."
    }
}

private struct CameraMediaPicker: UIViewControllerRepresentable {
    let onCancel: () -> Void
    let onResult: (Result<CameraCapture, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCancel: onCancel, onResult: onResult)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoQuality = .typeMedium
        picker.videoMaximumDuration = 10
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onCancel: () -> Void
        let onResult: (Result<CameraCapture, Error>) -> Void

        init(onCancel: @escaping () -> Void, onResult: @escaping (Result<CameraCapture, Error>) -> Void) {
            self.onCancel = onCancel
            self.onResult = onResult
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onResult(.success(.image(image)))
                return
            }
            if let url = info[.mediaURL] as? URL, let data = try? Data(contentsOf: url) {
                onResult(.success(.video(data)))
                return
            }
            onResult(.failure(CameraCaptureError.missingResult))
        }
    }
}

private struct AttachmentPreviewSheet: View {
    @ObservedObject var service: ConversationService
    let attachment: ChatAttachment
    @Environment(\.dismiss) private var dismiss
    @State private var previewURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let previewURL {
                    QuickLookPreview(url: previewURL)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                        Text("Vorschau nicht verfügbar")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    ProgressView("Medium wird entschlüsselt …")
                }
            }
            .navigationTitle(attachment.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .task(id: attachment.id) {
            preparePreview()
        }
        .onDisappear {
            removePreviewFile()
        }
    }

    private func preparePreview() {
        do {
            let data = try service.attachmentData(for: attachment)
            let fileExtension = URL(fileURLWithPath: attachment.fileName).pathExtension
            let suffix = fileExtension.isEmpty ? (attachment.kind == .image ? "jpg" : "mov") : fileExtension
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("PrivateChatPreview-\(UUID().uuidString)")
                .appendingPathExtension(suffix)
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            #else
            try data.write(to: url, options: [.atomic])
            #endif
            previewURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removePreviewFile() {
        guard let previewURL else { return }
        try? FileManager.default.removeItem(at: previewURL)
        self.previewURL = nil
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
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
