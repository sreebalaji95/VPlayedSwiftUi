#if canImport(Shared)
import Foundation
import Observation
// Kotlin classes are not Sendable; they are only used on the main thread here.
@preconcurrency import Shared

/// The Home model on iOS and macOS: the Kotlin shared `HomeFeedController` (also behind AndroidJP's
/// Home) runs the feed — parallel first load, paging with de-duplication, skipping pages with
/// nothing new (decision D9), refresh that keeps content on failure, and channel follow. This class
/// mirrors its state into the structs the Home views draw (`SharedHomeMapping`) and turns its
/// events into notices. Same API as `HomeViewModel`, which stays for visionOS.
@Observable
final class SharedHomeViewModel {
    private(set) var phase: HomeViewModel.Phase = .idle
    private(set) var banners: [HomeBanner] = []
    private(set) var sections: [HomeSection] = []
    private(set) var isLoadingMore = false
    private(set) var loadMoreFailed = false
    private(set) var hasMorePages = false
    /// A non-blocking message to surface as a toast (e.g. a refresh failed but older content is still shown).
    var notice: String?

    private var updatingChannels: Set<String> = []

    func isFollowing(_ channel: ChannelItem) -> Bool { channel.isFollowed }
    func followerCount(of channel: ChannelItem) -> Int? { channel.followCount }
    func isUpdatingFollow(_ channel: ChannelItem) -> Bool { updatingChannels.contains(channel.id) }

    @ObservationIgnored private let controller: HomeFeedController
    /// Awaited once before the first load (`RootView` waits for the geo token here).
    @ObservationIgnored private let prepare: () async -> Void
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var state: HomeFeedState
    @ObservationIgnored private var waiters: [Waiter] = []
    @ObservationIgnored private let watchers = KotlinSubscriptions()

    /// Resumes an `async` call once the shared state satisfies its condition.
    private struct Waiter {
        let isSatisfied: (HomeFeedState) -> Bool
        let continuation: CheckedContinuation<Void, Never>
    }

    init(graph: SharedGraph = SharedLayer.graph, prepare: @escaping () async -> Void = {}) {
        self.prepare = prepare
        let controller = graph.homeFeedController()
        self.controller = controller
        state = controller.currentState
        watchers.add(controller.close)
        // Reads the controller's current state rather than the delivered one: a delivery queued
        // before an intent's synchronous update would otherwise briefly undo it.
        watchers.add(controller.watchState { [weak self] _ in
            MainActor.assumeIsolated { self?.syncState() }
        }.close)
        watchers.add(controller.watchEffects { [weak self] effect in
            MainActor.assumeIsolated { self?.handle(effect) }
        }.close)
    }

    /// Loads the feed the first time Home appears; later appearances keep the existing content.
    func loadIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true
        phase = .loading
        await prepare()
        controller.load()
        syncState()
        await wait { !$0.isLoading }
    }

    func retry() async {
        hasStarted = true
        controller.retry()
        syncState()
        await wait { !$0.isLoading }
    }

    /// Pull-to-refresh, a sign-in or a language change: reloads banners and the first page,
    /// keeping current content on failure. Before the first load it does nothing.
    func refresh() async {
        guard hasStarted else { return }
        controller.refresh()
        syncState()
        await wait { !$0.isRefreshing && !$0.isLoading }
    }

    /// Fetches the next page when the end of the feed becomes visible (or retries a failed one).
    func loadMoreIfNeeded() async {
        guard phase == .loaded else { return }
        controller.loadNextPage()
        syncState()
        await wait { !($0.paging is PagingStatusLoading) }
    }

    /// Follows or unfollows a channel, then shows the new state. Like UIKit it waits for the
    /// server, so a failed request leaves the card as it was and shows a toast.
    func setFollowing(_ follow: Bool, channel: ChannelItem) async {
        guard channel.slug != nil else { return }
        controller.setFollowing(channelId: channel.id, follow: follow)
        syncState()
        await wait { !$0.updatingChannelIds.contains(channel.id) }
    }

    // MARK: Shared state and effects

    private func syncState() {
        let state = controller.currentState
        self.state = state
        let newBanners = state.banners.map(SharedHomeMapping.banner)
        if newBanners != banners { banners = newBanners }
        let newSections = state.sections.map(SharedHomeMapping.section).filter(\.isDisplayable)
        if newSections != sections { sections = newSections }
        isLoadingMore = state.paging is PagingStatusLoading
        loadMoreFailed = state.paging is PagingStatusFailed
        hasMorePages = state.nextPage != nil
        updatingChannels = state.updatingChannelIds
        phase = derivedPhase(state)
        resumeWaiters()
    }

    private func derivedPhase(_ state: HomeFeedState) -> HomeViewModel.Phase {
        if !hasStarted { return .idle }
        if let error = state.error { return .failed(APIError(error).userMessage) }
        if state.isLoading { return .loading }
        if state.isEmpty { return .empty }
        return .loaded
    }

    private func handle(_ effect: HomeFeedEffect) {
        switch effect {
        case let failed as HomeFeedEffectRefreshFailed:
            notice = APIError(failed.error).userMessage
        case let changed as HomeFeedEffectFollowChanged:
            notice = changed.isFollowed
                ? String(localized: "You have started following this channel", bundle: .localized)
                : String(localized: "You have unfollowed this channel", bundle: .localized)
        case let failed as HomeFeedEffectFollowFailed:
            notice = APIError(failed.error).userMessage
        default:
            break
        }
    }

    private func wait(until isSatisfied: @escaping (HomeFeedState) -> Bool) async {
        if isSatisfied(state) { return }
        await withCheckedContinuation { continuation in
            waiters.append(Waiter(isSatisfied: isSatisfied, continuation: continuation))
        }
    }

    private func resumeWaiters() {
        var ready: [Waiter] = []
        var pending: [Waiter] = []
        for waiter in waiters {
            if waiter.isSatisfied(state) { ready.append(waiter) } else { pending.append(waiter) }
        }
        guard !ready.isEmpty else { return }
        waiters = pending
        ready.forEach { $0.continuation.resume() }
    }
}
#endif
