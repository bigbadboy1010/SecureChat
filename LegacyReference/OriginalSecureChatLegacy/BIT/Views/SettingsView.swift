import SwiftUI

struct SettingsView: View {
    @StateObject private var analyticsService = AnalyticsService.shared
    @StateObject private var securityService = SecurityAuditService.shared
    @State private var analyticsEnabled = true
    @State private var lowPowerMode = false
    @State private var showReport = false
    @State private var reportText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Einstellungen")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.systemBackground))
                .border(width: 1, edges: [.bottom], color: .gray.opacity(0.2))

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Privacy Section
                    SectionHeader(title: "Datenschutz")

                    SettingToggle(
                        title: "Analysen",
                        description: "Hilf uns, die App zu verbessern",
                        isOn: $analyticsEnabled,
                        action: { analyticsService.setAnalyticsOptIn($analyticsEnabled) }
                    )

                    SettingToggle(
                        title: "Stromsparmode",
                        description: "Reduziert Hintergrund-Aktivität",
                        isOn: $lowPowerMode
                    )

                    Divider()

                    // Security Section
                    SectionHeader(title: "Sicherheit")

                    Button(action: {
                        reportText = securityService.generateComplianceReport()
                        showReport = true
                    }) {
                        HStack {
                            Text("Sicherheitsbericht")
                                .foregroundColor(.black)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding(12)
                    }

                    Button(action: {}) {
                        HStack {
                            Text("Verschlüsselung verwalten")
                                .foregroundColor(.black)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding(12)
                    }

                    Divider()

                    // App Section
                    SectionHeader(title: "Info")

                    SettingRow(title: "Version", value: "6.0")
                    SettingRow(title: "Build", value: "1")
                    SettingRow(title: "Lizenz", value: "MIT")

                    Spacer()

                    // Logout Button
                    Button(action: {}) {
                        Text("Abmelden")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(8)
                    }
                    .padding()
                }
                .padding()
            }
        }
        .sheet(isPresented: $showReport) {
            ReportView(text: reportText, isPresented: $showReport)
        }
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.gray)
            .padding(.bottom, 8)
    }
}

struct SettingToggle: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    var action: (() -> Void)?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .onChange(of: isOn) { _ in
                    action?()
                }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct SettingRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .fontWeight(.semibold)
            Spacer()
            Text(value)
                .foregroundColor(.gray)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct ReportView: View {
    let text: String
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            ScrollView {
                Text(text)
                    .font(.caption)
                    .padding()
            }
            .navigationTitle("Sicherheitsbericht")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

struct SettingsTabView: View {
    var body: some View {
        NavigationView {
            SettingsView()
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    SettingsView()
}
