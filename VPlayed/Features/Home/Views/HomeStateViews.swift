import SwiftUI

/// Skeleton shown during the first load, laid out like the feed: the hero (behind the glass bar,
/// with its badge, title, synopsis and buttons) and three rails of cards with titles.
struct HomeLoadingView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                ForEach(0..<3, id: \.self) { _ in rail }
            }
            .shimmering()
        }
        .scrollDisabled(true)
        .scrollIndicators(.hidden)
        // Like the feed, the hero starts at the top of the screen, behind the glass bar.
        .ignoresSafeArea(edges: .top)
        .softTopScrollEdge()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading home")
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(Theme.Palette.surface)
            VStack(alignment: .leading, spacing: 0) {
                SkeletonBlock(width: 104, height: 26, cornerRadius: 13)
                SkeletonBlock(width: 230, height: 34, cornerRadius: Theme.Radius.control)
                    .padding(.top, 14)
                SkeletonBlock(height: 12)
                    .padding(.top, 18)
                SkeletonBlock(width: 220, height: 12)
                    .padding(.top, 8)
                HStack(spacing: 10) {
                    Capsule().fill(Theme.Palette.raised).frame(height: 50)
                    Circle().fill(Theme.Palette.raised).frame(width: 50, height: 50)
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.bottom, 44)
        }
        .containerRelativeFrame(.vertical) { height, _ in HeroCarouselView.height(inContainer: height) }
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 14) {
            SkeletonBlock(width: 150, height: 18)
            // The row is wider than a phone; a disabled scroll view takes exactly the offered
            // width, so it can't widen the screen.
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 10) {
                            SkeletonBlock(width: 158, height: 89, cornerRadius: Theme.Radius.control)
                            SkeletonBlock(width: 110, height: 12)
                        }
                    }
                }
            }
            .scrollDisabled(true)
            .scrollIndicators(.hidden)
        }
        .padding(.leading, Theme.Spacing.gutter)
        .padding(.top, 26)
    }
}

/// Centered message with an icon tile and one call to action (empty feed / load failure).
struct HomeMessageView: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: String
    let actionTitle: LocalizedStringKey
    let action: () async -> Void

    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 32))
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(width: 76, height: 76)
                .background(Theme.Palette.raised, in: .rect(cornerRadius: Theme.Radius.popover))
                .padding(.bottom, 20)
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            Button {
                isWorking = true
                Task {
                    await action()
                    isWorking = false
                }
            } label: {
                ZStack {
                    Text(actionTitle).opacity(isWorking ? 0 : 1)
                    if isWorking { ProgressView().tint(Theme.Palette.onPrimary) }
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.Palette.onPrimary)
                .padding(.horizontal, 12)
            }
            .glassButtonStyle(.prominent)
            .tint(Theme.Palette.brand)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(isWorking)
            .padding(.top, 24)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Feed footer while more rails page in, or a retry row if the next page failed.
struct LoadMoreFooter: View {
    let failed: Bool
    let retry: () async -> Void

    var body: some View {
        Group {
            if failed {
                Button {
                    Task { await retry() }
                } label: {
                    Label("Couldn't load more. Tap to retry.", systemImage: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                .glassButtonStyle()
                .buttonBorderShape(.capsule)
                .frame(maxWidth: .infinity)
            } else {
                ProgressView()
                    .tint(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityLabel("Loading more")
            }
        }
        .padding(.vertical, 16)
    }
}

/// Short-lived message pill (prototype toast).
struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.Palette.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(Theme.Palette.raised, in: .capsule)
            .overlay { Capsule().strokeBorder(Theme.Palette.line2, lineWidth: 1) }
            .padding(.horizontal, 24)
    }
}
