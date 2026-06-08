//
// ChannelInviteView.swift
// schat
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ChannelInviteView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    let channelTag: String

    @State private var showScanner: Bool = false
    @State private var scanDidComplete: Bool = false
    @State private var scanError: String? = nil
    @State private var scanSuccess: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            Text("Channel Invite")
                .font(.system(size: 18, weight: .semibold, design: .monospaced))

            Text(channelTag)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .textSelection(.enabled)

            if let payload = viewModel.channelInviteString(for: channelTag) {
                QRCodeBlock(payload: payload)
            } else {
                Text("Invite konnte nicht erzeugt werden.")
                    .font(.system(size: 12, design: .monospaced))
            }

            Button("Invite scannen") {
                scanDidComplete = false
                scanError = nil
                scanSuccess = nil
                showScanner = true
            }
            .buttonStyle(.borderedProminent)

            if let scanSuccess {
                Text(scanSuccess)
                    .font(.system(size: 12, design: .monospaced))
            }
            if let scanError {
                Text(scanError)
                    .font(.system(size: 12, design: .monospaced))
            }

            Spacer(minLength: 0)
        }
        .padding()
        .sheet(isPresented: $showScanner) {
            #if os(iOS)
            InviteScannerSheet(
                onDone: { result in
                    showScanner = false
                    switch result {
                    case .success(let code):
                        let ok = viewModel.applyInviteString(code)
                        scanSuccess = ok ? "✅ Invite übernommen" : "❌ Ungültiger Invite"
                    case .failure(let err):
                        scanError = "❌ \(err.localizedDescription)"
                    }
                }
            )
            #else
            Text("QR-Scan ist nur auf iOS verfügbar.")
                .padding()
            #endif
        }
    }
}

private struct QRCodeBlock: View {
    let payload: String

    var body: some View {
        #if os(iOS)
        if let image = QRCodeUtil.generateQRCode(from: payload) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 260, maxHeight: 260)
                .background(Color.white)
                .cornerRadius(12)
            Text(payload)
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
        } else {
            Text("QR konnte nicht generiert werden.")
                .font(.system(size: 12, design: .monospaced))
        }
        #else
        Text(payload)
            .font(.system(size: 12, design: .monospaced))
            .textSelection(.enabled)
        #endif
    }
}

#if os(iOS)
private struct InviteScannerSheet: View {
    let onDone: (Result<String, Error>) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var didScan: Bool = false
    @State private var lastError: String? = nil

    var body: some View {
        ZStack {
            QRScannerView(onResult: { result in
                switch result {
                case .success:
                    onDone(result)
                case .failure(let err):
                    lastError = err.localizedDescription
                    onDone(.failure(err))
                }
            }, didScan: $didScan)
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button("Close") {
                        dismiss()
                    }
                    .padding()
                    .background(Color.black.opacity(0.5))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .padding()

                Spacer()

                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [10]))
                    .frame(width: 260, height: 260)
                    .padding(.bottom, 40)

                if let lastError {
                    Text(lastError)
                        .foregroundColor(.white)
                        .padding(.bottom, 20)
                }
            }
        }
    }
}
#endif
