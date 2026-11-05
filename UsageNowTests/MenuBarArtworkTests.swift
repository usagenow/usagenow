import AppKit
import Testing
@testable import UsageNow

@MainActor
struct MenuBarArtworkTests {
    @Test func everyProviderHasABoundedTemplateImage() {
        for definition in ProviderCatalog.available {
            let image = ProviderMenuBarArtwork.image(for: definition.id)
            #expect(image.size == NSSize(width: 15, height: 15))
            #expect(image.isTemplate)
            #expect(image === ProviderMenuBarArtwork.image(for: definition.id))
        }
    }

    @Test func antigravityHasVisibleArtworkAndATransparentBackground() throws {
        let image = ProviderMenuBarArtwork.image(for: .antigravity)
        let data = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: data))
        var transparent = 0
        var visible = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let alpha = try #require(bitmap.colorAt(x: x, y: y)).alphaComponent
                if alpha < 0.05 { transparent += 1 }
                if alpha > 0.5 { visible += 1 }
            }
        }
        #expect(transparent > bitmap.pixelsWide * bitmap.pixelsHigh / 4)
        #expect(visible > bitmap.pixelsWide * bitmap.pixelsHigh / 10)
        #expect(try #require(bitmap.colorAt(x: 0, y: 0)).alphaComponent == 0)
    }
}
