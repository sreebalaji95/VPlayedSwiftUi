import CoreText
import Testing
@testable import VPlayed

struct BrandTests {
    /// A brand that names a typeface must ship it: otherwise every text style silently falls back
    /// to the system font.
    @Test(.enabled(if: Brand.fontFamily != nil, "The brand uses the system font"))
    func brandTypefaceIsAvailable() throws {
        let family = try #require(Brand.fontFamily)
        let font = CTFontCreateWithName(family as CFString, 12, nil)
        #expect(CTFontCopyFamilyName(font) as String == family)
    }
}
