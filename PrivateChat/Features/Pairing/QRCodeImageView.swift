import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct QRCodeImageView: View {
    let payload: String

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        Image(uiImage: makeQRCodeImage())
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .accessibilityLabel("PrivateChat Pairing QR-Code")
    }

    private func makeQRCodeImage() -> UIImage {
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else {
            return UIImage(systemName: "qrcode") ?? UIImage()
        }

        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return UIImage(systemName: "qrcode") ?? UIImage()
        }

        return UIImage(cgImage: cgImage)
    }
}
