import SwiftUI

@main
struct BITApp: App {
    @StateObject private var navigationManager = NavigationManager()
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var offlineService = OfflineService.shared
    @StateObject private var analyticsService = AnalyticsService.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    TabView(selection: $navigationManager.activeTab) {
                        ChatTabView()
                            .tabItem {
                                Label("Chats", systemImage: "bubble.left.and.bubble.right.fill")
                            }
                            .tag(NavigationTab.chats)

                        GroupsTabView()
                            .tabItem {
                                Label("Gruppen", systemImage: "person.3.fill")
                            }
                            .tag(NavigationTab.groups)

                        CallsTabView()
                            .tabItem {
                                Label("Anrufe", systemImage: "phone.fill")
                            }
                            .tag(NavigationTab.calls)

                        SettingsTabView()
                            .tabItem {
                                Label("Einstellungen", systemImage: "gear")
                            }
                            .tag(NavigationTab.settings)
                    }
                    .environmentObject(navigationManager)
                    .overlay(alignment: .bottom) {
                        if offlineService.pendingMessageCount > 0 {
                            SyncStatusView()
                                .padding()
                        }
                    }
                } else {
                    LoginView()
                        .environmentObject(authManager)
                }
            }
            .onAppear {
                analyticsService.trackEvent("app_opened", category: .general)
            }
            .preferredColorScheme(nil)
        }
    }
}

// MARK: - Navigation Manager
class NavigationManager: ObservableObject {
    @Published var activeTab: NavigationTab = .chats
    @Published var selectedChat: String?
    @Published var selectedGroup: String?
}

enum NavigationTab {
    case chats
    case groups
    case calls
    case settings
}

// MARK: - Authentication Manager
class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var errorMessage: String?

    func login(username: String, password: String) {
        // Placeholder: In production, validate credentials
        currentUser = User(id: UUID().uuidString, name: username)
        isAuthenticated = true
    }

    func logout() {
        currentUser = nil
        isAuthenticated = false
    }
}

struct User: Identifiable {
    let id: String
    let name: String
    var avatar: Data?
}
