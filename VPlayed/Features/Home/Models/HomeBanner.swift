import Foundation

/// A hero slide from `mediaview/api/v1/homebanners` (`BannerMasterDetails.master_details`).
nonisolated struct HomeBanner: Sendable, Identifiable, Hashable {
    let id: String
    let title: String
    let slug: String?
    let kind: ContentKind
    let synopsis: String?
    let genres: [String]
    let backdropURL: URL?
    let titleImageURL: URL?

    init(id: String, title: String, slug: String? = nil, kind: ContentKind = .unknown, synopsis: String? = nil, genres: [String] = [], backdropURL: URL? = nil, titleImageURL: URL? = nil) {
        self.id = id
        self.title = title
        self.slug = slug
        self.kind = kind
        self.synopsis = synopsis
        self.genres = genres
        self.backdropURL = backdropURL
        self.titleImageURL = titleImageURL
    }

}
