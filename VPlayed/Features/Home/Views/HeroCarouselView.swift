import SwiftUI

/// Full-width hero carousel fed by `homebanners`. Swipeable, autoplays every 6s, with
/// the prototype's progress dots (the active dot fills yellow over the slide interval).
struct HeroCarouselView: View {
    let banners: [HomeBanner]

    static let slideInterval: Duration = .seconds(6)

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
        .containerRelativeFrame(.vertical) { height, _ in
            // Prototype: clamp(460px, 72vh, 600px).
            min(max(height * 0.72, 460), 600)
        }
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
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Theme.Palette.background, location: 0.02),
                    .init(color: Theme.Palette.scrim.opacity(0.82), location: 0.20),
                    .init(color: Theme.Palette.scrim.opacity(0.32), location: 0.46),
                    .init(color: .clear, location: 0.68),
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            LinearGradient(
                stops: [
                    .init(color: Theme.Palette.scrim.opacity(0.45), location: 0),
                    .init(color: .clear, location: 0.6),
                ],
                startPoint: .leading,
                endPoint: .trailing
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

            HStack(spacing: 10) {
                Button { openRoute(openDetail) } label: {
                    Label("Watch now", systemImage: "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .labelStyle(SpacedLabelStyle(spacing: 9))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Theme.Palette.brand, in: .rect(cornerRadius: Theme.Radius.control))
                        .shadow(color: Theme.Palette.brand.opacity(0.26), radius: 10, y: 8)
                }
                .buttonStyle(PressableButtonStyle())

                Button { openRoute(.signInRequired(action: "Add to watchlist")) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(.ultraThinMaterial, in: .rect(cornerRadius: Theme.Radius.control))
                        .background(Color.white.opacity(0.12), in: .rect(cornerRadius: Theme.Radius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.control)
                                .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                        }
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Add \(banner.title) to watchlist")
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
                .tracking(1.5)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: .capsule)
        .background(Theme.Palette.scrim.opacity(0.55), in: .capsule)
        .overlay { Capsule().strokeBorder(Theme.Palette.line2, lineWidth: 1) }
    }

    @ViewBuilder
    private var titleView: some View {
        let textTitle = Text(banner.title)
            .font(.system(size: 37, weight: .bold))
            .tracking(-1.3)
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .shadow(color: .black.opacity(0.4), radius: 12, y: 4)

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
                        .fill(Color.white.opacity(0.28))
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
                .fill(Color.white.opacity(0.28))
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
