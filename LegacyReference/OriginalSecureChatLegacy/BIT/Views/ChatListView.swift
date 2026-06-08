import SwiftUI

struct ChatListView: View {
    @StateObject private var viewModel = ChatListViewModel()
    @State private var searchText = ""
    @State private var selectedChat: ChatListItem?
    @State private var showNewChatSheet = false
    @State private var showArchiveView = false
    @State private var selectedTab: ChatFilter = .all
    
    enum ChatFilter {
        case all
        case unread
        case archived
        case pinned
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                SearchBar(text: $searchText, placeholder: "Chats durchsuchen...")
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                
                // Filter Tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        filterTab("Alle", selected: selectedTab == .all) {
                            selectedTab = .all
                        }
                        filterTab("Ungelesen", selected: selectedTab == .unread) {
                            selectedTab = .unread
                        }
                        filterTab("Archiviert", selected: selectedTab == .archived) {
                            selectedTab = .archived
                        }
                        filterTab("Gepinnt", selected: selectedTab == .pinned) {
                            selectedTab = .pinned
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                
                Divider()
                
                // Chat List
                List {
                    let filteredChats = viewModel.getFilteredChats(searchText: searchText, filter: selectedTab)
                    
                    if filteredChats.isEmpty {
                        VStack(alignment: .center, spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                            Text("Keine Chats gefunden")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(filteredChats, id: \.id) { chat in
                            NavigationLink(destination: ChatDetailView(chat: chat)) {
                                ChatListItemView(chat: chat)
                            }
                            .contextMenu {
                                contextMenuActions(for: chat)
                            }
                        }
                        .onDelete { indexSet in
                            deleteCats(at: indexSet)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Nachrichten")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showNewChatSheet = true }) {
                        Image(systemName: "square.and.pencil")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button(action: { showArchiveView = true }) {
                        Image(systemName: "archivebox.fill")
                    }
                }
            }
            .sheet(isPresented: $showNewChatSheet) {
                NewChatSheetView(isPresented: $showNewChatSheet)
            }
            .sheet(isPresented: $showArchiveView) {
                ArchivedChatsView(isPresented: $showArchiveView)
            }
        }
    }
    
    private func filterTab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                .cornerRadius(6)
                .foregroundColor(selected ? .blue : .gray)
        }
    }
    
    @ViewBuilder
    private func contextMenuActions(for chat: ChatListItem) -> some View {
        Button(action: { viewModel.togglePin(chat: chat) }) {
            Label(chat.isPinned ? "Entpinnen" : "Pinnen", 
                  systemImage: chat.isPinned ? "pin.slash.fill" : "pin.fill")
        }
        
        Button(action: { viewModel.archive(chat: chat) }) {
            Label("Archivieren", systemImage: "archivebox.fill")
        }
        
        Button(action: { viewModel.mute(chat: chat) }) {
            Label(chat.isMuted ? "Unmute" : "Stummschalten", 
                  systemImage: chat.isMuted ? "speaker.fill" : "speaker.slash.fill")
        }
        
        Divider()
        
        Button(role: .destructive, action: { viewModel.delete(chat: chat) }) {
            Label("Löschen", systemImage: "trash.fill")
        }
    }
    
    private func deleteCats(at indexSet: IndexSet) {
        // Handle deletion
    }
}

// MARK: - Chat List Item View
struct ChatListItemView: View {
    let chat: ChatListItem
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(colorForChat(chat))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(String(chat.name.prefix(1)))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(chat.name)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    
                    if chat.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                    
                    Spacer()
                    
                    Text(timeAgoString(chat.lastMessageTime))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray)
                }
                
                HStack {
                    Text(chat.lastMessage)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .opacity(chat.isMuted ? 0.5 : 1.0)
    }
    
    private func colorForChat(_ chat: ChatListItem) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .red, .purple, .pink]
        let index = chat.name.hashValue % colors.count
        return colors[abs(index)]
    }
    
    private func timeAgoString(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.minute, .hour, .day, .month], from: date, to: now)
        
        if let day = components.day, day > 0 {
            return day == 1 ? "Gestern" : "\(day)d"
        } else if let hour = components.hour, hour > 0 {
            return "\(hour)h"
        } else if let minute = components.minute, minute > 0 {
            return "\(minute)m"
        } else {
            return "Jetzt"
        }
    }
}

