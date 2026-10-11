import SwiftUI

/// Full-width hero carousel fed by `homebanners`. Swipeable, autoplays every 6s, with
/// the prototype's progress dots (the active dot fills yellow over the slide interval).
struct HeroCarouselView: View {
    let banners: [HomeBanner]

    static let slideInterval: Duration = .seconds(6)

    /// Hero height for a feed of the given visible height: the prototype's
    /// clamp(460px, 72vh, 600px), 50pt shorter. Shared with the Home skeleton.
    static func height(inContainer height: CGFloat) -> CGFloat {
        min(max(height * 0.72, 460), 600) - 50
    }

    @State private var currentID: HomeBanner.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currentIndex: Int {
        banners.firstIndex { $0.id == currentID } ?? 0
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(banners) { banner in
                    HeroSlide(banner: banner)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID)
        .containerRelativeFrame(.vertical) { height, _ in Self.height(inContainer: height) }
        .overlay(alignment: .bottom) {
            if banners.count > 1 {
                HeroPageDots(count: banners.count, current: currentIndex, animates: !reduceMotion)
                    .padding(.bottom, 18)
            }
        }
        .task(id: currentID) {
            guard banners.count > 1, !reduceMotion else { return }
            try? await Task.sleep(for: Self.slideInterval)
            guard !Task.isCancelled else { return }
            let next = banners[(currentIndex + 1) % banners.count]
            withAnimation(.easeInOut(duration: 0.6)) { currentID = next.id }
        }
        .onAppear {
            if currentID == nil { currentID = banners.first?.id }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Featured")
    }
}

private struct HeroSlide: View {
    let banner: HomeBanner

    @Environment(\.openRoute) private var openRoute
    @Environment(\.colorScheme) private var colorScheme

    private var openDetail: AppRoute {
        .content(slug: banner.slug, title: banner.title, kind: banner.kind)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Button { openRoute(openDetail) } label: {
                RemoteImage(url: banner.backdropURL, showsFailureIcon: false)
                    .background(Theme.Palette.surface)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            scrims.allowsHitTesting(false)

            content
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.bottom, 44)
        }
        .clipped()
    }

