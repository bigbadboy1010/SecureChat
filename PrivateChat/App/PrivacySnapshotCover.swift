import SwiftUI
import UIKit

/// A separate scene window covers presented sheets as well as the chat root
/// before the system takes an app-switcher snapshot. It contains no user data.
struct PrivacySnapshotCover: UIViewRepresentable {
    let isCovered: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SceneReaderView {
        let reader = SceneReaderView()
        reader.isUserInteractionEnabled = false
        reader.onScene = { [weak coordinator = context.coordinator] scene in
            coordinator?.attach(scene)
        }
        context.coordinator.setCovered(isCovered)
        return reader
    }

    func updateUIView(_ uiView: SceneReaderView, context: Context) {
        context.coordinator.setCovered(isCovered)
        context.coordinator.attach(uiView.window?.windowScene)
    }

    static func dismantleUIView(_ uiView: SceneReaderView, coordinator: Coordinator) {
        uiView.onScene = nil
        coordinator.close()
    }

    final class SceneReaderView: UIView {
        var onScene: ((UIWindowScene?) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onScene?(window?.windowScene)
        }
    }

    final class Coordinator {
        private var coverWindow: UIWindow?
        private var isCovered = false

        func attach(_ scene: UIWindowScene?) {
            guard let scene else { return }
            if coverWindow?.windowScene !== scene {
                close()
                let window = UIWindow(windowScene: scene)
                window.frame = scene.coordinateSpace.bounds
                window.windowLevel = .alert + 1
                window.backgroundColor = .systemBackground
                window.rootViewController = UIHostingController(rootView: CoverContent())
                coverWindow = window
            }
            coverWindow?.frame = scene.coordinateSpace.bounds
            coverWindow?.isHidden = !isCovered
        }

        func setCovered(_ covered: Bool) {
            isCovered = covered
            coverWindow?.isHidden = !covered
        }

        func close() {
            coverWindow?.isHidden = true
            coverWindow?.rootViewController = nil
            coverWindow = nil
        }
    }

    private struct CoverContent: View {
        var body: some View {
            ZStack {
                Color(red: 0.04, green: 0.08, blue: 0.11).ignoresSafeArea()
                VStack(spacing: 18) {
                    Image(systemName: "lock.fill").font(.system(size: 38, weight: .medium))
                    Text("PrivateRoom").font(.title2.weight(.semibold))
                    Text("Dein privater Raum ist gesperrt.").font(.subheadline)
                }
                .foregroundStyle(.white)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
