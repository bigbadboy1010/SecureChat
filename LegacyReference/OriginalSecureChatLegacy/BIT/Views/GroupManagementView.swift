import SwiftUI

struct GroupManagementView: View {
    @StateObject private var viewModel = GroupManagementViewModel()
    @State private var showCreateGroupSheet = false
    @State private var selectedGroup: GroupModel?
    @State private var searchText = ""
    
    var body: some View {
        NavigationStack {
            List {
                Section("Deine Gruppen") {
                    if viewModel.groups.isEmpty {
                        Text("Keine Gruppen vorhanden")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(viewModel.groups, id: \.id) { group in
                            NavigationLink(destination: GroupDetailView(group: group)) {
                                groupRow(group)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Gruppen durchsuchen")
            .navigationTitle("Gruppen")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showCreateGroupSheet = true }) {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateGroupSheet) {
                CreateGroupSheetView(isPresented: $showCreateGroupSheet)
            }
        }
    }
    
    private func groupRow(_ group: GroupModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10))
                        Text("\(group.memberCount) Mitglieder")
                            .font(.system(size: 11, design: .monospaced))
                        
                        if group.isEncrypted {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                            Text("E2E")
                                .font(.system(size: 11, design: .monospaced))
                        }
                    }
                    .foregroundColor(.gray)
                }
                
                Spacer()
                
                if group.isAdmin {
                    Label("Admin", systemImage: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
            }
        }
    }
}

// MARK: - Group Detail View
struct GroupDetailView: View {
    let group: GroupModel
    @State private var members: [GroupMember] = []
    @State private var selectedTab: GroupTab = .messages
    
    enum GroupTab {
        case messages
        case members
        case settings
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tabs
                Picker("Tab", selection: $selectedTab) {
                    Text("Nachrichten").tag(GroupTab.messages)
                    Text("Mitglieder").tag(GroupTab.members)
                    Text("Einstellungen").tag(GroupTab.settings)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content
                TabView(selection: $selectedTab) {
                    groupMessagesView
                        .tag(GroupTab.messages)
                    
                    groupMembersView
                        .tag(GroupTab.members)
                    
                    groupSettingsView
                        .tag(GroupTab.settings)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle(group.name)
        }
    }
    
    @ViewBuilder
    private var groupMessagesView: some View {
        VStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nachrichten werden hier angezeigt")
                        .foregroundColor(.gray)
                        .padding()
                }
            }
            
            HStack(spacing: 8) {
                TextField("Nachricht eingeben", text: .constant(""))
                    .textFieldStyle(.roundedBorder)
                
                Button(action: {}) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private var groupMembersView: some View {
        List {
            ForEach(members, id: \.id) { member in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.name)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        
                        if member.isAdmin {
                            Text("Admin")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Spacer()
                    
                    if member.isOnline {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var groupSettingsView: some View {
        List {
            Section("Grundeinstellungen") {
                HStack {
                    Text("Name")
                    Spacer()
                    Text(group.name)
                        .foregroundColor(.gray)
                }
                
                HStack {
                    Text("Mitglieder")
                    Spacer()
                    Text("\(group.memberCount)")
                        .foregroundColor(.gray)
                }
            }
            
            Section("Sicherheit") {
                Toggle("Ende-zu-Ende-Verschlüsselung", isOn: .constant(group.isEncrypted))
                    .disabled(true)
                
                HStack {
                    Text("Verschlüsselung")
                    Spacer()
                    Text("AES-256-GCM")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.green)
                }
            }
            
            Section {
                Button(role: .destructive, action: {}) {
                    Label("Gruppe verlassen", systemImage: "arrow.backward")
                }
            }
        }
    }
}

// MARK: - Create Group Sheet
struct CreateGroupSheetView: View {
    @Binding var isPresented: Bool
    @State private var groupName = ""
    @State private var selectedMembers: Set<String> = []
    @State private var isEncrypted = true
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Gruppenname") {
                    TextField("z.B. Projektteam", text: $groupName)
                }
                
                Section("Mitglieder auswählen") {
                    // List of available members
                    Toggle("alice", isOn: .constant(false))
                    Toggle("bob", isOn: .constant(false))
                    Toggle("charlie", isOn: .constant(false))
                }
                
                Section("Sicherheit") {
                    Toggle("Ende-zu-Ende-Verschlüsselung", isOn: $isEncrypted)
                }
            }
            .navigationTitle("Neue Gruppe erstellen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Erstellen") {
                        // Create group
                        isPresented = false
                    }
                    .disabled(groupName.isEmpty)
                }
            }
        }
    }
}

// MARK: - View Models
class GroupManagementViewModel: ObservableObject {
    @Published var groups: [GroupModel] = []
    
    init() {
        loadGroups()
    }
    
    private func loadGroups() {
        groups = [
            GroupModel(id: "1", name: "SecureChat Team", memberCount: 5, isAdmin: true, isEncrypted: true),
            GroupModel(id: "2", name: "App Development", memberCount: 8, isAdmin: false, isEncrypted: true),
            GroupModel(id: "3", name: "Security Review", memberCount: 3, isAdmin: true, isEncrypted: true),
        ]
    }
}

// MARK: - Models
struct GroupModel: Identifiable {
    let id: String
    let name: String
    let memberCount: Int
    let isAdmin: Bool
    let isEncrypted: Bool
}

struct GroupMember: Identifiable {
    let id: String
    let name: String
    let isAdmin: Bool
    let isOnline: Bool
}
