//
// QRScannerView.swift
// schat
//

import SwiftUI
#if os(iOS)
import AVFoundation

struct QRScannerView: UIViewControllerRepresentable {
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let parent: QRScannerView

        init(parent: QRScannerView) {
            self.parent = parent
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !parent.didScan else { return }
            guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject else { return }
            guard obj.type == .qr else { return }
            guard let value = obj.stringValue, !value.isEmpty else { return }

            parent.didScan = true
            parent.onResult(.success(value))
        }
    }

    enum ScanError: Error, LocalizedError {
        case cameraUnavailable
        case permissionDenied
        case setupFailed

        var errorDescription: String? {
            switch self {
            case .cameraUnavailable:
                return "Kamera nicht verfügbar."
            case .permissionDenied:
                return "Kamera-Berechtigung verweigert."
            case .setupFailed:
                return "Scanner konnte nicht initialisiert werden."
            }
        }
    }

    let onResult: (Result<String, Error>) -> Void
    @Binding var didScan: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .black

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .denied || status == .restricted {
            DispatchQueue.main.async { onResult(.failure(ScanError.permissionDenied)) }
            return vc
        }

        guard let device = AVCaptureDevice.default(for: .video) else {
            DispatchQueue.main.async { onResult(.failure(ScanError.cameraUnavailable)) }
            return vc
        }

        let session = AVCaptureSession()
        session.sessionPreset = .high

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
        } catch {
            DispatchQueue.main.async { onResult(.failure(error)) }
            return vc
        }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) { session.addOutput(output) }
        output.setMetadataObjectsDelegate(context.coordinator, queue: DispatchQueue.main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = vc.view.bounds
        vc.view.layer.addSublayer(preview)

        // Start session asynchronously
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }

        // Keep session alive on the controller
        objc_setAssociatedObject(vc, &AssociatedKeys.sessionKey, session, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(vc, &AssociatedKeys.previewKey, preview, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // keep preview layer sized correctly on rotation
        if let preview = objc_getAssociatedObject(uiViewController, &AssociatedKeys.previewKey) as? AVCaptureVideoPreviewLayer {
            preview.frame = uiViewController.view.bounds
        }
    }

    private struct AssociatedKeys {
        static var sessionKey: UInt8 = 0
        static var previewKey: UInt8 = 0
    }
}
#endif
