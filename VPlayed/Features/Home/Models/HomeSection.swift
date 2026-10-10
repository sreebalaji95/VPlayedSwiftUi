import Foundation

/// One rail from `mediaview/api/v1/home` (`SocialHomeTabsModel`). Its `data` array is
/// polymorphic; the rail `type` decides how the items decode.
nonisolated struct HomeSection: Decodable, Sendable, Identifiable, Hashable {
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

    private enum CodingKeys: String, CodingKey {
        case id = "_id", title, type, data
        case isTopTen = "is_top_ten"
    }

    init(id: String, title: String, type: Int, isTopTen: Bool = false, content: Content) {
        self.id = id
        self.title = title
        self.type = type
        self.isTopTen = isTopTen
        self.content = content
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = container.lenient(LocalizedText.self, .title)?.value ?? ""
        type = container.lenientInt(.type) ?? 0
        isTopTen = container.lenientBool(.isTopTen) ?? false
        id = container.lenientString(.id) ?? "\(type)-\(title)"

        switch type {
        case 1, 7: content = .titles(container.lossyArray(ContentItem.self, .data))
        case 2, 8: content = .promos(container.lossyArray(ContentItem.self, .data))
        case 3: content = .audio(container.lossyArray(AudioItem.self, .data))
        case 4, 9: content = .channels(container.lossyArray(ChannelItem.self, .data))
        case 5: content = .bulkPlans(container.lossyArray(BulkPlan.self, .data))
        case 6: content = .live(container.lossyArray(LiveItem.self, .data))
        default: content = .unsupported(type: type)
        }
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

/// One page of `mediaview/api/v1/home`.
nonisolated struct HomeFeedPage: Decodable, Sendable {
    let sections: [HomeSection]
    /// The next page number, or nil on the last page.
    let nextPage: Int?

    private enum CodingKeys: String, CodingKey {
        case data, next
    }

    init(sections: [HomeSection], nextPage: Int?) {
        self.sections = sections
        self.nextPage = nextPage
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sections = container.lossyArray(HomeSection.self, .data)
        nextPage = container.lenientInt(.next).flatMap { $0 > 0 ? $0 : nil }
    }
}
