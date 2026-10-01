import AppKit
import SwiftUI

/// The window the global shortcut opens: the same content as the menu bar
/// window, in a panel of UsageNow's own, placed under the menu bar item.
///
/// SwiftUI's `MenuBarExtra` window can't be opened from code — a
/// programmatic click on its menu bar item does nothing — so the shortcut
/// can't simply show that one.
@MainActor
final class ShortcutPanelController: NSObject, NSWindowDelegate {
    private static let cornerRadius: CGFloat = 12
    /// Space between the menu bar and the panel, and to the screen's edges.
    private static let margin: CGFloat = 6

    private let content: () -> AnyView
    private let onOpen: () -> Void
    private var panel: ShortcutPanel?
    private var hosting: NSHostingView<AnyView>?

    init(content: @escaping () -> AnyView, onOpen: @escaping () -> Void) {
        self.content = content
        self.onOpen = onOpen
    }

    var isOpen: Bool { panel?.isVisible == true }

    func toggle() {
        isOpen ? close() : open()
    }

    func close() {
        panel?.orderOut(nil)
        // Rebuilt on the next open, so nothing keeps ticking while hidden.
        panel?.contentView = nil
        hosting = nil
    }

    private func open() {
        let panel = panel ?? makePanel()
        self.panel = panel

        let root = AnyView(
            content()
                .background(PanelMaterial())
                .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                .fixedSize()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { [weak self] in self?.place(size: $0) }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        self.hosting = hosting
        panel.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        place(size: hosting.fittingSize)

        panel.makeKeyAndOrderFront(nil)
        onOpen()
    }

    private func makePanel() -> ShortcutPanel {
        let panel = ShortcutPanel(
            contentRect: NSRect(x: 0, y: 0, width: MenuBarContentView.width, height: 300),
            // Takes the keyboard without bringing UsageNow in front of the
            // app the person is working in.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        return panel
    }

    /// Keeps the panel's top edge under the menu bar as its content grows,
    /// centered on the menu bar item when that's on screen.
    private func place(size: CGSize) {
        guard let panel, size.width > 0, size.height > 0 else { return }
        let anchor = MenuBarItem.frame
        let screen = anchor.flatMap { frame in NSScreen.screens.first { $0.frame.intersects(frame) } } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let centerX = anchor.map(\.midX) ?? (visible.maxX - size.width / 2 - Self.margin)
        let x = min(max(centerX - size.width / 2, visible.minX + Self.margin), visible.maxX - size.width - Self.margin)
        let top = visible.maxY - Self.margin
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
        panel.invalidateShadow()
    }

    /// Like the menu bar window, it closes when the person clicks elsewhere.
    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

/// A borderless panel can't take the keyboard unless it says it can.
private final class ShortcutPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Escape closes it.
    override func cancelOperation(_ sender: Any?) {
        (delegate as? ShortcutPanelController)?.close()
    }
}

/// The system's popover material, under the same tint the menu bar window uses.
private struct PanelMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
