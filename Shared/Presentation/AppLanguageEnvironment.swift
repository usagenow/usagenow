import SwiftUI

extension View {
    /// A per-app language also controls reading direction when the Mac's
    /// own language is different. System mode keeps the inherited setting.
    @ViewBuilder
    func appLanguage(_ language: AppLanguage?) -> some View {
        if let language, language != .system, let locale = language.locale {
            environment(\.locale, locale)
                .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
        } else {
            self
        }
    }
}
