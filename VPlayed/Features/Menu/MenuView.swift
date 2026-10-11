import SwiftUI

/// The hamburger menu, opened from the Home toolbar: browse destinations, then app settings.
struct MenuView: View {
    @Environment(\.openRoute) private var openRoute
    @Environment(LanguageStore.self) private var languageStore

    var body: some View {
        ScrollView {
            GlassGroup {
                VStack(spacing: 10) {
                    Button { openRoute(.movies) } label: {
                        MenuRow(symbol: "film", title: "Movies") { EmptyView() }
                    }
                    .buttonStyle(GlassRowStyle.style)
                    .padding(.bottom, 14)

                    Button { openRoute(.language) } label: {
                        MenuRow(symbol: "globe", title: "Language") {
                            Text(verbatim: languageStore.language.nativeName)
                        }
                    }
                    .buttonStyle(GlassRowStyle.style)
                }
            }
            .padding(Theme.Spacing.gutter)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .navigationTitle(Text("Menu"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// The glass row used by Menu and Language.
enum GlassRowStyle {
    static let style = GlassCardButtonStyle(shape: RoundedRectangle(cornerRadius: 22), padding: 14)
}

/// Icon, title, trailing value and a forward chevron (mirrored in right-to-left languages).
private struct MenuRow<Value: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    @ViewBuilder let value: () -> Value

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(width: 32, height: 32)
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer(minLength: 8)
            value()
                .font(.system(size: 15))
                .foregroundStyle(Theme.Palette.textSecondary)
            Image(systemName: "chevron.forward")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
