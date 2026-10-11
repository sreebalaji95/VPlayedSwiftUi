import SwiftUI

/// Artwork frame shared by rail cards: raised fill, 1pt hairline, rounded corners and the
/// bottom fade the prototype draws over every card image.
struct CardArtwork: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = Theme.Radius.control
    /// Bottom fade: opacity at the bottom edge and where it reaches transparent (0…1 from the bottom).
    var fade: (opacity: Double, end: Double)? = (0.75, 0.48)

    var body: some View {
        RemoteImage(url: url)
            .frame(width: width, height: height)
            .background(Theme.Palette.raised)
            .overlay {
                if let fade {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(fade.opacity), location: 0.02),
                            .init(color: .clear, location: fade.end),
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Theme.Palette.line, lineWidth: 1)
            }
    }
}

/// Top-right access tag: crown (subscription), COMING SOON, or a price. Drawn on artwork, so it
/// stays dark in both themes.
struct CornerTag: View {
    let tag: AccessTag
    var height: CGFloat = 26

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: Theme.Radius.control,
            bottomTrailingRadius: 0,
            topTrailingRadius: Theme.Radius.control
        )
    }

    var body: some View {
        Group {
            switch tag {
            case .crown:
                Image(systemName: "crown.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.accent)
                    .frame(width: 32, height: height)
                    .background(
                        LinearGradient(
                            colors: [Theme.Palette.neutral700, Theme.Palette.background],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: shape
                    )
            case .comingSoon, .price:
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .letterSpacing(0.66)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.accent)
                    .padding(.horizontal, 11)
                    .frame(height: height)
                    .background(Theme.Palette.scrim.opacity(0.82), in: shape)
            }
        }
        .overlay { shape.strokeBorder(Theme.Palette.accent.opacity(0.55), lineWidth: 1) }
        .environment(\.colorScheme, .dark)
        .accessibilityLabel(accessibilityText)
    }

    private var label: String {
        switch tag {
        case .comingSoon: String(localized: "COMING SOON", bundle: .localized)
        case .price(let value): value.uppercased()
        case .crown: ""
        }
    }

    private var accessibilityText: String {
        switch tag {
        case .comingSoon: String(localized: "Coming soon", bundle: .localized)
        case .price(let value): String(localized: "Price \(value)", bundle: .localized)
        case .crown: String(localized: "Subscription", bundle: .localized)
        }
    }
}

/// Press feedback for Home's rail cards and rail titles: a slight shrink and dim, matching the
/// prototype's `:active`. Content, not controls, so it stays outside the Liquid Glass styles.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// Outline rank numeral for Top-10 rails (prototype: Inter 800, no fill, 15% `line2` stroke).
/// SwiftUI can't stroke glyphs, so the outline is built from offset copies masked by the glyph.
struct RankNumeral: View {
    let rank: Int
    let height: CGFloat

    /// Heavy-weight digits have a cap height of ~0.72em, so this makes the glyphs fill `height`.
    private var fontSize: CGFloat { height * 1.38 }

    var body: some View {
        let digits = Text("\(rank)").font(.system(size: fontSize, weight: .heavy))
        ZStack {
            ForEach(Self.offsets.indices, id: \.self) { index in
                digits
                    .foregroundStyle(Theme.Palette.line2)
                    .offset(x: Self.offsets[index].width, y: Self.offsets[index].height)
            }
            digits.foregroundStyle(Theme.Palette.background)
        }
        .tracking(-fontSize * 0.06)
        .fixedSize()
        // Sit the glyphs on the baseline rather than the line box, which includes descender space.
        .alignmentGuide(.bottom) { $0[.lastTextBaseline] }
        .frame(height: height, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private static let offsets: [CGSize] = stride(from: 0.0, to: 360.0, by: 30.0).map { degrees in
        let radians = degrees * .pi / 180
        return CGSize(width: cos(radians) * 1.4, height: sin(radians) * 1.4)
    }
}