// MARK: - Search Bar
struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - New Chat Sheet
struct NewChatSheetView: View {
    @Binding var isPresented: Bool
    @State private var selectedPeople: [String] = []
    @State private var chatName: String = ""
    
    var body: some View {
        NavigationStack {
            List {
                Section("Chat-Name") {
                    TextField("Unterhaltung benennen", text: $chatName)
                }
                
                Section("Teilnehmer auswählen") {
                    // List of available people
                    Text("alice")
                    Text("bob")
                    Text("charlie")
                }
            }
            .navigationTitle("Neuer Chat")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Erstellen") {
                        // Create chat
                        isPresented = false
                    }
                }
            }
        }
    }
}

// MARK: - Archived Chats View
struct ArchivedChatsView: View {
    @Binding var isPresented: Bool
    @State private var archivedChats: [ChatListItem] = []
    
    var body: some View {
        NavigationStack {
            List {
                if archivedChats.isEmpty {
                    Text("Keine archivierten Chats")
                        .foregroundColor(.gray)
                } else {
                    ForEach(archivedChats, id: \.id) { chat in
                        HStack {
                            Text(chat.name)
                            Spacer()
                            Button(action: { unarchive(chat) }) {
                                Image(systemName: "arrowshape.left.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Archiv")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        isPresented = false
                    }
                }
            }
        }
    }
    
    private func unarchive(_ chat: ChatListItem) {
        // Unarchive chat
    }
}

// MARK: - View Models
class ChatListViewModel: ObservableObject {
    @Published var chats: [ChatListItem] = []
    
    init() {
        loadChats()
    }
    
    func getFilteredChats(searchText: String, filter: ChatListView.ChatFilter) -> [ChatListItem] {
        var filtered = chats
        
        // Apply filter
        switch filter {
        case .all:
            break
        case .unread:
            filtered = filtered.filter { $0.unreadCount > 0 }
        case .archived:
            filtered = filtered.filter { $0.isArchived }
        case .pinned:
            filtered = filtered.filter { $0.isPinned }
        }
        
        // Apply search
        if !searchText.isEmpty {
            filtered = filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        
        return filtered.sorted { $0.lastMessageTime > $1.lastMessageTime }
    }
    
    func togglePin(chat: ChatListItem) {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            chats[index].isPinned.toggle()
        }
    }
    
    func archive(chat: ChatListItem) {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            chats[index].isArchived = true
        }
    }
    
    func mute(chat: ChatListItem) {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            chats[index].isMuted.toggle()
        }
    }
    
    func delete(chat: ChatListItem) {
        chats.removeAll { $0.id == chat.id }
    }
    
    private func loadChats() {
        chats = [
            ChatListItem(id: "1", name: "alice", lastMessage: "Hallo! Wie geht es dir?", lastMessageTime: Date().addingTimeInterval(-300), unreadCount: 2, isPinned: false, isArchived: false, isMuted: false),
            ChatListItem(id: "2", name: "Team Project", lastMessage: "alice: Das sieht gut aus!", lastMessageTime: Date().addingTimeInterval(-900), unreadCount: 0, isPinned: true, isArchived: false, isMuted: false),
            ChatListItem(id: "3", name: "bob", lastMessage: "Bis dann!", lastMessageTime: Date().addingTimeInterval(-3600), unreadCount: 0, isPinned: false, isArchived: false, isMuted: false),
        ]
    }
}

// MARK: - Models
struct ChatListItem: Identifiable {
    let id: String
    let name: String
    let lastMessage: String
    let lastMessageTime: Date
    let unreadCount: Int
    var isPinned: Bool
    var isArchived: Bool
    var isMuted: Bool
}

// MARK: - Chat Detail View
struct ChatDetailView: View {
    let chat: ChatListItem
    @State private var messageText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack {
                HStack {
                    Text(chat.name)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    Spacer()
                    Button(action: {}) {
                        Image(systemName: "info.circle.fill")
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .background(Color(.systemBackground))
            .border(width: 1, edges: [.bottom], color: .gray.opacity(0.2))
            
            // Messages
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Konversation geladen")
                        .foregroundColor(.gray)
                }
                .padding()
            }
            
            // Input
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 8) {
                    TextField("Nachricht", text: $messageText)
                        .textFieldStyle(.roundedBorder)
                    
                    Button(action: { messageText = "" }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .navigationTitle(chat.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
