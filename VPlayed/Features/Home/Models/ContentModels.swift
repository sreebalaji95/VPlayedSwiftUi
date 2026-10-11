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
        case .video: String(localized: "Video", bundle: .localized)
        case .series: String(localized: "Series", bundle: .localized)
        case .microSeries: String(localized: "Micro series", bundle: .localized)
        case .promo: String(localized: "Promo", bundle: .localized)
        case .audio: String(localized: "Audio", bundle: .localized)
        case .live: String(localized: "Live", bundle: .localized)
        case .unknown: String(localized: "Title", bundle: .localized)
        }
    }
}

nonisolated struct Genre: Decodable, Sendable, Hashable {
    let title: String

    private enum CodingKeys: String, CodingKey { case title }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let title = container.lenientString(.title) else {
            throw DecodingError.dataCorruptedError(forKey: .title, in: container, debugDescription: "Missing genre title")
        }
        self.title = title
    }
}

nonisolated struct Price: Decodable, Sendable, Hashable {
    let currency: String?
    let currencySign: String?
    let currencyType: Int?
    let amount: Double?
    let discountedPercentage: Double?

    private enum CodingKeys: String, CodingKey {
        case currency, amount
        case currencySign = "currency_sign"
        case currencyType = "currency_type"
        case discountedPercentage = "discounted_percentage"
    }

    init(currency: String?, currencySign: String? = nil, currencyType: Int?, amount: Double?, discountedPercentage: Double? = nil) {
        self.currency = currency
        self.currencySign = currencySign
        self.currencyType = currencyType
        self.amount = amount
        self.discountedPercentage = discountedPercentage
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currency = container.lenientString(.currency)
        currencySign = container.lenientString(.currencySign)
        currencyType = container.lenientInt(.currencyType)
        amount = container.lenientDouble(.amount)
        discountedPercentage = container.lenientDouble(.discountedPercentage)
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

    /// The entry matching the preferred currency type, else the first (`checkCurrencyIndex`).
    static func preferred(in prices: [Price], currencyType: Int?) -> Price? {
        prices.first { $0.currencyType == (currencyType ?? 1) } ?? prices.first
    }
}

/// A video, series, micro-series or promo card (`TrendingShos` / `TrendingPromos`).
nonisolated struct ContentItem: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let title: String
    let slug: String?
    let shoType: Int?
    let thumbnailImage: String?
    let thumbnailImages: ImageSet?
    let newThumbnailImages: ImageSet?
    let posterImage: String?
    let mobilePosterImage: String?
    let videoDuration: Double?
    let monetization: Int?
    let prices: [Price]
    let defaultCurrencyType: Int?
    let isSubscription: Bool?
    let isUserSubscribed: Bool?
    let isScheduled: Bool?
    let viewCount: Int?
    let likeCount: Int?
    /// `default_genre.title`, e.g. "Drama" (catalogue items such as Movies).
    let genre: String?

    private enum CodingKeys: String, CodingKey {
        case id = "_id", title, slug, monetization, prices, scheduled
        case shoType = "sho_type"
        case thumbnailImage = "thumbnail_image"
        case thumbnailImages = "thumbnail_images"
        case newThumbnailImages = "new_thumbnail_images"
        case posterImage = "poster_image"
        case mobilePosterImage = "mobile_poster_image"
        case videoDuration = "video_duration"
        case defaultCurrencyType = "default_currency_type"
        case isSubscription = "is_subscription"
        case isUserSubscribed = "is_user_subscribed"
        case viewCount = "view_count"
        case likeCount = "guds_count"
        case defaultGenre = "default_genre"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = container.lenientString(.id) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Missing _id")
        }
        self.id = id
        title = container.lenientString(.title) ?? ""
        slug = container.lenientString(.slug)
        shoType = container.lenientInt(.shoType)
        thumbnailImage = container.lenientString(.thumbnailImage)
        thumbnailImages = container.lenient(ImageSet.self, .thumbnailImages)
        newThumbnailImages = container.lenient(ImageSet.self, .newThumbnailImages)
        posterImage = container.lenientString(.posterImage)
        mobilePosterImage = container.lenientString(.mobilePosterImage)
        videoDuration = container.lenientDouble(.videoDuration)
        monetization = container.lenientInt(.monetization)
        prices = container.lossyArray(Price.self, .prices)
        defaultCurrencyType = container.lenientInt(.defaultCurrencyType)
        isSubscription = container.lenientBool(.isSubscription)
        isUserSubscribed = container.lenientBool(.isUserSubscribed)
        isScheduled = container.lenientBool(.scheduled)
        viewCount = container.lenientInt(.viewCount)
        likeCount = container.lenientInt(.likeCount)
        genre = container.lenient(Genre.self, .defaultGenre)?.title
    }

    var isMicroSeries: Bool { shoType == 6 }

    /// 16:9 artwork. Micro-series `new_thumbnail_images` are portrait, so they use the poster instead.
    var landscapeImageURL: URL? {
        let path = isMicroSeries
            ? mobilePosterImage ?? posterImage ?? newThumbnailImages?.path(preferring: [.tl, .tp])
            : newThumbnailImages?.path(preferring: [.tc, .tl, .to, .tv, .tp, .tm, .mobile, .web]) ?? posterImage ?? thumbnailImage
        return ImageURL.resolve(path)
    }

    /// Portrait artwork: micro-series 3:4 `new_thumbnail_images` (`tp` is the largest; their `tc` is
    /// tiny), otherwise the 2:3 `thumbnail_images`.
    var portraitImageURL: URL? {
        let path = isMicroSeries
            ? newThumbnailImages?.path(preferring: [.tp, .to, .tl, .tm, .tc, .tv]) ?? thumbnailImages?.path(preferring: [.web, .key, .mobile]) ?? thumbnailImage
            : thumbnailImages?.path(preferring: [.web, .key, .mobile]) ?? thumbnailImage ?? newThumbnailImages?.path(preferring: [.tc, .tv, .tp])
        return ImageURL.resolve(path)
    }

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

