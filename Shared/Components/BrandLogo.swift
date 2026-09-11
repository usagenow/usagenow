import AppKit
import SwiftUI

/// The UsageNow wordmark (symbol + name), tinted with the foreground style.
///
/// Falls back to the drawn symbol when the `UsageNowLogo` asset is missing.
struct BrandLogo: View {
    private static let hasAsset = NSImage(named: "UsageNowLogo") != nil

    var body: some View {
        Group {
            if Self.hasAsset {
                Image("UsageNowLogo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                UsageNowSymbolShape()
                    .aspectRatio(UsageNowSymbolShape.aspectRatio, contentMode: .fit)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: AppInfo.name))
        .accessibilityAddTraits(.isImage)
    }
}

/// The vertical-bar brand symbol drawn as a shape, using the geometry of
/// the `UsageNowSymbol` asset. Placeholder for contexts without assets.
struct UsageNowSymbolShape: Shape {
    private static let size = CGSize(width: 96.36, height: 98.41)
    static let aspectRatio = size.width / size.height

    private static let bars: [CGRect] = [
        CGRect(x: 0, y: 0.13, width: 18.83, height: 98.28),
        CGRect(x: 28.23, y: 0.14, width: 9.4, height: 49.14),
        CGRect(x: 37.64, y: 49.27, width: 9.4, height: 49.14),
        CGRect(x: 56.44, y: 0.13, width: 4.8, height: 49.14),
        CGRect(x: 61.23, y: 49.27, width: 4.8, height: 49.14),
        CGRect(x: 75.46, y: 0, width: 2.4, height: 49.36),
        CGRect(x: 82.12, y: 49.49, width: 2.4, height: 48.91),
        CGRect(x: 93.96, y: 0.02, width: 2.4, height: 98.28),
    ]

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / Self.size.width, rect.height / Self.size.height)
        let origin = CGPoint(
            x: rect.midX - Self.size.width * scale / 2,
            y: rect.midY - Self.size.height * scale / 2
        )
        var path = Path()
        for bar in Self.bars {
            path.addRect(CGRect(
                x: origin.x + bar.minX * scale,
                y: origin.y + bar.minY * scale,
                width: bar.width * scale,
                height: bar.height * scale
            ))
        }
        return path
    }
}

#Preview("Brand") {
    VStack(spacing: 16) {
        BrandLogo().frame(height: 16)
        UsageNowSymbolShape().frame(width: 40, height: 40)
    }
    .padding()
}
