import SwiftUI

/// Artwork frame shared by rail and grid cards: raised fill, 1pt hairline, rounded corners and
/// the bottom fade the prototype draws over every card image.
struct CardArtwork: View {
    let url: URL?
    /// Fixed size for rail cards; nil fills the offered width at `aspectRatio` (grid cards).
    private let size: CGSize?
    private let aspectRatio: CGFloat
    private let cornerRadius: CGFloat
    /// Bottom fade: opacity at the bottom edge and where it reaches transparent (0…1 from the bottom).
    private let fade: (opacity: Double, end: Double)?

    init(
        url: URL?,
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat = Theme.Radius.control,
        fade: (opacity: Double, end: Double)? = (0.75, 0.48)
    ) {
        self.url = url
        size = CGSize(width: width, height: height)
        aspectRatio = height > 0 ? width / height : 16 / 9
        self.cornerRadius = cornerRadius
        self.fade = fade
    }

    /// Fills the offered width, e.g. a grid column, at `aspectRatio` (width / height).
    init(
        url: URL?,
        aspectRatio: CGFloat,
        cornerRadius: CGFloat = Theme.Radius.control,
        fade: (opacity: Double, end: Double)? = (0.75, 0.48)
    ) {
        self.url = url
        size = nil
        self.aspectRatio = aspectRatio
        self.cornerRadius = cornerRadius
        self.fade = fade
    }

    var body: some View {
        sized(RemoteImage(url: url))
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

    @ViewBuilder
    private func sized(_ image: RemoteImage) -> some View {
        if let size {
            image.frame(width: size.width, height: size.height)
        } else {
            Color.clear
                .aspectRatio(aspectRatio, contentMode: .fit)
                .overlay { image }
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
                    .foregroundStyle(Theme.Palette.highlight)
                    .frame(width: 32, height: height)
                    .background(
                        LinearGradient(
                            colors: [Theme.Palette.fillStrong, Theme.Palette.background],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: shape
                    )
            case .comingSoon, .price:
                Text(label)
                    .font(Theme.Typography.badge)
                    .letterSpacing(0.66)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.highlight)
                    .padding(.horizontal, 11)
                    .frame(height: height)
                    .background(Theme.Palette.scrim.opacity(0.82), in: shape)
            }
        }
        .overlay { shape.strokeBorder(Theme.Palette.highlight.opacity(0.55), lineWidth: 1) }
        .environment(\.colorScheme, .dark)
        .accessibilityLabel(accessibilityText)
    }

    private var label: String {
        switch tag {
        case .comingSoon: L10n.string(.commonComingSoonCaps)
        case .price(let value): value.uppercased()
        case .crown: ""
        }
    }

    private var accessibilityText: String {
        switch tag {
        case .comingSoon: L10n.string(.commonComingSoon)
        case .price(let value): L10n.string(.homePrice, [value])
        case .crown: L10n.string(.navSubscription)
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

/// Outline rank numeral for Top-10 rails (prototype: Inter 800, no fill, a `lineStrong` stroke).
/// SwiftUI can't stroke glyphs, so the outline is built from offset copies masked by the glyph.
struct RankNumeral: View {
    let rank: Int
    let height: CGFloat

    /// Heavy-weight digits have a cap height of ~0.72em, so this makes the glyphs fill `height`.
    private var fontSize: CGFloat { height * 1.38 }

    var body: some View {
        let digits = Text(rank, format: .number).font(Theme.Typography.rankNumeral(size: fontSize))
        ZStack {
            ForEach(Self.offsets.indices, id: \.self) { index in
                digits
                    .foregroundStyle(Theme.Palette.lineStrong)
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
