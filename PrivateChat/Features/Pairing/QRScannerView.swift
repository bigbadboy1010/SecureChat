import AVFoundation
import SwiftUI
import UIKit

struct QRScannerView: UIViewControllerRepresentable {
    let onCodeDetected: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        _ = context
        return QRScannerViewController(onCodeDetected: onCodeDetected)
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {
        _ = context
        uiViewController.update(onCodeDetected: onCodeDetected)
    }
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "org.francois.PrivateChat.qr-scanner.session", qos: .userInitiated)
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var onCodeDetected: (String) -> Void
    private var hasDetectedCode = false
    private var hasConfiguredSession = false
    private let messageLabel = UILabel()

    init(onCodeDetected: @escaping (String) -> Void) {
        self.onCodeDetected = onCodeDetected
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureMessageLabel()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        requestAndStartScanning()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        messageLabel.frame = CGRect(
            x: 16,
            y: view.bounds.height - 72,
            width: view.bounds.width - 32,
            height: 56
        )
    }

    func update(onCodeDetected: @escaping (String) -> Void) {
        self.onCodeDetected = onCodeDetected
    }

    private func configureMessageLabel() {
        messageLabel.text = "QR-Code in den Rahmen halten"
        messageLabel.textColor = .white
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 2
        messageLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        messageLabel.layer.cornerRadius = 12
        messageLabel.clipsToBounds = true
        view.addSubview(messageLabel)
    }

    private func requestAndStartScanning() {
        #if targetEnvironment(simulator)
        showSimulatorMessage()
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSessionIfNeeded()
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard granted else {
                        self?.showCameraDeniedMessage()
                        return
                    }
                    self?.configureSessionIfNeeded()
                    self?.startSession()
                }
            }
        case .denied, .restricted:
            showCameraDeniedMessage()
        @unknown default:
            showCameraDeniedMessage()
        }
        #endif
    }

    private func configureSessionIfNeeded() {
        guard hasConfiguredSession == false else {
            return
        }

        guard let captureDevice = AVCaptureDevice.default(for: .video) else {
            messageLabel.text = "Keine Kamera verfügbar."
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: captureDevice)
            guard session.canAddInput(input) else {
                messageLabel.text = "Kamera-Input nicht verfügbar."
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                messageLabel.text = "QR-Scanner-Output nicht verfügbar."
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr]

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.insertSublayer(layer, at: 0)
            previewLayer = layer
            hasConfiguredSession = true
        } catch {
            messageLabel.text = "Kamera konnte nicht gestartet werden."
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning == false else {
                return
            }
            self.session.startRunning()
        }
    }

    private func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else {
                return
            }
            self.session.stopRunning()
        }
    }

    private func showCameraDeniedMessage() {
        messageLabel.text = "Kamerazugriff ist deaktiviert. Pairing-Code kann manuell eingefügt werden."
    }

    private func showSimulatorMessage() {
        messageLabel.text = "QR-Scan ist im Simulator deaktiviert. Pairing-Code bitte manuell einfügen oder auf einem iPhone testen."
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        _ = output
        _ = connection
        guard hasDetectedCode == false else {
            return
        }
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue,
              value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return
        }

        hasDetectedCode = true
        stopSession()
        DispatchQueue.main.async { [onCodeDetected] in
            onCodeDetected(value)
        }
    }
}
