// SecureChat/BIT/Views/QRInviteSheet.swift
import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRInviteSheet: View {
    @EnvironmentObject var viewModel: ChatViewModel
    let channel: String

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        VStack(spacing: 16) {
            Text("Invite QR")
                .font(.title2.weight(.semibold))

            if let invite = viewModel.channelInviteString(for: channel),
               let uiImage = makeQRImage(from: invite) {
                Image(uiImage: uiImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 320, maxHeight: 320)
                    .padding()

                Text(invite)
                    .font(.footnote)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            } else {
                Text("QR konnte nicht erzeugt werden (kein Invite verfügbar).")
                    .foregroundStyle(.secondary)
            }

            Text("Channel: \(channel)")
                .font(.footnote)
                .textSelection(.enabled)
        }
        .padding()
    }

    private func makeQRImage(from string: String) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgimg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgimg)
    }
}
