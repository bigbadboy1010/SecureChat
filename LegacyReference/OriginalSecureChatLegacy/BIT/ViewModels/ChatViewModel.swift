import Foundation
import SwiftUI

final class ChatViewModel: ObservableObject {
    @Published var messages: [BitchatMessage] = []
    @Published var messageText: String = ""
    @Published var selectedChannel: String = "default"
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let persistenceService = MessagePersistenceService.shared
    private let offlineService = OfflineService.shared
    private let searchService = SearchService.shared
    private let analyticsService = AnalyticsService.shared
    private let securityService = SecurityAuditService.shared

    init() {
        loadMessages()
    }

    func loadMessages() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let msgs = self?.persistenceService.fetchMessages(
                channelTag: self?.selectedChannel ?? "default",
                limit: 100
            ) ?? []
            DispatchQueue.main.async {
                self?.messages = msgs.sorted { $0.timestamp < $1.timestamp }
                self?.isLoading = false
            }
        }
    }

    func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let validationResult = securityService.validateAndSanitizeInput(messageText)
        guard case .success(let sanitized) = validationResult else {
            errorMessage = "Invalid message content"
            return
        }

        let message = BitchatMessage(
            id: UUID().uuidString,
            content: sanitized,
            senderID: "current_user",
            channelTag: selectedChannel,
            timestamp: Date(),
            deliveryStatus: offlineService.isOnline ? .sent : .pending,
            isRead: true
        )

        if offlineService.isOnline {
            persistenceService.saveMessage(message)
            analyticsService.trackEvent("message_sent", category: .messaging)
        } else {
            offlineService.queueMessage(message, priority: .normal)
        }

        DispatchQueue.main.async {
            self.messages.append(message)
            self.messageText = ""
        }
    }

    func deleteMessage(_ messageID: String) {
        persistenceService.deleteMessage(messageID)
        messages.removeAll { $0.id == messageID }
        analyticsService.trackEvent("message_deleted", category: .messaging)
    }

    func markAsRead(_ messageID: String) {
        if let index = messages.firstIndex(where: { $0.id == messageID }) {
            var message = messages[index]
            message.isRead = true
            persistenceService.saveMessage(message)
            messages[index] = message
        }
    }

    func changeChannel(_ channelID: String) {
        selectedChannel = channelID
        messageText = ""
        loadMessages()
    }
}
