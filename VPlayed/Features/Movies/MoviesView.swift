import SwiftUI

/// The Movies catalogue (prototype page "VPlayed Movies"): a large title, the film count, and a
/// paged grid of 16:9 cards. The prototype's Genre / Language / Access / Sort chips are left out
/// until the API can filter (`sho-details/media/1` takes only `page` and `limit`).
struct MoviesView: View {
    @State private var model = MoviesViewModel()
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
            .navigationTitle(Text(L10n.shared(.navMovies)))
            .navigationBarTitleDisplayMode(.large)
            .task { await model.loadIfNeeded() }
            .task(id: model.notice) {
                guard model.notice != nil else { return }
                try? await Task.sleep(for: .seconds(2.5))
                if !Task.isCancelled { model.notice = nil }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .loading:
            MoviesLoadingView()
        case .failed(let message):
            HomeMessageView(
                symbol: "wifi.exclamationmark",
                title: L10n.shared(.moviesLoadFailed),
                message: message,
                actionTitle: L10n.shared(.commonTryAgain),
                action: model.retry
            )
        case .empty:
            HomeMessageView(
                symbol: "film",
                title: L10n.shared(.moviesEmpty),
                message: L10n.shared(.homeEmptyMessage),
                actionTitle: L10n.shared(.commonRefresh),
                action: model.retry
            )
        case .loaded:
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let total = model.total {
                    Text(Self.filmCount(total))
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 20) {
                    ForEach(model.movies) { movie in
                        Button {
                            openRoute(.content(slug: movie.slug, title: movie.title, kind: .video))
                        } label: {
                            MovieCard(item: movie)
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
                if model.hasMorePages {
                    LoadMoreFooter(failed: model.loadMoreFailed, retry: model.loadMoreIfNeeded)
                        // Re-fires while the footer stays visible after each page is appended.
                        .task(id: model.movies.count) {
                            if !model.loadMoreFailed { await model.loadMoreIfNeeded() }
                        }
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.refresh() }
    }

    /// "**1,997** films · curated from across the world" with the count bold and bright: the
    /// catalog's plural string is Markdown.
    private static func filmCount(_ total: Int) -> AttributedString {
        var text = L10n.shared.markdownPlural(.moviesCount, count: total, L10n.shared.number(total))
        for run in text.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            text[run.range].foregroundColor = Theme.Palette.textPrimary
        }
        return text
    }

    /// Two columns on iPhone, more as the width grows (four on iPad, as in the prototype).
    static let columns = [GridItem(.adaptive(minimum: 160), spacing: 12, alignment: .top)]
}

/// Grid card: 16:9 artwork with the access tag, then the title and "Genre • duration".
private struct MovieCard: View {
    let item: ContentItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardArtwork(url: item.landscapeImageURL, aspectRatio: 16 / 9)
                .overlay(alignment: .topTrailing) {
                    if let tag = item.accessTag { CornerTag(tag: tag) }
                }
            Text(item.title)
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .padding(.top, 10)
            if let details {
                Text(details)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var details: String? {
        let parts = [item.genre, item.formattedDuration].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}

/// Skeleton while the first page loads, laid out like the grid: the subtitle line, then cards
/// with their title and genre / duration lines.
private struct MoviesLoadingView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SkeletonBlock(width: 240, height: 14)
                LazyVGrid(columns: MoviesView.columns, alignment: .leading, spacing: 20) {
                    ForEach(0..<10, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 0) {
                            RoundedRectangle(cornerRadius: Theme.Radius.control)
                                .fill(Theme.Palette.raised)
                                .aspectRatio(16 / 9, contentMode: .fit)
                            SkeletonBlock(width: 120, height: 13)
                                .padding(.top, 11)
                            SkeletonBlock(width: 80, height: 10)
                                .padding(.top, 7)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .shimmering()
        }
        .scrollDisabled(true)
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.shared(.moviesLoading))
    }
}
