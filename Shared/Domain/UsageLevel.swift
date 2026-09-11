/// Semantic severity of a usage value.
///
/// Drives subtle tinting in the popover today, and menu bar states and
/// notifications later.
enum UsageLevel: Int, Sendable, CaseIterable, Comparable {
    case normal
    case elevated
    case high
    case critical

    /// Thresholds in whole percent: 0–69 normal, 70–84 elevated,
    /// 85–94 high, 95–100 critical.
    init(percent: Int) {
        switch percent {
        case ..<70: self = .normal
        case 70..<85: self = .elevated
        case 85..<95: self = .high
        default: self = .critical
        }
    }

    static func < (lhs: UsageLevel, rhs: UsageLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
