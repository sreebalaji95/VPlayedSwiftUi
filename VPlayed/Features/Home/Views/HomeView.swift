import SwiftUI

/// The mobile Home screen: header, hero carousel and API-driven rails. The tab bar belongs to
/// `RootView`.
struct HomeView: View {
    let model: HomeViewModel

    var body: some View {
        VStack(spacing: 0) {
            HomeHeaderView()
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
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .task { await model.loadIfNeeded() }
        .task(id: model.notice) {
            guard model.notice != nil else { return }
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { model.notice = nil }
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .loading:
            HomeLoadingView()
        case .failed(let message):
            HomeMessageView(
                symbol: "wifi.exclamationmark",
                title: "Couldn't load Home",
                message: message,
                actionTitle: "Try again",
                action: model.retry
            )
        case .empty:
            HomeMessageView(
                symbol: "film",
                title: "Your home feed is empty",
                message: "There's nothing to show yet. Check back soon.",
                actionTitle: "Refresh",
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
                    RailSectionView(section: section)
                }
                if model.hasMorePages {
                    LoadMoreFooter(failed: model.loadMoreFailed, retry: model.loadMoreIfNeeded)
                        // Re-fires while the footer stays visible after each page is appended.
                        .task(id: model.sections.count) {
                            if !model.loadMoreFailed { await model.loadMoreIfNeeded() }
                        }
                }
            }
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.refresh() }
    }
}
