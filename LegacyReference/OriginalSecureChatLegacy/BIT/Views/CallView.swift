import SwiftUI

struct CallView: View {
    @StateObject private var callService = CallService.shared
    @State private var inCall = false
    @State private var selectedPeer: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Anrufe")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.systemBackground))
                .border(width: 1, edges: [.bottom], color: .gray.opacity(0.2))

            if inCall {
                CallActiveView(
                    peerID: selectedPeer ?? "Unknown",
                    onEndCall: { inCall = false }
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(callService.callHistory, id: \.id) { record in
                            CallHistoryRow(record: record)
                                .onTapGesture {
                                    selectedPeer = record.peerID
                                    inCall = true
                                }
                        }
                    }
                    .padding()
                }
            }

            Spacer()
        }
    }
}

struct CallActiveView: View {
    let peerID: String
    var onEndCall: () -> Void
    
    @State private var isMicEnabled = true
    @State private var isCameraEnabled = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Anruf mit \(peerID)")
                .font(.headline)
            
            Spacer()

            // Call Duration
            Text("00:45")
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundColor(.blue)

            Spacer()

            // Controls
            HStack(spacing: 40) {
                Button(action: { isMicEnabled.toggle() }) {
                    Image(systemName: isMicEnabled ? "mic.fill" : "mic.slash.fill")
                        .font(.system(size: 24))
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Color.gray.opacity(0.3)))
                        .foregroundColor(.black)
                }

                Button(action: { isCameraEnabled.toggle() }) {
                    Image(systemName: isCameraEnabled ? "video.fill" : "video.slash.fill")
                        .font(.system(size: 24))
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Color.gray.opacity(0.3)))
                        .foregroundColor(.black)
                }

                Button(action: onEndCall) {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 24))
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Color.red))
                        .foregroundColor(.white)
                }
            }

            Spacer()
        }
        .padding()
    }
}

struct CallHistoryRow: View {
    let record: CallService.CallRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.peerID)
                    .fontWeight(.semibold)
                Text("\(record.duration)s • \(record.type.rawValue)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            Image(systemName: record.direction == .incoming ? "arrow.down.left" : "arrow.up.right")
                .foregroundColor(record.direction == .incoming ? .blue : .green)

            Button(action: {}) {
                Image(systemName: "phone.fill")
                    .foregroundColor(.blue)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct CallsTabView: View {
    var body: some View {
        NavigationView {
            CallView()
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    CallView()
}
