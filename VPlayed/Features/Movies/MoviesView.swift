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
            .navigationTitle(Text("Movies"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
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
                title: "Couldn't load movies",
                message: message,
                actionTitle: "Try again",
                action: model.retry
            )
        case .empty:
            HomeMessageView(
                symbol: "film",
                title: "No movies yet",
                message: String(localized: "There's nothing to show yet. Check back soon.", bundle: .localized),
                actionTitle: "Refresh",
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
                        .font(.system(size: 14))
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

    /// "**1,997** films · curated from across the world" with the count bold and bright. Built as
    /// an `AttributedString` because `Text` doesn't apply Markdown to plural (stringsdict) strings.
    private static func filmCount(_ total: Int) -> AttributedString {
        var text = AttributedString(
            localized: "**\(total)** films · curated from across the world",
            bundle: .localized,
            locale: AppLanguage.current.locale
        )
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
                    if let tag = AccessTag.resolve(for: item) { CornerTag(tag: tag) }
                }
            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .padding(.top, 10)
            if let details {
                Text(details)
                    .font(.system(size: 12))
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

/// Placeholder grid while the first page loads.
private struct MoviesLoadingView: View {
    @State private var dimmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RoundedRectangle(cornerRadius: Theme.Radius.badge)
                    .frame(width: 220, height: 14)
                LazyVGrid(columns: MoviesView.columns, alignment: .leading, spacing: 20) {
                    ForEach(0..<8, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: Theme.Radius.control)
                                .aspectRatio(16 / 9, contentMode: .fit)
                            RoundedRectangle(cornerRadius: Theme.Radius.badge)
                                .frame(width: 110, height: 12)
                        }
                    }
                }
            }
            .foregroundStyle(Theme.Palette.raised)
            .padding(.horizontal, Theme.Spacing.gutter)
            .opacity(dimmed ? 0.5 : 1)
        }
        .scrollDisabled(true)
        .scrollIndicators(.hidden)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dimmed = true }
        }
        .accessibilityLabel("Loading movies")
    }
}
