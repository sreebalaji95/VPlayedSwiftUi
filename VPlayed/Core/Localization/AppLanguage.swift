import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// The languages the app ships in. The choice is stored as the app's `AppleLanguages`, the same
/// per-app setting iOS Settings → VPlayed → Language writes, so the in-app picker and Settings
/// always agree and the choice survives relaunches.
nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case arabic = "ar"
    case portuguese = "pt"
    case tamil = "ta"

    var id: Self { self }

    /// The language's name in that language, so people can find theirs whatever the UI shows.
    var nativeName: String {
        switch self {
        case .english: "English"
        case .arabic: "العربية"
        case .portuguese: "Português"
        case .tamil: "தமிழ்"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    var isRightToLeft: Bool { locale.language.characterDirection == .rightToLeft }

    /// The chosen language, else the best match for the system's preferred languages. Also drives
    /// the API's `X-Language-Code` header and which entry of a `{"en": …}` field is shown.
    static var current: AppLanguage {
        let preferences = UserDefaults.standard.stringArray(forKey: preferencesKey) ?? Locale.preferredLanguages
        let match = Bundle.preferredLocalizations(from: allCases.map(\.rawValue), forPreferences: preferences).first
        return match.flatMap(AppLanguage.init(rawValue:)) ?? .english
    }

    fileprivate static func select(_ language: AppLanguage) {
        UserDefaults.standard.set([language.rawValue], forKey: preferencesKey)
    }

    private static let preferencesKey = "AppleLanguages"
}

/// Observable holder for the UI language, owned by `RootView`, so picking a language re-renders
/// the app in it immediately.
@Observable
final class LanguageStore {
    private(set) var language = AppLanguage.current

    init() {
        Self.applyLayoutDirectionToUIKit(for: language)
    }

    func select(_ language: AppLanguage) {
        guard language != self.language else { return }
        AppLanguage.select(language)
        // Before `language` changes, so the views `RootView` rebuilds for it pick this up.
        Self.applyLayoutDirectionToUIKit(for: language)
        self.language = language
    }

    /// UIKit lays out bars in the direction of the language the app launched in, not SwiftUI's
    /// `layoutDirection`, so after switching between left-to-right and right-to-left languages
    /// toolbar items land on the wrong side (Home's menu button must be on the right in Arabic).
    /// Forcing the direction makes UIKit views created from now on follow `language`; `RootView`
    /// rebuilds its tabs (`.id`) on every switch, so their bars are new.
    private static func applyLayoutDirectionToUIKit(for language: AppLanguage) {
        #if canImport(UIKit)
        UIView.appearance().semanticContentAttribute = language.isRightToLeft ? .forceRightToLeft : .forceLeftToRight
        #endif
    }
}

nonisolated extension Bundle {
    /// The `.lproj` bundle for the current `AppLanguage`. Strings built in code pass it to
    /// `String(localized:bundle:)`, because `Bundle.main` only picks its language at launch.
    /// SwiftUI `Text` literals follow the `locale` environment that `RootView` sets.
    static var localized: Bundle {
        guard let path = Bundle.main.path(forResource: AppLanguage.current.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
}
