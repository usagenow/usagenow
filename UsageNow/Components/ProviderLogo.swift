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

/// The provider's logo asset. Monochrome marks (OpenAI) are template images
/// that follow the foreground color; colored marks keep their brand colors.
/// Falls back to a neutral SF Symbol if the asset is missing.
struct ProviderLogo: View {
    let provider: ProviderID

    var body: some View {
        if NSImage(named: provider.logoAssetName) != nil {
            Image(provider.logoAssetName)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.primary)
        } else {
            Image(systemName: provider.fallbackSymbolName)
                .resizable()
                .scaledToFit()
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
    }
}

extension ProviderID {
    var logoAssetName: String {
        switch self {
        case .codex: "OpenAILogo"
        case .claudeCode: "ClaudeLogo"
        }
    }

    var fallbackSymbolName: String {
        switch self {
        case .codex: "terminal"
        case .claudeCode: "asterisk"
        }
    }
}

#Preview("Provider logos") {
    HStack(spacing: 12) {
        ForEach(ProviderID.allCases) { ProviderLogoTile(provider: $0) }
    }
    .padding()
}
