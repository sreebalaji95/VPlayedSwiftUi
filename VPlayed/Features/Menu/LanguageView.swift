import SwiftUI

/// Picks the app language from the backend's list (`LanguageStore.languages`). Each option shows its
/// own name ("العربية") with the name in the current language underneath ("Arabic"), and the app
/// switches as soon as one is tapped.
struct LanguageView: View {
    @Environment(LanguageStore.self) private var languageStore
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GlassGroup {
                    VStack(spacing: 10) {
                        ForEach(languageStore.languages) { language in
                            Button { languageStore.select(language) } label: {
                                row(for: language)
                            }
                            .buttonStyle(GlassRowStyle.style)
                            .accessibilityAddTraits(language == languageStore.language ? .isSelected : [])
                        }
                    }
                }
                Text(L10n.shared(.languageFooter, Brand.name))
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .padding(.horizontal, 14)
            }
            .padding(Theme.Spacing.gutter)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .navigationTitle(Text(L10n.shared(.navLanguage)))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for language: AppLanguage) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: language.nativeName)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                if let localizedName = locale.localizedString(forLanguageCode: language.code),
                   localizedName != language.nativeName {
                    Text(verbatim: localizedName)
                        .font(Theme.Typography.bodySmall)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            Spacer(minLength: 8)
            if language == languageStore.language {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.primary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 40)
    }
}
