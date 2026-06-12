import SwiftUI

struct ServiceErrorAlertModifier: ViewModifier {
    @ObservedObject var service: ConversationService
    @State private var presentedMessage: String?
    @State private var presentationTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .task(id: service.lastErrorMessage ?? "") {
                scheduleErrorPresentation(service.lastErrorMessage)
            }
            .onDisappear {
                presentationTask?.cancel()
                presentationTask = nil
            }
            .alert(
                "Fehler",
                isPresented: Binding<Bool>(
                    get: { presentedMessage != nil },
                    set: { isPresented in
                        guard isPresented == false else {
                            return
                        }
                        dismissError()
                    }
                )
            ) {
                Button("OK") {
                    dismissError()
                }
            } message: {
                Text(presentedMessage ?? "Unbekannter Fehler")
            }
    }

    private func scheduleErrorPresentation(_ message: String?) {
        presentationTask?.cancel()
        guard let message, message.isEmpty == false else {
            return
        }
        presentationTask = Task { @MainActor in
            await Task.yield()
            guard Task.isCancelled == false else { return }
            if presentedMessage != message {
                presentedMessage = message
            }
        }
    }

    private func dismissError() {
        presentationTask?.cancel()
        presentationTask = nil
        presentedMessage = nil
        Task { @MainActor in
            service.clearError()
        }
    }
}

extension View {
    func privateChatErrorAlert(service: ConversationService) -> some View {
        modifier(ServiceErrorAlertModifier(service: service))
    }
}
