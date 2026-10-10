import SwiftUI

/// Solid 56pt top bar: menu on the left; search tile, mic and notifications on the right.
struct HomeHeaderView: View {
    @Environment(\.openRoute) private var openRoute

    var body: some View {
        HStack(spacing: 0) {
            iconButton("line.3.horizontal", size: 22, label: "Menu") { openRoute(.menu) }
            Spacer(minLength: 0)
            Button { openRoute(.search) } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.Palette.muted)
                    .frame(width: 44, height: 44)
                    .background(Theme.Palette.sunken, in: .rect(cornerRadius: Theme.Radius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.control)
                            .strokeBorder(Theme.Palette.line, lineWidth: 1)
                    }
            }
            .buttonStyle(PressableButtonStyle(scale: 0.94))
            .accessibilityLabel("Search")
            iconButton("mic", size: 20, label: "Voice search") { openRoute(.voiceSearch) }
            iconButton("bell", size: 20, label: "Notifications") { openRoute(.notifications) }
        }
        .padding(.leading, 6)
        .padding(.trailing, Theme.Spacing.gutter - 6)
        .frame(height: Theme.Layout.headerHeight)
        .background(Theme.Palette.background.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Theme.Palette.line.frame(height: 1) }
    }

    private func iconButton(_ symbol: String, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.9))
        .accessibilityLabel(label)
    }
}
