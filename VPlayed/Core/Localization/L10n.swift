import Foundation
import Observation
// Kotlin classes are not Sendable; the catalog lookups are thread-safe.
@preconcurrency import Shared

/// The app's text, read from the shared string catalog in the Kotlin Multiplatform layer
/// (`kmp/shared/src/commonMain/composeResources`), the same strings AndroidJP shows.
///
/// SwiftUI's `LocalizedStringKey` lookups don't reach that catalog, so views pass the resolved
/// `String`: `Text(L10n.shared(.homeFeatured))`. A `String` given to `Text` is shown as it is.
/// Lookups through `shared` read `languageCode`, so the views re-render when the language changes
/// (`RootView` also rebuilds its tabs). Code off the main actor uses the `nonisolated` static
/// functions.
///
/// Placeholders are positional (`%1$s`…); pass numbers already formatted for the locale
/// (`formatted(_:)`). Catalog lookups follow the app's `AppleLanguages`, which `LanguageStore`
/// writes before it switches; a language without translations shows English.
@Observable
final class L10n {
    static let shared = L10n()

    /// The language the catalog is read in.
    private(set) var languageCode: String

    private init() {
        languageCode = SharedStrings.shared.languageCode
    }

    func setLanguage(_ code: String) {
        SharedStrings.shared.setLanguage(code: code)
        languageCode = SharedStrings.shared.languageCode
    }

    /// The string for `key`, with `%1$s`… replaced by `args`.
    func callAsFunction(_ key: L10nKey, _ args: String...) -> String {
        _ = languageCode
        return Self.string(key, args)
    }

    /// The plural form of `key` for `count`, with `%1$s`… replaced by `args`.
    func plural(_ key: L10nPluralKey, count: Int, _ args: String...) -> String {
        _ = languageCode
        return Self.plural(key, count: count, args)
    }

    /// `value` with the digits and grouping of the app language (Arabic-Indic digits in Arabic).
    func number(_ value: Int) -> String {
        value.formatted(.number.locale(Locale(identifier: languageCode)))
    }

    /// A string written in Markdown (`**bold**`, `[link](target)`), styled.
    func markdown(_ key: L10nKey, _ args: String...) -> AttributedString {
        _ = languageCode
        return Self.attributed(Self.string(key, args))
    }

    /// A plural string written in Markdown, styled.
    func markdownPlural(_ key: L10nPluralKey, count: Int, _ args: String...) -> AttributedString {
        _ = languageCode
        return Self.attributed(Self.plural(key, count: count, args))
    }

    nonisolated static func string(_ key: L10nKey, _ args: [String] = []) -> String {
        SharedStrings.shared.string(key: key.rawValue, args: args)
    }

    nonisolated static func plural(_ key: L10nPluralKey, count: Int, _ args: [String] = []) -> String {
        SharedStrings.shared.plural(key: key.rawValue, quantity: Int32(clamping: count), args: args)
    }

    /// The text of a catalog string the shared layer chose (`AuthMessageKey.resource`,
    /// `messageResource(error)`…). Messages that name the brand get `Brand.name`.
    nonisolated static func message(_ resource: LibraryStringResource) -> String {
        SharedStrings.shared.resource(resource: resource, args: [Brand.name])
    }

    private nonisolated static func attributed(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }

    #if DEBUG
    /// Every key Swift names exists in the catalog (a renamed key would otherwise show as its name).
    nonisolated static func assertCatalogMatches() {
        let missing = L10nKey.allCases.map(\.rawValue).filter { !SharedStrings.shared.hasKey(key: $0) }
            + L10nPluralKey.allCases.map(\.rawValue).filter { !SharedStrings.shared.hasKey(key: $0) }
        assert(missing.isEmpty, "L10nKey is out of date; run kmp/scripts/generate-swift-l10n-keys.py. Missing: \(missing)")
    }
    #endif
}
