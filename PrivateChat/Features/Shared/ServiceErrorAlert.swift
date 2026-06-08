import SwiftUI

struct ServiceErrorAlertModifier: ViewModifier {
    @ObservedObject var service: ConversationService
    @State private var presentedMessage: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: service.lastErrorMessage) { message in
                guard let message, message.isEmpty == false else {
                    return
                }
                presentedMessage = message
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

    private func dismissError() {
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
