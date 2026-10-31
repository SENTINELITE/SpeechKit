import SwiftUI
import UIKit

/// A separate opaque window covers every presentation in this scene, including sheets.
struct DemoPrivacyCover: UIViewRepresentable {
    func makeUIView(context: Context) -> PrivacyCoverAnchor { PrivacyCoverAnchor() }
    func updateUIView(_ uiView: PrivacyCoverAnchor, context: Context) {}
    static func dismantleUIView(_ uiView: PrivacyCoverAnchor, coordinator: ()) { uiView.removeCover() }

    final class PrivacyCoverAnchor: UIView {
        private var coverWindow: UIWindow?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            removeCover()
            guard let scene = window?.windowScene else { return }

            let cover = UIWindow(windowScene: scene)
            cover.windowLevel = .alert + 1
            cover.backgroundColor = .black
            let controller = UIViewController()
            controller.view.backgroundColor = .black
            cover.rootViewController = controller
            cover.isUserInteractionEnabled = false
            coverWindow = cover
            cover.isHidden = scene.activationState == .foregroundActive

            NotificationCenter.default.addObserver(self, selector: #selector(hideContent), name: UIScene.willDeactivateNotification, object: scene)
            NotificationCenter.default.addObserver(self, selector: #selector(hideContent), name: UIScene.didEnterBackgroundNotification, object: scene)
            NotificationCenter.default.addObserver(self, selector: #selector(showContent), name: UIScene.didActivateNotification, object: scene)
        }

        func removeCover() {
            NotificationCenter.default.removeObserver(self)
            coverWindow?.isHidden = true
            coverWindow = nil
        }

        @objc private func hideContent() { coverWindow?.isHidden = false }
        @objc private func showContent() { coverWindow?.isHidden = true }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}
