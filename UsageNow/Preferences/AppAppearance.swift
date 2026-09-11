import Foundation

/// The app's color theme. Light by default; `system` follows macOS.
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case light
    case dark
    case system

    static let `default` = AppAppearance.light

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "System"
        }
    }
}
