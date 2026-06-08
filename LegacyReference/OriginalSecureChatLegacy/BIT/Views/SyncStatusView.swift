import SwiftUI

struct SyncStatusView: View {
    @StateObject private var offlineService = OfflineService.shared

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: syncIcon)
                    .foregroundColor(syncColor)
                    .font(.caption)

                Text(syncStatusText)
                    .font(.caption)
                    .fontWeight(.semibold)

                if offlineService.pendingMessageCount > 0 {
                    Spacer()
                    Text("\(offlineService.pendingMessageCount)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(syncColor.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(syncColor.opacity(0.1))
            .cornerRadius(8)

            if offlineService.pendingMessageCount > 0 {
                Button(action: {
                    offlineService.syncOfflineMessages()
                }) {
                    Text("Jetzt synchronisieren")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private var syncStatusText: String {
        if case .syncing = offlineService.syncStatus {
            return "Synchronisiert..."
        } else if case .pendingSync = offlineService.syncStatus {
            return "\(offlineService.pendingMessageCount) wartend"
        } else if case .syncFailed = offlineService.syncStatus {
            return "Sync fehlgeschlagen"
        } else {
            return offlineService.isOnline ? "Online" : "Offline"
        }
    }

    private var syncIcon: String {
        if case .syncing = offlineService.syncStatus {
            return "arrow.2.circlepath"
        } else if case .pendingSync = offlineService.syncStatus {
            return "exclamationmark.circle"
        } else if case .syncFailed = offlineService.syncStatus {
            return "xmark.circle"
        } else {
            return offlineService.isOnline ? "wifi" : "wifi.slash"
        }
    }

    private var syncColor: Color {
        if case .syncing = offlineService.syncStatus {
            return .blue
        } else if case .pendingSync = offlineService.syncStatus {
            return .orange
        } else if case .syncFailed = offlineService.syncStatus {
            return .red
        } else {
            return offlineService.isOnline ? .green : .orange
        }
    }
}

#Preview {
    SyncStatusView()
}
