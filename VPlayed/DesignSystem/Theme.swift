import SwiftUI

/// Design tokens from the VPlayed prototype (dark theme, `vp-ds-tokens.css`).
enum Theme {
    /// Colours live in `Assets.xcassets/Colors`; these refer to them through Xcode's generated
    /// asset symbols, so a renamed or missing asset fails the build. Most have a light value and
    /// a Dark appearance and follow the system theme; the exceptions are noted below.
    enum Palette {
        static let background = Color(.background)
        static let surface = Color(.surface)
        static let raised = Color(.raised)
        static let neutral700 = Color(.neutral700)
        static let sunken = Color(.sunken)

        static let textPrimary = Color(.textPrimary)
        static let textSecondary = Color(.textSecondary)
        static let textTertiary = Color(.textTertiary)
        static let muted = Color(.muted)

        /// The brand reds are the same in both themes.
        static let brand = Color(.brand)
        static let brandPressed = Color(.brandPressed)
        /// Secondary yellow highlight. The app's main accent is the red `AccentColor` asset.
        static let accent = Color(.accentYellow)
        static let teal = Color(.accentTeal)
        static let amber = Color(.amber)
        /// Dark text for light fills, in both themes.
        static let onLight = Color(.onLight)

        static let line = Color(.line)
        static let line2 = Color(.line2)
        /// Always dark: backs chips and labels drawn on artwork, which stay dark in both themes.
        static let scrim = Color(.scrim)
        /// The highlight that sweeps across skeleton placeholders while content loads.
        static let shimmer = Color(.shimmerHighlight)
    }

    enum Radius {
        static let badge: CGFloat = 4
        static let control: CGFloat = 8
        static let card: CGFloat = 12
        static let panel: CGFloat = 16
        static let popover: CGFloat = 24
    }

    enum Spacing {
        static let gutter: CGFloat = 16
    }

    enum Layout {
        static let headerLogoHeight: CGFloat = 26
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Parses `#RRGGBB` / `RRGGBB` strings as returned by the API (e.g. `bg_card_color`).
    init?(hexString: String?) {
        guard var value = hexString?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let hex = UInt32(value, radix: 16) else { return nil }
        self.init(hex: hex)
    }
}
