import SwiftUI

/// The mobile Home screen: a Liquid Glass top bar (`HomeToolbar`) over the hero carousel and
/// API-driven rails. The hero runs up behind the bar. The tab bar belongs to `RootView`.
struct HomeView: View {
    let model: SharedHomeViewModel

    @Environment(\.openRoute) private var openRoute

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if let notice = model.notice {
                    ToastView(message: notice)
                        .padding(.bottom, Theme.Spacing.gutter)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.22), value: model.notice)
            .background(Theme.Palette.background.ignoresSafeArea())
            .toolbar { HomeToolbar(openRoute: openRoute) }
        .task { await model.loadIfNeeded() }
        .task(id: model.notice) {
            guard model.notice != nil else { return }
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { model.notice = nil }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .loading:
            HomeLoadingView()
        case .failed(let message):
            HomeMessageView(
                symbol: "wifi.exclamationmark",
                title: L10n.shared(.homeLoadFailed),
                message: message,
                actionTitle: L10n.shared(.commonTryAgain),
                action: model.retry
            )
        case .empty:
            HomeMessageView(
                symbol: "film",
                title: L10n.shared(.homeEmptyTitle),
                message: L10n.shared(.homeEmptyMessage),
                actionTitle: L10n.shared(.commonRefresh),
                action: model.retry
            )
        case .loaded:
            feed
        }
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !model.banners.isEmpty {
                    HeroCarouselView(banners: model.banners)
                }
                ForEach(model.sections) { section in
                    RailSectionView(section: section, model: model)
                }
                if model.hasMorePages {
                    LoadMoreFooter(failed: model.loadMoreFailed, retry: model.loadMoreIfNeeded)
                        // Re-fires while the footer stays visible after each page is appended.
                        .task(id: model.sections.count) {
                            if !model.loadMoreFailed { await model.loadMoreIfNeeded() }
                        }
                }
            }
            .padding(.bottom, Theme.Spacing.railGap)
        }
        .scrollIndicators(.hidden)
        // The hero starts at the top of the screen, behind the glass bar.
        .ignoresSafeArea(edges: .top)
        .softTopScrollEdge()
        .refreshable { await model.refresh() }
    }
}
