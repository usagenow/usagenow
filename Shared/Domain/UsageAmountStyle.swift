import SwiftUI

/// Whether limits read as what's left or what's used. The popover, the
/// menu bar, and the widget all follow the same choice.
enum UsageAmountStyle: String, CaseIterable, Codable, Sendable {
    /// "58% left", with a bar that shrinks as the limit is used.
    case remaining
    /// "42% used", with a bar that grows.
    case used

    static let `default` = UsageAmountStyle.remaining

    /// The whole percent shown, following `UsagePercentage`'s rounding, so
    /// "0% left" and "100% used" both mean exhausted.
    func displayValue(_ usage: UsagePercentage) -> Int {
        self == .remaining ? usage.remainingDisplayValue : usage.displayValue
    }

    /// "58%" or "42%", without the word after it.
    func percent(_ usage: UsagePercentage) -> String {
        self == .remaining ? UsageFormatter.remainingPercent(usage) : UsageFormatter.percent(usage)
    }

    /// How much of the bar is filled.
    func barFraction(_ usage: UsagePercentage) -> Double {
        self == .remaining ? usage.remainingFraction : usage.fraction
    }

    /// The word that follows the percentage.
    var unit: Text {
        switch self {
        case .remaining: Text("left", comment: "Follows a remaining percentage, e.g. 58% left")
        case .used: Text("used", comment: "Follows a used percentage, e.g. 42% used")
        }
    }

    /// "58% left" or "42% used", for VoiceOver.
    func accessibilityDescription(_ usage: UsagePercentage) -> String {
        switch self {
        case .remaining: String(localized: "\(UsageFormatter.remainingPercent(usage)) left", comment: "Remaining quota, e.g. 58% left")
        case .used: String(localized: "\(UsageFormatter.percent(usage)) used", comment: "Used quota, e.g. 42% used")
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .remaining: "Remaining"
        case .used: "Used"
        }
    }
}

extension EnvironmentValues {
    /// Set once at the top of the popover and the widget.
    @Entry var usageAmountStyle: UsageAmountStyle = .default
}
