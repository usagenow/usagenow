import AppKit
import SwiftUI

/// Neutral surface colors tuned separately for light and dark appearance.
///
/// Semantic system styles like `.quaternary` nearly disappear on the dark
/// popover material, so these set explicit, slightly stronger values there.
enum Palette {
    static let track = Color(light: .black.opacity(0.08), dark: .white.opacity(0.13))
    static let trackHighContrast = Color(light: .black.opacity(0.22), dark: .white.opacity(0.32))

    static let tileFill = Color(light: .white, dark: .white.opacity(0.09))
    static let tileStroke = Color(light: .black.opacity(0.09), dark: .white.opacity(0.10))

    static let badgeFill = Color(light: .black.opacity(0.05), dark: .white.opacity(0.10))
    static let hoverFill = Color(light: .black.opacity(0.06), dark: .white.opacity(0.10))
}

extension Color {
    /// A color that resolves differently in light and dark appearance.
    init(light: Color, dark: Color) {
        let light = NSColor(light)
        let dark = NSColor(dark)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}
