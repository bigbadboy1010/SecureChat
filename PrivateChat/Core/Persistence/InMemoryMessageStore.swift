import Foundation

final class InMemoryMessageStore: MessageStoring {
    private var conversations: [StoredConversation]

    init(conversations: [StoredConversation] = []) {
        self.conversations = conversations
    }

    func load() throws -> [StoredConversation] {
        conversations
    }

    func save(_ conversations: [StoredConversation]) throws {
        self.conversations = conversations
    }
}
