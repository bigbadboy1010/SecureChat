import SwiftUI

struct BackupRecoveryView: View {
    @State private var selectedTab: BackupTab = .backup
    
    enum BackupTab {
        case backup
        case restore
        case settings
    }
    
    var body: some View {
        NavigationStack {
            List {
                Picker("Ansicht", selection: $selectedTab) {
                    Text("Sichern").tag(BackupTab.backup)
                    Text("Wiederherstellen").tag(BackupTab.restore)
                    Text("Einstellungen").tag(BackupTab.settings)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .padding(.vertical, 8)
                
                if selectedTab == .backup {
                    backupSection
                } else if selectedTab == .restore {
                    restoreSection
                } else {
                    settingsSection
                }
            }
            .navigationTitle("Sicherung & Wiederherstellung")
        }
    }
    
    @ViewBuilder
    private var backupSection: some View {
        Section("Backup-Status") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Letzte Sicherung")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        Text("Heute um 15:32 Uhr")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 20))
                }
            }
            .padding(.vertical, 4)
        }
        
        Section("Sicherungsoptionen") {
            NavigationLink(destination: CreateBackupView()) {
                HStack {
                    Image(systemName: "square.and.arrow.down.on.square.fill")
                    Text("Neue Sicherung erstellen")
                }
            }
            
            NavigationLink(destination: BackupHistoryView()) {
                HStack {
                    Image(systemName: "clock.fill")
                    Text("Sicherungsverlauf")
                }
            }
        }
        
        Section("Sicherungsdetails") {
            backupDetailRow(label: "Nachrichten", value: "2.847")
            backupDetailRow(label: "Kontakte", value: "42")
            backupDetailRow(label: "Dateien", value: "156")
            backupDetailRow(label: "Größe", value: "145 MB")
        }
        
        Section {
            Button(action: {}) {
                HStack {
                    Image(systemName: "icloud.and.arrow.up.fill")
                    Text("Mit iCloud synchronisieren")
                }
            }
        }
    }
    
    @ViewBuilder
    private var restoreSection: some View {
        Section("Verfügbare Sicherungen") {
            VStack(alignment: .leading, spacing: 12) {
                backupRestoreRow(
                    date: "15. Mai 2026, 15:32",
                    size: "145 MB",
                    messages: "2.847",
                    isLatest: true
                )
                
                backupRestoreRow(
                    date: "14. Mai 2026, 22:15",
                    size: "142 MB",
                    messages: "2.801",
                    isLatest: false
                )
                
                backupRestoreRow(
                    date: "13. Mai 2026, 14:50",
                    size: "138 MB",
                    messages: "2.756",
                    isLatest: false
                )
            }
        }
        
        Section {
            Button(role: .destructive, action: {}) {
                HStack {
                    Image(systemName: "xmark.icloud.fill")
                    Text("Alle Sicherungen löschen")
                }
            }
        }
    }
    
    @ViewBuilder
    private var settingsSection: some View {
        Section("Automatische Sicherung") {
            Toggle("Täglich sichern", isOn: .constant(true))
            
            HStack {
                Text("Sicherungszeit")
                Spacer()
                Text("02:00 Uhr")
                    .foregroundColor(.gray)
            }
        }
        
        Section("Sicherungsort") {
            HStack {
                Text("Standort")
                Spacer()
                Text("iCloud")
                    .foregroundColor(.gray)
            }
            
            Toggle("Auf Wi-Fi beschränken", isOn: .constant(true))
        }
        
        Section("Verschlüsselung") {
            HStack {
                Text("Sicherungsverschlüsselung")
                Spacer()
                Text("AES-256")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.green)
            }
            
            HStack {
                Text("Passwortschutz")
                Spacer()
                Toggle("", isOn: .constant(true))
            }
        }
    }
    
    private func backupDetailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, design: .monospaced))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.blue)
        }
    }
    
    private func backupRestoreRow(date: String, size: String, messages: String, isLatest: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(date)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    if isLatest {
                        Text("AKTUELL")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(3)
                    }
                }
                
                HStack(spacing: 12) {
                    Text("\(messages) Nachrichten")
                        .font(.system(size: 11, design: .monospaced))
                    Text("•")
                    Text(size)
                        .font(.system(size: 11, design: .monospaced))
                }
                .foregroundColor(.gray)
            }
            
            Spacer()
            
            Button(action: {}) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Create Backup View
struct CreateBackupView: View {
    @State private var isCreating = false
    @State private var progress: Double = 0
    @State private var status = "Vorbereitung..."
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                if isCreating {
                    ProgressView(value: progress)
                        .frame(height: 4)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                }
                
                Text("Sicherung wird erstellt")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                
                Text(status)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.gray)
            }
            .padding(20)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            Spacer()
            
            Button(action: { startBackup() }) {
                Text(isCreating ? "Wird gesichert..." : "Sicherung starten")
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(8)
            }
            .disabled(isCreating)
        }
        .padding()
        .navigationTitle("Sicherung erstellen")
    }
    
    private func startBackup() {
        isCreating = true
        var currentProgress: Double = 0
        
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            currentProgress += Double.random(in: 0.02...0.15)
            progress = min(currentProgress, 0.95)
            
            if currentProgress > 0.3 {
                status = "Nachrichten werden gesichert..."
            }
            if currentProgress > 0.6 {
                status = "Dateien werden gesichert..."
            }
            if currentProgress > 0.85 {
                status = "Finalisierung..."
            }
            
            if progress >= 0.95 {
                timer.invalidate()
                progress = 1.0
                status = "Fertig!"
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isCreating = false
                }
            }
        }
    }
}

// MARK: - Backup History View
struct BackupHistoryView: View {
    var body: some View {
        List {
            Section("Sicherungsverlauf") {
                ForEach(0..<5, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sicherung #\(5-index)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        Text("Vor \(index) Tagen")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .navigationTitle("Verlauf")
    }
}
