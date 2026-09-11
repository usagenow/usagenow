import AppKit
import SwiftUI

extension View {
    /// Calls `action` whenever the hosting window becomes key. For a
    /// `MenuBarExtra` window, that's each time the popover opens.
    func onPopoverOpen(perform action: @escaping @MainActor () -> Void) -> some View {
        background(WindowKeyObserver(onBecomeKey: action))
    }
}

private struct WindowKeyObserver: NSViewRepresentable {
    let onBecomeKey: @MainActor () -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onBecomeKey = onBecomeKey
        return view
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onBecomeKey = onBecomeKey
    }

    final class ObserverView: NSView {
        var onBecomeKey: (@MainActor () -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard let window else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidBecomeKey),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
            if window.isKeyWindow {
                onBecomeKey?()
            }
        }

        @objc private func windowDidBecomeKey(_ notification: Notification) {
            onBecomeKey?()
        }
    }
}
