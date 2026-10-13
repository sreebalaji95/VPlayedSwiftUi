import Foundation
import Observation

/// A channel's follow state after the user changed it.
struct ChannelFollowState: Equatable {
    var isFollowed: Bool
    var followers: Int
}

/// Drives the Home feed: hero banners plus paged rails.
@Observable
final class HomeViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var banners: [HomeBanner] = []
    private(set) var sections: [HomeSection] = []
    private(set) var isLoadingMore = false
    private(set) var loadMoreFailed = false
    /// A non-blocking error to surface as a toast (e.g. a refresh failed but older content is still shown).
    var notice: String?

    /// What the user changed on a channel since the feed loaded; the feed's own value applies until then.
    private(set) var followStates: [String: ChannelFollowState] = [:]
    private var updatingChannels: Set<String> = []

    var hasMorePages: Bool { nextPage != nil }

    func isFollowing(_ channel: ChannelItem) -> Bool { followStates[channel.id]?.isFollowed ?? channel.isFollowed }
    func followerCount(of channel: ChannelItem) -> Int? { followStates[channel.id]?.followers ?? channel.followCount }
    func isUpdatingFollow(_ channel: ChannelItem) -> Bool { updatingChannels.contains(channel.id) }

    /// Follows or unfollows a channel, then shows the new state. Like UIKit it waits for the
    /// server, so a failed request leaves the card as it was and shows a toast.
    func setFollowing(_ follow: Bool, channel: ChannelItem) async {
        guard let slug = channel.slug, updatingChannels.insert(channel.id).inserted else { return }
        defer { updatingChannels.remove(channel.id) }
        do {
            try await service.setFollowing(follow, channelSlug: slug)
            let current = followerCount(of: channel) ?? 0
            followStates[channel.id] = ChannelFollowState(isFollowed: follow, followers: max(0, current + (follow ? 1 : -1)))
            notice = follow
                ? String(localized: "You have started following this channel", bundle: .localized)
                : String(localized: "You have unfollowed this channel", bundle: .localized)
        } catch is CancellationError {
            return
        } catch {
            notice = (error as? APIError)?.userMessage ?? APIError.network(code: 0).userMessage
        }
    }

    private let service: any HomeServicing
    /// Awaited once before the first load (`RootView` waits for the geo token here).
    private let prepare: () async -> Void
    private var nextPage: Int?
    /// Bumped on every full reload so responses from superseded loads are discarded.
    private var generation = 0

    /// Caps how many consecutive pages are fetched when a page yields no displayable rails.
    private let maxEmptyPagesInARow = 5

    init(service: any HomeServicing = HomeService(), prepare: @escaping () async -> Void = {}) {
        self.service = service
        self.prepare = prepare
    }

    /// Loads the feed the first time Home appears; later appearances keep the existing content.
    func loadIfNeeded() async {
        guard phase == .idle else { return }
        phase = .loading
        await prepare()
        await reload(isInitial: true)
    }

    func retry() async {
        phase = .loading
        await reload(isInitial: true)
    }

    /// Pull-to-refresh: reloads banners and the first page, keeping current content on failure.
    func refresh() async {
        await reload(isInitial: phase != .loaded)
    }

    /// Fetches the next page when the end of the feed becomes visible.
    func loadMoreIfNeeded() async {
        guard phase == .loaded, !isLoadingMore, let page = nextPage else { return }
        isLoadingMore = true
        loadMoreFailed = false
        let token = generation
        defer { if token == generation { isLoadingMore = false } }

        var pageToLoad: Int? = page
        var emptyPages = 0
        while let current = pageToLoad {
            let result = await capture { try await self.service.homePage(current) }
            guard token == generation else { return }
            switch result {
            case .success(let feedPage):
                let added = appendSections(feedPage.sections)
                // Guard against a server that repeats or rewinds the page number.
                nextPage = feedPage.nextPage.flatMap { $0 > current ? $0 : nil }
                emptyPages = added == 0 ? emptyPages + 1 : 0
                // A page with nothing displayable would leave the trigger offscreen, so keep going.
                pageToLoad = added == 0 && emptyPages < maxEmptyPagesInARow ? nextPage : nil
            case .failure(let error):
                if !(error is CancellationError) { loadMoreFailed = true }
                return
            }
        }
    }

    private func reload(isInitial: Bool) async {
        generation += 1
        let token = generation
        isLoadingMore = false
        loadMoreFailed = false

        async let bannerResult = capture { try await self.service.banners() }
        async let pageResult = capture { try await self.service.homePage(1) }
        let (bannersOutcome, pageOutcome) = await (bannerResult, pageResult)
        guard token == generation else { return }

        switch pageOutcome {
        case .success(let page):
            if case .success(let newBanners) = bannersOutcome {
                banners = newBanners
            } else if isInitial {
                banners = []
            }
            sections = []
            followStates = [:]
            _ = appendSections(page.sections)
            nextPage = page.nextPage
            phase = sections.isEmpty && banners.isEmpty && nextPage == nil ? .empty : .loaded
            if phase == .loaded, sections.isEmpty, nextPage != nil {
                // The first page had nothing displayable; pull the next ones right away.
                await loadMoreIfNeeded()
            }
        case .failure(let error) where error is CancellationError:
            // The view went away mid-load; start over next time it appears.
            if isInitial { phase = .idle }
        case .failure(let error):
            let message = (error as? APIError)?.userMessage ?? APIError.network(code: 0).userMessage
            if isInitial {
                phase = .failed(message)
            } else {
                notice = message
            }
        }
    }

    /// Appends displayable sections not already shown; returns how many were added.
    private func appendSections(_ newSections: [HomeSection]) -> Int {
        let existing = Set(sections.map(\.id))
        let fresh = newSections.filter { $0.isDisplayable && !existing.contains($0.id) }
        sections.append(contentsOf: fresh)
        return fresh.count
    }

    private func capture<T: Sendable>(_ operation: () async throws -> T) async -> Result<T, any Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }
}
