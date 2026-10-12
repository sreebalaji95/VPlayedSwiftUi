import SwiftUI

/// 16:9 card, 172pt wide (the prototype's `hcard` is 158pt).
struct LandscapeCard: View {
    let item: ContentItem
    var width: CGFloat = 172

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardArtwork(url: item.landscapeImageURL, width: width, height: width * 9 / 16)
                .overlay(alignment: .topTrailing) {
                    if let tag = AccessTag.resolve(for: item) { CornerTag(tag: tag) }
                }
            CardTitle(text: item.title)
        }
        .frame(width: width, alignment: .leading)
    }
}

/// Portrait card, 112pt wide at 221:295 (prototype `pcard`).
struct PortraitCard: View {
    let item: ContentItem
    var width: CGFloat = 112

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardArtwork(url: item.portraitImageURL, width: width, height: width * 295 / 221, fade: (0.85, 0.42))
                .overlay(alignment: .topTrailing) {
                    if let tag = AccessTag.resolve(for: item) { CornerTag(tag: tag) }
                }
            CardTitle(text: item.title)
        }
        .frame(width: width, alignment: .leading)
    }
}

/// Numbered portrait card for top-10 rails ("Most Watched"): 128pt 3:4 poster tucked over an outline numeral.
struct RankedPortraitCard: View {
    let item: ContentItem
    let rank: Int

    private let posterWidth: CGFloat = 128
    private var posterHeight: CGFloat { posterWidth * 4 / 3 }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(alignment: .bottom, spacing: rank >= 10 ? -58 : -34) {
                RankNumeral(rank: rank, height: 168)
                CardArtwork(url: item.portraitImageURL, width: posterWidth, height: posterHeight, fade: (0.85, 0.42))
                    .overlay(alignment: .topTrailing) {
                        // Price and coming-soon tags are hidden on this rail; crowns still show.
                        if AccessTag.resolve(for: item) == .crown { CornerTag(tag: .crown) }
                    }
            }
            Text(item.title)
                .font(Theme.Typography.rankedTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(2)
                .frame(width: posterWidth, alignment: .leading)
                .padding(.top, 10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Number \(rank), \(item.title)")
    }
}

/// Ranked landscape card ("Top 10 today"): 171×96 card overlapping an 82pt numeral by 30pt.
struct RankedLandscapeCard: View {
    let item: ContentItem
    let rank: Int

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(alignment: .bottom, spacing: -30) {
                RankNumeral(rank: rank, height: 82)
                CardArtwork(url: item.landscapeImageURL, width: 171, height: 96, cornerRadius: Theme.Radius.card)
                    .overlay(alignment: .topTrailing) {
                        if AccessTag.resolve(for: item) == .crown { CornerTag(tag: .crown, height: 28) }
                    }
            }
            Text(item.title)
                .font(Theme.Typography.rankedTitleLarge)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(2)
                .frame(width: 171, alignment: .leading)
                .padding(.top, 10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Number \(rank), \(item.title)")
    }
}

/// Promo clip card: 16:9 with a duration pill and a views · likes line.
struct PromoCard: View {
    let item: ContentItem
    var width: CGFloat = 172

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardArtwork(url: item.landscapeImageURL, width: width, height: width * 9 / 16)
                .overlay(alignment: .bottomTrailing) {
                    if let duration = item.formattedDuration {
                        HStack(spacing: 3) {
                            Image(systemName: "play.fill").font(.system(size: 8, weight: .bold))
                            Text(duration).monospacedDigit()
                        }
                        .font(Theme.Typography.badge)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.Palette.scrim.opacity(0.72), in: .capsule)
                        .padding(9)
                    }
                }
            CardTitle(text: item.title)
            if item.viewCount != nil || item.likeCount != nil {
                HStack(spacing: 10) {
                    if let views = item.viewCount {
                        Label(views.formatted(.number.notation(.compactName)), systemImage: "eye")
                    }
                    if let likes = item.likeCount {
                        Label(likes.formatted(.number.notation(.compactName)), systemImage: "hand.thumbsup")
                    }
                }
                .labelStyle(CompactLabelStyle())
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .padding(.top, 4)
            }
        }
        .frame(width: width, alignment: .leading)
    }
}

struct CardTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Typography.cardTitle)
            .foregroundStyle(Theme.Palette.textPrimary)
            .lineLimit(2)
            .lineSpacing(1)
            .padding(.top, 10)
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 11))
            configuration.title
        }
    }
}
