import Foundation

/// The product's identity in code. Everything a rebrand replaces lives in this `Brand` folder
/// (this file, the colours and wordmark in `Assets.xcassets`, `AppIcon.icon`, any `Fonts`), plus
/// `Config/Brand.xcconfig` and the copy keys listed in WHITE_LABEL.md.
nonisolated enum Brand {
    /// The product name people see: the wordmark's accessibility label and the messages that
    /// name the app. It is not translated.
    static let name = "VPlayed"

    /// The family name of the brand typeface (e.g. "Inter"), or nil for the system font (SF Pro).
    /// Put its font files (.ttf, .otf or .ttc, one per weight or a variable font) in `Brand/Fonts`;
    /// they are registered at launch. Characters the typeface lacks (Arabic or Tamil, often) fall
    /// back to the system font.
    static let fontFamily: String? = "Inter"
}
