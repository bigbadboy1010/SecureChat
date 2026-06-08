import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var showMessageActions = false
    @State private var selectedMessage: BitchatMessage?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack {
                Text("Chats")
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(.systemBackground))
            .border(width: 1, edges: [.bottom], color: .gray.opacity(0.2))

            // Messages List
            ZStack {
                if viewModel.messages.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("Keine Nachrichten")
                            .font(.headline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                                    .onTapGesture {
                                        selectedMessage = message
                                        showMessageActions = true
                                    }
                            }
                        }
                        .padding()
                    }
                }

                if viewModel.isLoading {
                    ProgressView()
                }
            }

            // Input Area
            HStack(spacing: 12) {
                TextField("Nachricht eingeben...", text: $viewModel.messageText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit {
                        viewModel.sendMessage()
                    }

                Button(action: viewModel.sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.blue)
                }
                .disabled(viewModel.messageText.isEmpty)
            }
            .padding()
            .background(Color(.systemBackground))
            .border(width: 1, edges: [.top], color: .gray.opacity(0.2))
        }
        .onAppear {
            viewModel.loadMessages()
        }
        .actionSheet(isPresented: $showMessageActions) {
            ActionSheet(title: Text("Nachrichtenoptionen"), buttons: [
                .destructive(Text("Löschen")) {
                    if let message = selectedMessage {
                        viewModel.deleteMessage(message.id)
                    }
                },
                .default(Text("Kopieren")) {
                    if let message = selectedMessage {
                        UIPasteboard.general.string = message.content
                    }
                },
                .cancel()
            ])
        }
    }
}

struct MessageBubble: View {
    let message: BitchatMessage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.senderID)
                .font(.caption)
                .foregroundColor(.gray)
            
            Text(message.content)
                .padding(12)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            
            HStack(spacing: 4) {
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.gray)
                
                Spacer()
                
                Image(systemName: deliveryStatusIcon(message.deliveryStatus))
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func deliveryStatusIcon(_ status: DeliveryStatus) -> String {
        switch status {
        case .pending: return "clock"
        case .sent: return "checkmark"
        case .delivered: return "checkmark.2"
        case .read: return "checkmark.2"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

struct ChatTabView: View {
    var body: some View {
        NavigationView {
            ChatView()
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ChatView()
}
