import SwiftUI

/// Design tokens from the VPlayed prototype (dark theme, `vp-ds-tokens.css`).
enum Theme {
    /// Colours by role. They live in `Brand/Assets.xcassets/Colors` (named after the role) and are read
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

    /// Text styles by role, with the prototype's sizes and weights, in the brand typeface
    /// (`Brand.fontFamily`, else SF Pro). Views use these for text; SF Symbol sizes are icon
    /// metrics and stay in the views.
    enum Typography {
        /// The hero's title.
        static let heroTitle = font(37, .bold)
        /// Large screen title (placeholder screens).
        static let pageTitle = font(22, .bold)
        /// Login step headings ("Sign in or create your account") on phones.
        static let authTitle = font(20, .bold)
        /// Login step headings in regular width (iPad, Mac).
        static let authTitleLarge = font(26, .bold)
        /// Each digit of the sign-in code.
        static let codeDigit = font(20, .bold)
        /// Text typed into form fields.
        static let fieldValue = font(16, .semibold)
        /// Full-width form buttons: Continue, social sign-in, Continue as guest.
        static let formButton = font(16, .semibold)
        /// Labels above form fields.
        static let fieldLabel = font(12, .semibold)
        /// Small capitals above a step heading ("STEP 1 OF 3").
        static let stepLabel = font(11, .bold)
        /// Message titles, bulk-purchase names and prices.
        static let title = font(20, .bold)
        /// Home rail headers.
        static let railTitle = font(19.5, .bold)
        /// Channel names on channel cards.
        static let headline = font(16, .bold)
        /// The hero's "Watch now".
        static let buttonLarge = font(16, .bold)
        /// Menu and Language row titles.
        static let rowTitle = font(16, .medium)
        /// The value at the end of a menu row.
        static let rowValue = font(15, .regular)
        /// Titles under top-10 landscape cards.
        static let rankedTitleLarge = font(15, .bold)
        /// Titles under top-10 portrait cards.
        static let rankedTitle = font(14, .bold)
        /// Text buttons: retry, Watch Live, Set reminder, Explore bundles.
        static let button = font(14, .bold)
        /// Titles on and under cards.
        static let cardTitle = font(14, .semibold)
        /// Secondary controls and toasts: Skip intro, load-more retry, notices.
        static let controlLabel = font(14, .semibold)
        /// Messages and summaries.
        static let body = font(14, .regular)
        /// Synopses, bundle descriptions, the splash tagline, secondary row text.
        static let bodySmall = font(13, .regular)
        /// Emphasized short notes.
        static let note = font(13, .semibold)
        /// Explanatory footnotes; scales with Dynamic Type.
        static let footnote = Brand.fontFamily.map { Font.custom($0, size: 13, relativeTo: .footnote) } ?? .footnote
        /// Metadata lines: genre and duration, views and likes, dates, artists.
        static let caption = font(12, .regular)
        /// Follower counts.
        static let captionMedium = font(12.5, .medium)
        /// Small capitals on badges and tags: LIVE, categories, prices, durations.
        static let badge = font(11, .bold)
        /// Initials standing in for a logo.
        static let monogram = font(11, .heavy)

        /// Outline numerals on top-10 rails, sized to the card.
        static func rankNumeral(size: CGFloat) -> Font {
            font(size, .heavy)
        }

        private static func font(_ size: CGFloat, _ weight: Font.Weight) -> Font {
            if let family = Brand.fontFamily {
                // The family's face nearest to `weight`, at a fixed size like the system styles.
                .custom(family, fixedSize: size).weight(weight)
            } else {
                .system(size: size, weight: weight)
            }
        }
    }

    enum Radius {
        static let badge: CGFloat = 4
        static let control: CGFloat = 8
        static let card: CGFloat = 12
        static let panel: CGFloat = 16
        /// Menu and Language rows.
        static let row: CGFloat = 22
        static let popover: CGFloat = 24
    }

    enum Spacing {
        static let gutter: CGFloat = 16
        /// The equal gap between Home rows (the hero and each rail), and below the last one.
        static let railGap: CGFloat = 20
        /// Between a rail's title and its cards.
        static let railTitleGap: CGFloat = 8
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
