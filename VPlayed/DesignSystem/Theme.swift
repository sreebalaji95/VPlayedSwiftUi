import SwiftUI

/// Design tokens from the VPlayed prototype (dark theme, `vp-ds-tokens.css`).
enum Theme {
    /// Colours by role. They live in `Assets.xcassets/Colors` (named after the role) and are read
    /// through Xcode's generated asset symbols, so a renamed or missing asset fails the build.
    /// Most have a light value and a Dark appearance and follow the system theme; the exceptions
    /// are noted below.
    enum Palette {
        /// Page background; the hero artwork fades into it.
        static let background = Color(.background)
        /// Card backgrounds.
        static let surface = Color(.surface)
        /// Placeholders, skeletons, toasts and icon tiles: one step up from `surface`.
        static let raised = Color(.raised)
        /// A stronger neutral fill: failed images, the crown tag.
        static let fillStrong = Color(.fillStrong)

        static let textPrimary = Color(.textPrimary)
        static let textSecondary = Color(.textSecondary)
        static let textTertiary = Color(.textTertiary)

        /// The brand's main colour (red for VPlayed), from the `AccentColor` asset and the same in
        /// both themes: the selected tab, primary actions, the LIVE badge. Rebrand it there.
        static let primary = Color(.accent)
        /// Text and icons drawn on `primary` fills, in both themes. Keep it readable against
        /// `primary` (white for a dark primary, dark for a light one).
        static let onPrimary = Color(.onPrimary)
        /// Secondary highlight (yellow for VPlayed): crowns, prices, the hero's dots.
        static let highlight = Color(.highlight)
        /// Dark text for light fills, in both themes.
        static let onLight = Color(.onLight)

        /// Hairline borders.
        static let line = Color(.line)
        /// A more visible line: toast borders, rank numeral outlines.
        static let lineStrong = Color(.lineStrong)
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
