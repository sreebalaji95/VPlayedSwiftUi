import CoreText
import Foundation
#if os(iOS)
import UIKit
#endif

/// Makes the brand typeface's bundled font files available to the app, so `Brand.fontFamily` can
/// name it without listing each file in Info.plist (`UIAppFonts` on iOS and visionOS,
/// `ATSApplicationFontsPath` on macOS).
enum BrandFonts {
    /// Registers every font file in the app bundle for this process and puts the typeface in the
    /// system bars. Call once at launch, before any text draws. Does nothing when the brand uses
    /// the system font.
    static func registerBundledFonts() {
        guard Brand.fontFamily != nil else { return }
        for url in fontFiles {
            // Fails harmlessly if the file is already registered or isn't a font.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        styleSystemBars()
    }

    /// Navigation titles and tab bar labels are drawn by UIKit, so SwiftUI's `.font` never
    /// reaches them; their appearance proxies get the brand typeface at the system sizes instead.
    private static func styleSystemBars() {
        #if os(iOS)
        guard let family = Brand.fontFamily else { return }
        func font(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let descriptor = UIFontDescriptor(fontAttributes: [
                .family: family,
                .traits: [UIFontDescriptor.TraitKey.weight: weight],
            ])
            return UIFont(descriptor: descriptor, size: size)
        }
        // Titles scale with Dynamic Type like the system ones.
        let bar = UINavigationBar.appearance()
        bar.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: font(17, .semibold))]
        bar.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: font(34, .bold))]
        // Item appearance alone is ignored by the iOS 26 tab bar. Only the font is set, so the
        // default background (Liquid Glass) and the tint colours stay. Tab labels keep the
        // system's fixed size (Dynamic Type shows the large-content viewer instead), and a
        // scaled font would come out larger than the system's.
        let tabs = UITabBarAppearance()
        let label: [NSAttributedString.Key: Any] = [.font: font(10, .medium)]
        for layout in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
            layout.normal.titleTextAttributes = label
            layout.selected.titleTextAttributes = label
        }
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
        #endif
    }

    /// Font files anywhere in the app's resources, whichever folder they were copied into.
    static var fontFiles: [URL] {
        guard let resources = Bundle.main.resourceURL,
              let files = FileManager.default.enumerator(at: resources, includingPropertiesForKeys: nil)
        else { return [] }
        return files.compactMap { $0 as? URL }.filter { ["ttf", "otf", "ttc"].contains($0.pathExtension.lowercased()) }
    }
}
