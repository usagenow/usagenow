import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import UsageNow

@MainActor
struct GlobalShortcutTests {
    private func keyDown(_ characters: String, keyCode: Int, modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(keyCode)
        )!
    }

    @Test func writesModifiersInTheSystemOrder() {
        let shortcut = GlobalShortcut(event: keyDown("u", keyCode: kVK_ANSI_U, modifiers: [.command, .option, .control, .shift]))
        #expect(shortcut?.displayString == "⌃⌥⇧⌘U")
        #expect(shortcut?.carbonModifiers == UInt32(cmdKey | optionKey | controlKey | shiftKey))
    }

    @Test func ordinaryTypingIsNotAShortcut() {
        #expect(GlobalShortcut(event: keyDown("u", keyCode: kVK_ANSI_U, modifiers: [])) == nil)
        #expect(GlobalShortcut(event: keyDown("U", keyCode: kVK_ANSI_U, modifiers: [.shift])) == nil)
    }

    @Test func functionAndNamedKeysHaveNames() {
        #expect(GlobalShortcut(event: keyDown("\u{F70C}", keyCode: kVK_F9, modifiers: []))?.displayString == "F9")
        #expect(GlobalShortcut(event: keyDown(" ", keyCode: kVK_Space, modifiers: [.control, .option]))?.displayString == "⌃⌥Space")
    }

    /// The shortcut's panel is placed under the menu bar item, which
    /// SwiftUI doesn't expose. If a macOS release moves it, this fails
    /// before a person finds out.
    @Test func findsTheMenuBarItem() async throws {
        for _ in 0..<50 where MenuBarItem.frame == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(MenuBarItem.frame != nil)
    }

    /// macOS accepts a shortcut through the hot key API, with no permission asked.
    @Test func registersWithTheSystem() {
        let hotKey = GlobalHotKey.shared
        hotKey.register(GlobalShortcut(keyCode: UInt16(kVK_F19), modifiers: NSEvent.ModifierFlags([.control, .option, .shift, .command]).rawValue, key: "F19"))
        #expect(hotKey.isRegistered)
        hotKey.register(nil)
        #expect(!hotKey.isRegistered)
    }

    @Test func isRememberedAndCanBeRemoved() {
        let suite = "GlobalShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let preferences = AppPreferences(defaults: defaults)
        #expect(preferences.popoverShortcut == nil)
        #expect(!preferences.notifiesAboutLimits)

        let shortcut = GlobalShortcut(keyCode: UInt16(kVK_ANSI_U), modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue, key: "U")
        preferences.popoverShortcut = shortcut
        preferences.notifiesAboutLimits = true
        #expect(AppPreferences(defaults: defaults).popoverShortcut == shortcut)
        #expect(AppPreferences(defaults: defaults).notifiesAboutLimits)

        preferences.popoverShortcut = nil
        #expect(AppPreferences(defaults: defaults).popoverShortcut == nil)
    }
}