nonisolated struct AudioItem: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let title: String
    let slug: String?
    let artistName: String?
    let imageURL: URL?

    private enum CodingKeys: String, CodingKey {
        case id = "_id", title, slug
        case artistName = "artist_name"
        case thumbnailImage = "thumbnail_image"
        case thumbnailImages = "thumbnail_images"
        case newThumbnailImages = "new_thumbnail_images"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = container.lenientString(.id) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Missing _id")
        }
        self.id = id
        title = container.lenientString(.title) ?? ""
        slug = container.lenientString(.slug)
        artistName = container.lenientString(.artistName)
        let path = container.lenient(ImageSet.self, .thumbnailImages)?.path(preferring: [.web, .key, .mobile])
            ?? container.lenientString(.thumbnailImage)
            ?? container.lenient(ImageSet.self, .newThumbnailImages)?.path(preferring: [.web, .mobile, .tm, .tp])
        imageURL = ImageURL.resolve(path)
    }
}

/// A studio / channel (`TrendingStudios`), rail types 4 and 9.
nonisolated struct ChannelItem: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let slug: String?
    let logoURL: URL?
    let followCount: Int?

    private enum CodingKeys: String, CodingKey {
        case id = "_id", name, slug
        case channelName = "channel_name"
        case profilePicture = "profile_picture"
        case channelLogo = "channel_logo"
        case followCount = "follow_count"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = container.lenientString(.id) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Missing _id")
        }
        self.id = id
        name = container.lenientString(.name) ?? container.lenientString(.channelName) ?? ""
        slug = container.lenientString(.slug)
        logoURL = ImageURL.resolve(container.lenientString(.profilePicture) ?? container.lenientString(.channelLogo))
        followCount = container.lenientInt(.followCount)
    }
}

/// A bulk-purchase bundle (rail type 5).
nonisolated struct BulkPlan: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let slug: String?
    let label: String?
    let summary: String?
    let prices: [Price]
    let accentHex: String?

    private enum CodingKeys: String, CodingKey {
        case id = "_id", name, slug, label, description, prices
        case backgroundColor = "background_color"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = container.lenientString(.id) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Missing _id")
        }
        self.id = id
        name = container.lenientString(.name) ?? ""
        slug = container.lenientString(.slug)
        label = container.lenient(LocalizedText.self, .label)?.value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        summary = container.lenientString(.description)
        prices = container.lossyArray(Price.self, .prices)
        accentHex = container.lenientString(.backgroundColor)
    }

    var price: Price? { Price.preferred(in: prices, currencyType: 1) }
}

/// A live stream (rail type 6). `publish_status`: 0 soon, 1 upcoming, 2 yet to connect, 3 live, 4 hidden.
nonisolated struct LiveItem: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let title: String
    let slug: String?
    let channelName: String?
    let publishStatus: Int?
    let startsAt: Date?
    let imageURL: URL?

    private enum CodingKeys: String, CodingKey {
        case id = "_id", title, slug
        case studioName = "studio_name"
        case publishStatus = "publish_status"
        case streamStartTime = "stream_start_time"
        case scheduledAt = "scheduled_at"
        case newThumbnailImages = "new_thumbnail_images"
        case thumbnailImage = "thumbnail_image"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = container.lenientString(.id) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Missing _id")
        }
        self.id = id
        title = container.lenientString(.title) ?? ""
        slug = container.lenientString(.slug)
        channelName = container.lenientString(.studioName)
        publishStatus = container.lenientInt(.publishStatus)
        startsAt = (container.lenientString(.streamStartTime) ?? container.lenientString(.scheduledAt)).flatMap(Self.parseDate)
        imageURL = ImageURL.resolve(
            container.lenient(ImageSet.self, .newThumbnailImages)?.path(preferring: [.tc, .tl, .to, .tv, .tp, .tm])
                ?? container.lenientString(.thumbnailImage)
        )
    }

    var isLive: Bool { publishStatus == 3 }

    private static func parseDate(_ value: String) -> Date? {
        (try? Date(value, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)))
            ?? (try? Date(value, strategy: .iso8601))
    }
}

extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
