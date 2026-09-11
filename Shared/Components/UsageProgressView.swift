import SwiftUI

/// A thin bar showing how much of a limit is left — it shrinks as usage
/// grows. Empty when exhausted or unknown.
///
/// Hidden from accessibility: the enclosing row describes the value.
struct UsageProgressView: View {
    let usage: UsagePercentage?
    /// Thinner in the widget than in the popover.
    var height: CGFloat = 5
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(trackStyle)
                if let usage, usage.remainingDisplayValue > 0 {
                    Capsule()
                        .fill(usage.level.tint)
                        .frame(width: max(height, proxy.size.width * usage.remainingFraction))
                }
            }
        }
        .frame(height: height)
        .overlay {
            if contrast == .increased {
                Capsule().strokeBorder(.secondary, lineWidth: 0.5)
            }
        }
        .animation(.smooth(duration: 0.35), value: usage)
        .accessibilityHidden(true)
    }

    private var trackStyle: Color {
        contrast == .increased ? Palette.trackHighContrast : Palette.track
    }
}

#Preview("Levels") {
    VStack(spacing: 12) {
        ForEach([0, 12, 52, 74, 88, 97, 100], id: \.self) { percent in
            UsageProgressView(usage: UsagePercentage(percent: Double(percent)))
        }
        UsageProgressView(usage: nil)
    }
    .padding()
    .frame(width: 240)
}
