import AppKit
import Carbon.HIToolbox
import Observation

/// Registers the shortcut that opens UsageNow from any app.
///
/// Uses Carbon's hot key API, the one way to get a system-wide shortcut
/// that needs no Accessibility or Input Monitoring permission: macOS tells
/// UsageNow only that its own combination was pressed, never what else is
/// typed.
@MainActor
@Observable
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    /// False when macOS refused the shortcut — another app holds it.
    private(set) var isRegistered = false

    @ObservationIgnored var action: (@MainActor () -> Void)?
    @ObservationIgnored private var hotKey: EventHotKeyRef?
    @ObservationIgnored private var handler: EventHandlerRef?

    private static let signature: OSType = 0x55_4E_4F_57 // "UNOW"

    /// Replaces the registered shortcut. `nil` leaves none.
    func register(_ shortcut: GlobalShortcut?) {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        isRegistered = false
        guard let shortcut else { return }
        installHandlerIfNeeded()

        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: 1),
            GetEventDispatcherTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            Log.app.notice("Couldn’t register the global shortcut: \(status, privacy: .public)")
            return
        }
        hotKey = reference
        isRegistered = true
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, _ in
                // Carbon delivers hot key events on the main thread.
                MainActor.assumeIsolated { GlobalHotKey.shared.action?() }
                return noErr
            },
            1,
            &spec,
            nil,
            &handler
        )
    }
}

/// The menu bar item, as AppKit keeps it. SwiftUI's `MenuBarExtra` doesn't
/// expose its status item; the shortcut's panel is placed under it.
@MainActor
enum MenuBarItem {
    /// Where the item is on screen, or `nil` when it isn't shown — hidden
    /// by a menu bar manager, or pushed out by the camera housing.
    static var frame: NSRect? {
        NSApp.windows.first { $0.className.contains("StatusBarWindow") }?.frame
    }
}
