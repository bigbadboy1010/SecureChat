import SwiftUI

// MARK: - Global Error Handler
class ErrorHandler: ObservableObject {
    @Published var currentError: AppError?
    @Published var errorHistory: [AppError] = []
    
    static let shared = ErrorHandler()
    
    func handle(_ error: AppError) {
        DispatchQueue.main.async {
            self.currentError = error
            self.errorHistory.append(error)
            
            if self.errorHistory.count > 50 {
                self.errorHistory.removeFirst()
            }
        }
    }
    
    func clear() {
        DispatchQueue.main.async {
            self.currentError = nil
        }
    }
}

enum AppError: Identifiable, Equatable {
    case network(String)
    case encryption(String)
    case persistence(String)
    case authentication(String)
    case validation(String)
    case sync(String)
    case unknown(String)
    
    var id: String {
        UUID().uuidString
    }
    
    var title: String {
        switch self {
        case .network: return "Netzwerkfehler"
        case .encryption: return "Verschlüsselungsfehler"
        case .persistence: return "Datenspeicherfehler"
        case .authentication: return "Authentifizierungsfehler"
        case .validation: return "Validierungsfehler"
        case .sync: return "Synchronisierungsfehler"
        case .unknown: return "Unbekannter Fehler"
        }
    }
    
    var message: String {
        switch self {
        case .network(let msg): return msg
        case .encryption(let msg): return msg
        case .persistence(let msg): return msg
        case .authentication(let msg): return msg
        case .validation(let msg): return msg
        case .sync(let msg): return msg
        case .unknown(let msg): return msg
        }
    }
    
    var severity: ErrorSeverity {
        switch self {
        case .network, .sync: return .warning
        case .encryption, .persistence, .authentication: return .critical
        case .validation, .unknown: return .warning
        }
    }
    
    var icon: String {
        switch severity {
        case .critical: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }
    
    static func == (lhs: AppError, rhs: AppError) -> Bool {
        lhs.title == rhs.title && lhs.message == rhs.message
    }
}

enum ErrorSeverity {
    case info
    case warning
    case critical
}

// MARK: - Error Display View
struct ErrorBannerView: View {
    let error: AppError
    let onDismiss: () -> Void
    
    @State private var isVisible = true
    
    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: error.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colorForSeverity(error.severity))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(error.title)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        Text(error.message)
                            .font(.system(size: 12, design: .monospaced))
                            .opacity(0.8)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation {
                            isVisible = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onDismiss()
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                    }
                    .foregroundColor(.gray)
                }
                .padding(12)
                .background(backgroundColorForSeverity(error.severity))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(colorForSeverity(error.severity).opacity(0.3), lineWidth: 1)
                )
            }
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
    
    private func colorForSeverity(_ severity: ErrorSeverity) -> Color {
        switch severity {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }
    
    private func backgroundColorForSeverity(_ severity: ErrorSeverity) -> Color {
        switch severity {
        case .info: return Color.blue.opacity(0.1)
        case .warning: return Color.orange.opacity(0.1)
        case .critical: return Color.red.opacity(0.1)
        }
    }
}

// MARK: - Error Alert Dialog
struct ErrorAlertView: View {
    let error: AppError
    let onDismiss: () -> Void
    let onRetry: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                Image(systemName: error.icon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.red)
                
                VStack(spacing: 4) {
                    Text(error.title)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    
                    Text(error.message)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 20)
            
            HStack(spacing: 12) {
                Button(action: onDismiss) {
                    Text("Schließen")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
                
                if let onRetry = onRetry {
                    Button(action: onRetry) {
                        Text("Erneut versuchen")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 8)
    }
}

// MARK: - Error History View
struct ErrorHistoryView: View {
    @ObservedObject var errorHandler = ErrorHandler.shared
    
    var body: some View {
        NavigationStack {
            List {
                Section("Fehlerhistorie") {
                    if errorHandler.errorHistory.isEmpty {
                        Text("Keine Fehler registriert")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(Array(errorHandler.errorHistory.reversed().enumerated()), id: \.offset) { index, error in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: error.icon)
                                        .foregroundColor(colorForSeverity(error.severity))
                                    Text(error.title)
                                        .font(.system(weight: .semibold, design: .monospaced))
                                }
                                Text(error.message)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Fehler-Verzeichnis")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Löschen") {
                        errorHandler.errorHistory.removeAll()
                    }
                }
            }
        }
    }
    
    private func colorForSeverity(_ severity: ErrorSeverity) -> Color {
        switch severity {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Error Recovery View
struct ErrorRecoveryView: View {
    let error: AppError
    let onRetry: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(.orange)
                
                Text("Fehler bei der Verarbeitung")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                
                Text(error.message)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 20)
            
            VStack(spacing: 12) {
                Button(action: onRetry) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Erneut versuchen")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(8)
                }
                
                Button(action: onCancel) {
                    Text("Abbrechen")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}
