import Foundation
import Observation
import UIKit
// Kotlin classes are not Sendable; the language store is thread-safe and only read here.
@preconcurrency import Shared

/// A language the user can pick. The list comes from the backend (`mediaview/api/v1/language`,
/// through the shared layer's `SupportedLanguagesStore`); until it loads, or when it cannot, the
/// languages the app has translations for are offered. The choice is stored as the app's
/// `AppleLanguages`, the same per-app setting iOS Settings → VPlayed → Language writes, so the
/// in-app picker and Settings always agree and the choice survives relaunches.
///
/// App text comes from the shared string catalog; a language without its own translations (Telugu,
/// Hindi) shows the English text, while titles and descriptions from the API follow the language.
nonisolated struct AppLanguage: Hashable, Identifiable, Sendable {
    /// ISO 639-1 code ("en", "ar", "ta").
    let code: String
    /// The backend's English name ("Tamil"); used when the system has no name for the code.
    let name: String
    /// Right-to-left script, from the shared rule.
    let isRightToLeft: Bool

    var id: String { code }

    init(_ language: Shared.Language) {
        code = language.code
        name = language.name
        isRightToLeft = language.isRightToLeft
    }

    var locale: Locale { Locale(identifier: code) }

    /// The language's name in that language ("தமிழ்", "Português"), so people can find theirs
    /// whatever the UI shows.
    var nativeName: String {
        locale.localizedString(forLanguageCode: code)?.capitalized(with: locale) ?? name
    }

    /// The chosen language, else the best match for the system's preferred languages, else the
    /// backend's default. Also drives the API's `X-Language-Code` header and which entry of a
    /// `{"en": …}` field is shown. Read from any thread.
    static var current: AppLanguage {
        let preferences = UserDefaults.standard.stringArray(forKey: preferencesKey) ?? Locale.preferredLanguages
        return AppLanguage(SharedLayer.graph.supportedLanguagesStore.resolve(preferred: preferences))
    }

    fileprivate static func select(_ language: AppLanguage) {
        UserDefaults.standard.set([language.code], forKey: preferencesKey)
    }

    private static let preferencesKey = "AppleLanguages"
}

/// Observable holder for the UI language and the languages on offer, owned by `RootView`, so
/// picking a language re-renders the app in it immediately.
@Observable
final class LanguageStore {
    private(set) var language = AppLanguage.current
    /// What Menu → Language lists: the backend's languages once loaded.
    private(set) var languages: [AppLanguage]

    /// The common API can turn right-to-left layout off; the text stays in the chosen language.
    var isRTLAllowed = true {
        didSet {
            guard isRTLAllowed != oldValue else { return }
            Self.applyLayoutDirectionToUIKit(rightToLeft: isRightToLeft)
        }
    }

    /// The layout direction to use: the language's, unless right-to-left is turned off.
    var isRightToLeft: Bool { Self.isRightToLeft(language, allowed: isRTLAllowed) }

    @ObservationIgnored private var subscription: Shared.Closeable?

    init(store: SupportedLanguagesStore = SharedLayer.graph.supportedLanguagesStore) {
        languages = store.current.map(AppLanguage.init)
        Self.applyLayoutDirectionToUIKit(rightToLeft: isRightToLeft)
        L10n.shared.setLanguage(language.code)
        // The list loads at launch (`AppStartup`); a saved language it adds (e.g. Telugu) applies then.
        subscription = store.watchLanguages { [weak self] languages in
            MainActor.assumeIsolated { self?.update(languages.map(AppLanguage.init)) }
        }
    }

    deinit {
        subscription?.close()
    }

    func select(_ language: AppLanguage) {
        guard language != self.language else { return }
        AppLanguage.select(language)
        // Before `language` changes, so the views `RootView` rebuilds for it pick this up.
        Self.applyLayoutDirectionToUIKit(rightToLeft: Self.isRightToLeft(language, allowed: isRTLAllowed))
        L10n.shared.setLanguage(language.code)
        self.language = language
    }

    private func update(_ languages: [AppLanguage]) {
        self.languages = languages
        let resolved = AppLanguage.current
        guard resolved != language else { return }
        Self.applyLayoutDirectionToUIKit(rightToLeft: Self.isRightToLeft(resolved, allowed: isRTLAllowed))
        L10n.shared.setLanguage(resolved.code)
        language = resolved
    }

    private static func isRightToLeft(_ language: AppLanguage, allowed: Bool) -> Bool {
        language.isRightToLeft && allowed
    }

    /// UIKit lays out bars in the direction of the language the app launched in, not SwiftUI's
    /// `layoutDirection`, so after switching between left-to-right and right-to-left languages
    /// toolbar items land on the wrong side (Home's menu button must be on the right in Arabic).
    /// Forcing the direction makes UIKit views created from now on follow `language`; `RootView`
    /// rebuilds its tabs (`.id`) on every switch, so their bars are new.
    private static func applyLayoutDirectionToUIKit(rightToLeft: Bool) {
        UIView.appearance().semanticContentAttribute = rightToLeft ? .forceRightToLeft : .forceLeftToRight
    }
}
