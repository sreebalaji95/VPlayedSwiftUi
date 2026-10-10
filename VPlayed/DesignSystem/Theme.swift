import SwiftUI

/// Design tokens from the VPlayed prototype (dark theme, `vp-ds-tokens.css`).
enum Theme {
    enum Palette {
        static let background = Color(hex: 0x0A0A0B)
        static let surface = Color(hex: 0x131316)
        static let raised = Color(hex: 0x1B1C21)
        static let neutral700 = Color(hex: 0x26282E)
        static let sunken = Color(hex: 0x0C0C0E)

        static let textPrimary = Color(hex: 0xF6F7F9)
        static let textSecondary = Color(hex: 0xB7BCC4)
        static let textTertiary = Color(hex: 0x646A75)
        static let muted = Color(hex: 0x8B919C)

        static let brand = Color(hex: 0xFF0935)
        static let brandPressed = Color(hex: 0xB0071F)
        static let accent = Color(hex: 0xFFD119)
        static let teal = Color(hex: 0x0DCEA6)
        static let amber = Color(hex: 0xF5A623)
        static let onLight = Color(hex: 0x131316)

        static let line = Color.white.opacity(0.08)
        static let line2 = Color.white.opacity(0.15)
        static let scrim = Color(hex: 0x0A0A0B)

        /// The 140° logo gradient used for brand accents.
        static let logoGradient = LinearGradient(
            stops: [
                .init(color: brand, location: 0),
                .init(color: amber, location: 0.34),
                .init(color: accent, location: 0.66),
                .init(color: Color(hex: 0x00C9A7), location: 1),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
        static let headerHeight: CGFloat = 56
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
