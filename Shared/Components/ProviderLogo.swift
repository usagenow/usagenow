import AppKit
import SwiftUI

/// A provider's logo on a small neutral tile.
struct ProviderLogoTile: View {
    let provider: ProviderID
    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 24

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size / 4, style: .continuous)
        ProviderLogo(provider: provider)
            .frame(width: size * 0.62, height: size * 0.62)
            .frame(width: size, height: size)
            .background(Palette.tileFill, in: shape)
            .overlay(shape.strokeBorder(Palette.tileStroke, lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// The provider's logo, from `ProviderCatalog`. Monochrome marks (OpenAI)
/// are template images that follow the foreground color; colored marks keep
/// their brand colors. Providers UsageNow has no artwork for show a neutral
/// SF Symbol rather than an invented icon.
struct ProviderLogo: View {
    let provider: ProviderID

    var body: some View {
        let definition = ProviderCatalog.definition(for: provider)
        if let asset = definition.logoAssetName, NSImage(named: asset) != nil {
            Image(asset)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.primary)
        } else {
            Image(systemName: definition.symbolName)
                .resizable()
                .scaledToFit()
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Provider logos") {
    HStack(spacing: 12) {
        ForEach(ProviderCatalog.all) { ProviderLogoTile(provider: $0.id) }
    }
    .padding()
}
