import Testing
@testable import UsageNow

struct PluralCategoryTests {
    @Test func russianHasThreeFormsForWholeNumbers() {
        let forms = [1, 2, 4, 5, 11, 12, 14, 21, 22, 25, 101, 111, 1_204].map { PluralCategory.of(Int64($0), language: "ru") }
        #expect(forms == [.one, .few, .few, .many, .many, .many, .many, .one, .few, .many, .one, .many, .few])
    }

    @Test func frenchCountsZeroAsOne() {
        #expect(PluralCategory.of(0, language: "fr") == .one)
        #expect(PluralCategory.of(1, language: "fr") == .one)
        #expect(PluralCategory.of(2, language: "fr") == .other)
    }

    @Test func englishGermanAndSpanishHaveOneAndOther() {
        for language in ["en", "de", "es"] {
            #expect(PluralCategory.of(1, language: language) == .one)
            #expect(PluralCategory.of(0, language: language) == .other)
            #expect(PluralCategory.of(7, language: language) == .other)
        }
    }
}
