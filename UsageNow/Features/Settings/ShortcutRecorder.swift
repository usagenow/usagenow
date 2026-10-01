import AppKit
import SwiftUI

/// Records a global shortcut: click, then press the keys.
///
/// While recording, key presses in Settings go here instead of to the
/// window. Escape cancels; the button beside it removes the shortcut.
struct ShortcutRecorder: View {
    @Binding var shortcut: GlobalShortcut?

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                if isRecording {
                    Text("Press a shortcut…")
                } else if let shortcut {
                    Text(verbatim: shortcut.displayString)
                } else {
                    Text("Record Shortcut")
                }
            }
            .accessibilityLabel(Text("Keyboard shortcut"))
            .accessibilityValue(shortcut.map { Text(verbatim: $0.displayString) } ?? Text("None"))

            if shortcut != nil, !isRecording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove shortcut"))
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(GlobalShortcut.supportedModifiers)
            if event.keyCode == 53, modifiers.isEmpty { // Escape
                stopRecording()
            } else if let recorded = GlobalShortcut(event: event) {
                shortcut = recorded
                stopRecording()
            } else {
                NSSound.beep()
            }
            // Swallowed either way: the press was meant for the recorder.
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
