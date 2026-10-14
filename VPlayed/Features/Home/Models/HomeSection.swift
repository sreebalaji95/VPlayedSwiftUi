import Foundation

/// One rail from `mediaview/api/v1/home` (`SocialHomeTabsModel`). Its `data` array is
/// polymorphic; the rail `type` decides how the items decode.
nonisolated struct HomeSection: Sendable, Identifiable, Hashable {
    nonisolated enum Content: Hashable, Sendable {
        case titles([ContentItem])
        case promos([ContentItem])
        case audio([AudioItem])
        case channels([ChannelItem])
        case bulkPlans([BulkPlan])
        case live([LiveItem])
        case unsupported(type: Int)
    }

    /// The prototype card style a rail renders with.
    nonisolated enum Layout: Hashable, Sendable {
        case landscape, portrait, rankedLandscape, rankedPortrait
        case promos, audio, channels, bulkPlans, live
    }

    let id: String
    let title: String
    let type: Int
    let isTopTen: Bool
    let content: Content

    init(id: String, title: String, type: Int, isTopTen: Bool = false, content: Content) {
        self.id = id
        self.title = title
        self.type = type
        self.isTopTen = isTopTen
        self.content = content
    }

    var itemCount: Int {
        switch content {
        case .titles(let items), .promos(let items): items.count
        case .audio(let items): items.count
        case .channels(let items): items.count
        case .bulkPlans(let items): items.count
        case .live(let items): items.count
        case .unsupported: 0
        }
    }

    /// Unknown rail types and empty rails are not shown.
    var isDisplayable: Bool { itemCount > 0 }

    var layout: Layout? {
        switch content {
        case .titles(let items):
            // The UIKit app renders micro-series (sho_type 6) as vertical cards.
            let portrait = items.allSatisfy(\.isMicroSeries)
            if isTopTen { return portrait ? .rankedPortrait : .rankedLandscape }
            return portrait ? .portrait : .landscape
        case .promos: return .promos
        case .audio: return .audio
        case .channels: return .channels
        case .bulkPlans: return .bulkPlans
        case .live: return .live
        case .unsupported: return nil
        }
    }

    /// Top-10 rails are complete as shown, so the prototype gives them no "view all".
    var showsViewAll: Bool { !isTopTen }

    func kind(for item: ContentItem) -> ContentKind {
        switch content {
        case .promos: .promo
        default: ContentKind(shoType: item.shoType)
        }
    }
}
