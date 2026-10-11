import CoreText
import Foundation

/// Makes the brand typeface's bundled font files available to the app, so `Brand.fontFamily` can
/// name it without listing each file in Info.plist (`UIAppFonts` on iOS and visionOS,
/// `ATSApplicationFontsPath` on macOS).
enum BrandFonts {
    /// Registers every font file in the app bundle for this process. Call once at launch, before
    /// any text draws. Does nothing when the brand uses the system font.
    static func registerBundledFonts() {
        guard Brand.fontFamily != nil else { return }
        for url in fontFiles {
            // Fails harmlessly if the file is already registered or isn't a font.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Font files anywhere in the app's resources, whichever folder they were copied into.
    static var fontFiles: [URL] {
        guard let resources = Bundle.main.resourceURL,
              let files = FileManager.default.enumerator(at: resources, includingPropertiesForKeys: nil)
        else { return [] }
        return files.compactMap { $0 as? URL }.filter { ["ttf", "otf", "ttc"].contains($0.pathExtension.lowercased()) }
    }
}
