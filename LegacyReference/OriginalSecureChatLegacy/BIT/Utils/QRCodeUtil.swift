import UIKit
import CoreImage.CIFilterBuiltins

class QRCodeUtil {
    static func generateQRCode(from string: String) -> UIImage? {
        let data = Data(string.utf8)
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")

        if let output = filter.outputImage,
           let cgImage = context.createCGImage(output.transformed(by: CGAffineTransform(scaleX: 10, y: 10)), from: output.extent) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }
}
