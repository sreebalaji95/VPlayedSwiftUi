import Foundation

/// What a card opens. Derived from the rail `type` and the item's `sho_type`
/// (1 video, 2 series, 6 micro-series), following `AllTitleCardTableViewCell` routing.
nonisolated enum ContentKind: String, Hashable, Sendable {
    case video, series, microSeries, promo, audio, live, unknown

    init(shoType: Int?) {
        switch shoType {
        case 1: self = .video
        case 2: self = .series
        case 6: self = .microSeries
        default: self = .unknown
        }
    }

    var displayName: String {
        switch self {
        case .video: L10n.string(.contentKindVideo)
        case .series: L10n.string(.contentKindSeries)
        case .microSeries: L10n.string(.contentKindMicroSeries)
        case .promo: L10n.string(.contentKindPromo)
        case .audio: L10n.string(.contentKindAudio)
        case .live: L10n.string(.contentKindLive)
        case .unknown: L10n.string(.commonTitle)
        }
    }
}

nonisolated struct Price: Sendable, Hashable {
    let currency: String?
    let currencySign: String?
    let currencyType: Int?
    let amount: Double?
    let discountedPercentage: Double?

    init(currency: String?, currencySign: String? = nil, currencyType: Int?, amount: Double?, discountedPercentage: Double? = nil) {
        self.currency = currency
        self.currencySign = currencySign
        self.currencyType = currencyType
        self.amount = amount
        self.discountedPercentage = discountedPercentage
    }

    /// e.g. `₹33`, `$12.50`. Whole amounts drop the decimals, as in the UIKit app.
    var formatted: String? {
        guard let amount else { return nil }
        let number = amount.rounded() == amount
            ? String(Int(amount))
            : String(format: "%.2f", amount)
        return "\(symbol)\(number)"
    }

    private var symbol: String {
        if let currencySign { return currencySign }
        guard let currency else { return "" }
        return Self.symbolsByCurrency[currency.uppercased()] ?? currency + " "
    }

    /// ISO currency code → shortest local symbol (e.g. INR → ₹), built once.
    private static let symbolsByCurrency: [String: String] = {
        var symbols: [String: String] = [:]
        for identifier in Locale.availableIdentifiers {
            let locale = Locale(identifier: identifier)
            guard let code = locale.currency?.identifier, let symbol = locale.currencySymbol else { continue }
            if let existing = symbols[code], existing.count <= symbol.count { continue }
            symbols[code] = symbol
        }
        return symbols
    }()

}

/// A video, series, micro-series or promo card (`TrendingShos` / `TrendingPromos`). Image URLs and the
/// corner tag are decided when the item is read, here or by the shared layer (`SharedHomeMapping`).
nonisolated struct ContentItem: Sendable, Identifiable, Hashable {
    let id: String
    let title: String
    let slug: String?
    let shoType: Int?
    /// 16:9 artwork. Micro-series `new_thumbnail_images` are portrait, so they use the poster instead.
    let landscapeImageURL: URL?
    /// Portrait artwork: micro-series 3:4 `new_thumbnail_images` (`tp` is the largest; their `tc` is
    /// tiny), otherwise the 2:3 `thumbnail_images`.
    let portraitImageURL: URL?
    let videoDuration: Double?
    /// The card's corner tag, decided by the shared layer (decision D14).
    let accessTag: AccessTag?
    let viewCount: Int?
    let likeCount: Int?
    /// `default_genre.title`, e.g. "Drama" (catalogue items such as Movies).
    let genre: String?

    init(
        id: String,
        title: String,
        slug: String? = nil,
        shoType: Int? = nil,
        landscapeImageURL: URL? = nil,
        portraitImageURL: URL? = nil,
        videoDuration: Double? = nil,
        accessTag: AccessTag? = nil,
        viewCount: Int? = nil,
        likeCount: Int? = nil,
        genre: String? = nil
    ) {
        self.id = id
        self.title = title
        self.slug = slug
        self.shoType = shoType
        self.landscapeImageURL = landscapeImageURL
        self.portraitImageURL = portraitImageURL
        self.videoDuration = videoDuration
        self.accessTag = accessTag
        self.viewCount = viewCount
        self.likeCount = likeCount
        self.genre = genre
    }

    var isMicroSeries: Bool { shoType == 6 }

    /// e.g. `3m 26s`, `1h 12m`.
    var formattedDuration: String? {
        guard let seconds = videoDuration, seconds >= 1 else { return nil }
        let total = Int(seconds.rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(secs)s" }
        return "\(secs)s"
    }
}

nonisolated struct AudioItem: Sendable, Identifiable, Hashable {
    let id: String
    let title: String
    let slug: String?
    let artistName: String?
    let imageURL: URL?

    init(id: String, title: String, slug: String? = nil, artistName: String? = nil, imageURL: URL? = nil) {
        self.id = id
        self.title = title
        self.slug = slug
        self.artistName = artistName
        self.imageURL = imageURL
    }

}

/// A studio / channel (`TrendingStudios`), rail types 4 and 9.
nonisolated struct ChannelItem: Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let slug: String?
    let logoURL: URL?
    let followCount: Int?
    /// The channel's brand colour (`bg_card_color`), a hex string such as `#A0E3FF`.
    let brandHex: String?
    /// Whether the signed-in account follows the channel (`is_followed`; false for guests).
    let isFollowed: Bool

    init(id: String, name: String, slug: String? = nil, logoURL: URL? = nil, followCount: Int? = nil, brandHex: String? = nil, isFollowed: Bool = false) {
        self.id = id
        self.name = name
        self.slug = slug
        self.logoURL = logoURL
        self.followCount = followCount
        self.brandHex = brandHex
        self.isFollowed = isFollowed
    }

}

/// A bulk-purchase bundle (rail type 5).
nonisolated struct BulkPlan: Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let slug: String?
    let label: String?
    let summary: String?
    /// The full price in rupees (`currency_type` 1), as the UIKit card shows it.
    let price: Price?
    let accentHex: String?

    init(id: String, name: String, slug: String? = nil, label: String? = nil, summary: String? = nil, price: Price? = nil, accentHex: String? = nil) {
        self.id = id
        self.name = name
        self.slug = slug
        self.label = label
        self.summary = summary
        self.price = price
        self.accentHex = accentHex
    }

}

/// A live stream (rail type 6). `publish_status`: 0 soon, 1 upcoming, 2 yet to connect, 3 live, 4 hidden.
nonisolated struct LiveItem: Sendable, Identifiable, Hashable {
    let id: String
    let title: String
    let slug: String?
    let channelName: String?
    /// `publish_status` 3.
    let isLive: Bool
    let startsAt: Date?
    let imageURL: URL?

    init(id: String, title: String, slug: String? = nil, channelName: String? = nil, isLive: Bool, startsAt: Date? = nil, imageURL: URL? = nil) {
        self.id = id
        self.title = title
        self.slug = slug
        self.channelName = channelName
        self.isLive = isLive
        self.startsAt = startsAt
        self.imageURL = imageURL
    }

    private static func parseDate(_ value: String) -> Date? {
        (try? Date(value, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)))
            ?? (try? Date(value, strategy: .iso8601))
    }
}

extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
