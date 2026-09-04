//
//  KeyboardDismiss.swift
//  neko-id
//
//  Global keyboard dismissal helper for SwiftUI screens.
//

import SwiftUI
import UIKit

extension View {
    /// Dismisses the iOS keyboard when the user taps anywhere outside a text input.
    ///
    /// The recognizer is installed on the host window with `cancelsTouchesInView = false`,
    /// so regular buttons, pickers, photo selectors and navigation taps still work normally.
    func nekoDismissKeyboardOnTap() -> some View {
        overlay {
            NekoKeyboardDismissInstaller()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
    }
}

private struct NekoKeyboardDismissInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            context.coordinator.installIfNeeded(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.installIfNeeded(from: uiView)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var installedWindow: UIWindow?
        private weak var tapRecognizer: UITapGestureRecognizer?

        func installIfNeeded(from view: UIView) {
            guard let window = view.window else { return }
            guard installedWindow !== window else { return }

            uninstall()

            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self

            window.addGestureRecognizer(recognizer)
            installedWindow = window
            tapRecognizer = recognizer
        }

        func uninstall() {
            if let recognizer = tapRecognizer {
                installedWindow?.removeGestureRecognizer(recognizer)
            }
            tapRecognizer = nil
            installedWindow = nil
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            recognizer.view?.endEditing(true)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let touchedView = touch.view else { return true }
            return !touchedView.nekoIsTextInputOrDescendant
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private extension UIView {
    var nekoIsTextInputOrDescendant: Bool {
        var current: UIView? = self
        while let view = current {
            if view is UITextField || view is UITextView || view is UISearchBar {
                return true
            }

            let className = NSStringFromClass(type(of: view))
            if className.contains("TextField") || className.contains("TextView") || className.contains("SearchField") {
                return true
            }

            current = view.superview
        }
        return false
    }
}
