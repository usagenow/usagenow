import AppKit
import Testing
@testable import UsageNow

@MainActor
struct ProviderLogoTests {
    @Test func newProviderLogosReplaceSystemSymbols() {
        #expect(ProviderCatalog.definition(for: .windsurf).logoAssetName == "WindsurfLogo")
        #expect(ProviderCatalog.definition(for: .elevenlabs).logoAssetName == "ElevenLabsLogo")
    }

    @Test(arguments: [ProviderID.windsurf, .elevenlabs])
    func monochromeLogoIsBundledAndAdaptsToTheTheme(provider: ProviderID) throws {
        let name = try #require(ProviderCatalog.definition(for: provider).logoAssetName)
        let image = try #require(NSImage(named: name), "The logo must load instead of falling back to an SF Symbol")
        #expect(image.isTemplate, "Monochrome artwork must follow the foreground color in both themes")
        #expect(image.size.width > 0 && image.size.height > 0)
    }
}
