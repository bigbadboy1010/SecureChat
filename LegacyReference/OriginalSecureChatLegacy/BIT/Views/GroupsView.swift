import SwiftUI

struct GroupsView: View {
    @State private var groups: [Group] = []
    @State private var showCreateGroup = false
    @State private var groupName = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Gruppen")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Button(action: { showCreateGroup = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .border(width: 1, edges: [.bottom], color: .gray.opacity(0.2))

            if groups.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.3")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("Keine Gruppen")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(groups) { group in
                            GroupRow(group: group)
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showCreateGroup) {
            CreateGroupSheet(isPresented: $showCreateGroup, groupName: $groupName) { name in
                let newGroup = Group(
                    id: UUID().uuidString,
                    name: name,
                    members: [],
                    sharedEncryptionKey: Data(),
                    keyCommitment: "",
                    settings: GroupSettings()
                )
                groups.append(newGroup)
                groupName = ""
            }
        }
    }
}

struct GroupRow: View {
    let group: Group

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.name)
                .fontWeight(.semibold)
                .font(.headline)

            HStack(spacing: 16) {
                Label("\(group.members.count) Mitglieder", systemImage: "person.2.fill")
                    .font(.caption)
                    .foregroundColor(.gray)

                Spacer()

                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct CreateGroupSheet: View {
    @Binding var isPresented: Bool
    @Binding var groupName: String
    var onCreate: (String) -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextField("Gruppenname", text: $groupName)
                    .textFieldStyle(.roundedBorder)
                    .padding()

                Spacer()

                Button(action: {
                    if !groupName.isEmpty {
                        onCreate(groupName)
                        isPresented = false
                    }
                }) {
                    Text("Erstellen")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .padding()
                .disabled(groupName.isEmpty)
            }
            .navigationTitle("Neue Gruppe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Abbrechen") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

struct GroupsTabView: View {
    var body: some View {
        NavigationView {
            GroupsView()
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    GroupsView()
}
