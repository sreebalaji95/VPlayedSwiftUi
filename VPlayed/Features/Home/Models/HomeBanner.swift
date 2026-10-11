import Foundation

/// A hero slide from `mediaview/api/v1/homebanners` (`BannerMasterDetails.master_details`).
nonisolated struct HomeBanner: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let title: String
    let slug: String?
    let kind: ContentKind
    let synopsis: String?
    let genres: [String]
    let backdropURL: URL?
    let titleImageURL: URL?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case masterDetails = "master_details"
    }

    private enum DetailKeys: String, CodingKey {
        case id = "_id", title, slug, description, genre
        case shoType = "sho_type"
        case titleImages = "title_images"
        case titleImage = "title_image"
        case videoBannerImages = "video_banner_images"
        case homeBannerImages = "home_banner_images"
        case homeBannerImage = "home_banner_image"
        case mobileCoverImage = "mobile_cover_image"
        case posterImage = "poster_image"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let details = try container.nestedContainer(keyedBy: DetailKeys.self, forKey: .masterDetails)
        guard let title = details.lenientString(.title) else {
            throw DecodingError.dataCorruptedError(forKey: .title, in: details, debugDescription: "Banner without title")
        }
        id = container.lenientString(.id) ?? details.lenientString(.id) ?? title
        self.title = title
        slug = details.lenientString(.slug)
        kind = ContentKind(shoType: details.lenientInt(.shoType))
        synopsis = details.lenientString(.description)
        genres = details.lossyArray(Genre.self, .genre).map(\.title)

        // Same priority as BannerTableViewCell: video banner → home banner → cover/poster.
        // The hero is portrait-tall, so the large `web` render crops best.
        let backdrop = details.lenient(ImageSet.self, .videoBannerImages)?.path(preferring: [.web, .key, .mobile])
            ?? details.lenient(ImageSet.self, .homeBannerImages)?.path(preferring: [.web, .key, .mobile])
            ?? details.lenientString(.homeBannerImage)
            ?? details.lenientString(.mobileCoverImage)
            ?? details.lenientString(.posterImage)
        backdropURL = ImageURL.resolve(backdrop)

        let titleArt = details.lenient(ImageSet.self, .titleImages)?.path(preferring: [.web, .key, .mobile])
            ?? details.lenientString(.titleImage)
        titleImageURL = ImageURL.resolve(titleArt)
    }
}

/// `response` payload of `homebanners`.
nonisolated struct HomeBannerList: Decodable, Sendable {
    let banners: [HomeBanner]

    private enum CodingKeys: String, CodingKey { case data }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        banners = container.lossyArray(HomeBanner.self, .data)
    }
}
