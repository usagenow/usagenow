import SwiftUI

/// A compact, borderless toolbar-style button with an SF Symbol and a hover highlight.
struct IconButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(HoverHighlightButtonStyle(cornerRadius: 6))
        .help(title)
        .accessibilityLabel(title)
    }
}

/// Refresh, with the progress it causes drawn around it.
///
/// At rest it's just an arrow, the same weight as the settings gear beside
/// it. While a refresh runs, an arc sweeps around the arrow and the arrow
/// itself steps back — the motion says "working" without the icon jittering
/// in place.
struct RefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void

    @State private var sweep = Angle.zero

    private var title: LocalizedStringKey { isRefreshing ? "Refreshing…" : "Refresh" }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .rotationEffect(sweep)
                    .frame(width: 21, height: 21)
                    .opacity(isRefreshing ? 1 : 0)
                    .scaleEffect(isRefreshing ? 1 : 0.7)

                Image(systemName: "arrow.trianglehead.clockwise")
                    .font(.system(size: isRefreshing ? 10.5 : 13, weight: isRefreshing ? .semibold : .medium))
                    .opacity(isRefreshing ? 0.5 : 1)
            }
            .frame(width: 26, height: 26)
            .animation(.smooth(duration: 0.25), value: isRefreshing)
        }
        .buttonStyle(HoverHighlightButtonStyle(cornerRadius: 6))
        .help(title)
        .accessibilityLabel(title)
        .task(id: isRefreshing) {
            guard isRefreshing else {
                sweep = .zero
                return
            }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                sweep = .degrees(360)
            }
        }
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
