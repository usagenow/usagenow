import AppKit
import Carbon.HIToolbox

/// A key and its modifiers, pressed anywhere on the Mac to open UsageNow.
///
/// There is no default: any combination is already taken in somebody's
/// setup, so the person records their own in Settings.
struct GlobalShortcut: Codable, Equatable, Sendable {
    /// The hardware key, independent of the keyboard layout.
    var keyCode: UInt16
    /// `NSEvent.ModifierFlags`, limited to ⌃ ⌥ ⇧ ⌘.
    var modifiers: UInt
    /// The key as it read on the person's layout when recorded, e.g. "U".
    var key: String

    static let supportedModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    /// The shortcut for a key press, or `nil` when it can't be one: a
    /// letter with no modifier, or with Shift alone, is ordinary typing.
    /// Function keys work on their own.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(Self.supportedModifiers)
        let code = event.keyCode
        guard !flags.intersection([.control, .option, .command]).isEmpty || Self.functionKeys[code] != nil else { return nil }
        guard let key = Self.label(keyCode: code, characters: event.charactersIgnoringModifiers) else { return nil }
        self.init(keyCode: code, modifiers: flags.rawValue, key: key)
    }

    init(keyCode: UInt16, modifiers: UInt, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// "⌃⌥⌘U", modifiers in the order macOS writes them.
    var displayString: String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + key
    }

    /// The modifiers as Carbon's hot key API takes them.
    var carbonModifiers: UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var carbon = 0
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.shift) { carbon |= shiftKey }
        if flags.contains(.command) { carbon |= cmdKey }
        return UInt32(carbon)
    }

    private static func label(keyCode: UInt16, characters: String?) -> String? {
        if let named = namedKeys[keyCode] ?? functionKeys[keyCode] { return named }
        guard let characters, let first = characters.first, !first.isWhitespace, !first.isNewline else { return nil }
        return String(first).uppercased()
    }

    private static let namedKeys: [UInt16: String] = [
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Return): "↩",
        UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Delete): "⌫",
        UInt16(kVK_ForwardDelete): "⌦",
        UInt16(kVK_Escape): "⎋",
        UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_Home): "↖",
        UInt16(kVK_End): "↘",
        UInt16(kVK_PageUp): "⇞",
        UInt16(kVK_PageDown): "⇟",
    ]

    private static let functionKeys: [UInt16: String] = [
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15", UInt16(kVK_F16): "F16",
        UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18", UInt16(kVK_F19): "F19", UInt16(kVK_F20): "F20",
    ]
}