    private var scrims: some View {
        let tone = ScrimTone(colorScheme)
        return ZStack {
            LinearGradient(
                stops: [
                    // Fully opaque at the bottom edge either way, so the hero blends into the page.
                    .init(color: Theme.Palette.background, location: 0.02),
                    .init(color: Theme.Palette.background.opacity(tone.bottomMid), location: 0.20),
                    .init(color: Theme.Palette.background.opacity(tone.bottomHigh), location: 0.46),
                    .init(color: .clear, location: tone.bottomEnd),
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            LinearGradient(
                stops: [
                    .init(color: Theme.Palette.background.opacity(tone.leading), location: 0),
                    .init(color: .clear, location: 0.6),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            // Keep the darker side behind the text, which sits on the right in RTL languages.
            .flipsForRightToLeftLayoutDirection(true)
            // Behind the glass top bar: keeps the wordmark and bar buttons legible on bright art.
            LinearGradient(
                stops: [
                    .init(color: Theme.Palette.background.opacity(tone.top), location: 0),
                    .init(color: .clear, location: 0.25),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if banner.kind != .unknown {
                kindBadge.padding(.bottom, 12)
            }

            titleView

            if let synopsis = banner.synopsis {
                Text(synopsis)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(2)
                    .padding(.top, 14)
            }

            GlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    Button { openRoute(openDetail) } label: {
                        Label("Watch now", systemImage: "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .labelStyle(SpacedLabelStyle(spacing: 9))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                    }
                    .glassButtonStyle(.prominent)
                    .tint(Theme.Palette.brand)

                    Button { openRoute(.signInRequired(prompt: String(localized: "Sign in to add to your watchlist", bundle: .localized))) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .frame(width: 22, height: 22)
                    }
                    .glassButtonStyle()
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Add \(banner.title) to watchlist")
                }
                .controlSize(.large)
                .buttonBorderShape(.capsule)
            }
            .padding(.top, 14)
        }
    }

    private var kindBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.Palette.accent)
                .frame(width: 7, height: 7)
                .shadow(color: Theme.Palette.accent, radius: 4)
            Text(banner.kind.displayName.uppercased())
                .font(.system(size: 11, weight: .bold))
                .letterSpacing(1.5)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassSurface(in: .capsule)
    }

    @ViewBuilder
    private var titleView: some View {
        let textTitle = Text(banner.title)
            .font(.system(size: 37, weight: .bold))
            .letterSpacing(-1.3)
            .foregroundStyle(Theme.Palette.textPrimary)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .shadow(color: Theme.Palette.background.opacity(0.4), radius: 12, y: 4)

        if let titleImageURL = banner.titleImageURL {
            TitleArtwork(url: titleImageURL, fallback: textTitle)
                .accessibilityLabel(banner.title)
        } else {
            textTitle
        }
    }
}

/// The title logo image (max 265×96, anchored bottom-left); falls back to the text title.
private struct TitleArtwork<Fallback: View>: View {
    let url: URL
    let fallback: Fallback

    @State private var failed = false

    var body: some View {
        if failed {
            fallback
        } else {
            TitleImageLoader(url: url, failed: $failed)
                .frame(width: 265, height: 96, alignment: .bottomLeading)
                .shadow(color: .black.opacity(0.65), radius: 10, y: 4)
        }
    }
}

private struct TitleImageLoader: View {
    let url: URL
    @Binding var failed: Bool

    @Environment(\.displayScale) private var displayScale
    @State private var image: DecodedImage?

    var body: some View {
        let key = ImageRequestKey(url: url, pointSize: CGSize(width: 265, height: 96), scale: displayScale)
        Group {
            if let image = image ?? ImageMemoryCache.shared.image(for: key) {
                Image(decorative: image.cgImage, scale: displayScale)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 265, maxHeight: 96, alignment: .bottomLeading)
            } else {
                Color.clear
            }
        }
        .task(id: key) {
            do {
                image = try await ImagePipeline.shared.image(for: key)
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }
}

private struct HeroPageDots: View {
    let count: Int
    let current: Int
    let animates: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                if index == current {
                    ActiveDot(animates: animates).id(current)
                } else {
                    Circle()
                        .fill(Theme.Palette.textPrimary.opacity(0.28))
                        .frame(width: 7, height: 7)
                }
            }
        }
        .frame(maxWidth: 120)
        .clipped()
        .accessibilityElement()
        .accessibilityLabel("Slide \(current + 1) of \(count)")
    }

    private struct ActiveDot: View {
        let animates: Bool
        @State private var progress: CGFloat = 0

        var body: some View {
            Capsule()
                .fill(Theme.Palette.textPrimary.opacity(0.28))
                .frame(width: 20, height: 7)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Palette.accent)
                        .frame(width: 20 * (animates ? progress : 1), height: 7)
                }
                .clipShape(.capsule)
                .onAppear {
                    guard animates else { return }
                    withAnimation(.linear(duration: 6)) { progress = 1 }
                }
        }
    }
}

struct SpacedLabelStyle: LabelStyle {
    var spacing: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
            configuration.title
        }
    }
}

/// Scrim opacities for the hero. They fade the art into the page background, which in light mode
/// is near-white and washes the art out at the dark theme's strengths, so light mode uses less.
private struct ScrimTone {
    let bottomMid: Double
    let bottomHigh: Double
    let bottomEnd: Double
    let leading: Double
    let top: Double

    init(_ colorScheme: ColorScheme) {
        if colorScheme == .dark {
            (bottomMid, bottomHigh, bottomEnd, leading, top) = (0.82, 0.32, 0.68, 0.45, 0.55)
        } else {
            (bottomMid, bottomHigh, bottomEnd, leading, top) = (0.6, 0.12, 0.58, 0.15, 0.2)
        }
    }
}
