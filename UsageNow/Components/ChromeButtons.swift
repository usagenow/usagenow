import SwiftUI

/// A compact, borderless toolbar-style button with an SF Symbol and a hover highlight.
struct IconButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    /// Spins the symbol, e.g. while refreshing.
    var isSpinning = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: isSpinning)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(HoverHighlightButtonStyle(cornerRadius: 6))
        .help(title)
        .accessibilityLabel(title)
    }
}

/// A small secondary text button with a hover highlight, for popover chrome.
struct TextButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
        }
        .buttonStyle(HoverHighlightButtonStyle(cornerRadius: 5))
    }
}

/// Secondary foreground that turns primary with a subtle fill on hover or press.
struct HoverHighlightButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        HoverHighlight(configuration: configuration, cornerRadius: cornerRadius)
    }

    private struct HoverHighlight: View {
        let configuration: Configuration
        let cornerRadius: CGFloat

        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let isHighlighted = isEnabled && (isHovering || configuration.isPressed)
            configuration.label
                .foregroundStyle(isHighlighted ? .primary : .secondary)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Palette.hoverFill)
                        .opacity(isHighlighted ? 1 : 0)
                )
                .contentShape(.rect(cornerRadius: cornerRadius))
                .opacity(isEnabled ? 1 : 0.5)
                .onHover { isHovering = $0 }
        }
    }
}
