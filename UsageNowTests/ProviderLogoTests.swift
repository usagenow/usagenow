import AppKit
import SwiftUI
import Testing
@testable import UsageNow

@MainActor
struct ProviderLogoTests {
    @Test func newProviderLogosReplaceSystemSymbols() {
        #expect(ProviderCatalog.definition(for: .windsurf).logoAssetName == "WindsurfLogo")
        #expect(ProviderCatalog.definition(for: .elevenlabs).logoAssetName == "ElevenLabsLogo")
        #expect(ProviderCatalog.definition(for: .jetbrains).logoAssetName == "JetBrainsLogo")
        #expect(ProviderCatalog.definition(for: .perplexity).logoAssetName == "PerplexityLogo")
    }

    @Test(arguments: [ProviderID.windsurf, .elevenlabs, .perplexity])
    func monochromeLogoIsBundledAndAdaptsToTheTheme(provider: ProviderID) throws {
        let name = try #require(ProviderCatalog.definition(for: provider).logoAssetName)
        let image = try #require(NSImage(named: name), "The logo must load instead of falling back to an SF Symbol")
        #expect(image.isTemplate, "Monochrome artwork must follow the foreground color in both themes")
        #expect(image.size.width > 0 && image.size.height > 0)
    }

    @Test func jetBrainsKeepsItsBrandColors() throws {
        let image = try #require(NSImage(named: "JetBrainsLogo"))
        #expect(!image.isTemplate)
        #expect(image.size.width > 0 && image.size.height > 0)
    }

    @Test func updatedLogosRenderInBothThemes() throws {
        let folder = URL(fileURLWithPath: "/private/tmp/usagenow-1.0-icons", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, scheme, appearance) in [("light", ColorScheme.light, NSAppearance.Name.aqua), ("dark", .dark, .darkAqua)] {
            let content = VStack(alignment: .leading, spacing: 20) {
                ForEach([ProviderID.jetbrains, .perplexity], id: \.self) { provider in
                    HStack(spacing: 12) {
                        ProviderLogoTile(provider: provider)
                        Text(verbatim: provider.displayName).font(.body)
                    }
                }
            }
            .padding(24).frame(width: 320, height: 136, alignment: .leading)
            .foregroundStyle(.primary)
            .background(scheme == .light ? Color.white : Color(white: 0.12))
            .environment(\.colorScheme, scheme)
            let host = NSHostingView(rootView: content)
            host.appearance = NSAppearance(named: appearance)
            host.frame = NSRect(x: 0, y: 0, width: 320, height: 136)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            #expect(png.count > 1000)
            try png.write(to: folder.appending(path: "providers-\(name).png"))
        }
    }
}
