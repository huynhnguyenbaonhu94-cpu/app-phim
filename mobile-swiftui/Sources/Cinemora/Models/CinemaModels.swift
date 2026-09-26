import Foundation

struct Movie: Decodable, Identifiable, Hashable {
    let apiID: String?
    let slug: String
    let name: String
    let originName: String?
    let poster: String?
    let backdrop: String?
    let year: Int?
    let quality: String?
    let episodeCurrent: String?
    let episodeTotal: Int?
    let time: String?
    let lang: String?
    let description: String?
    let rating: Double?
    let categories: [MovieTag]?
    let countries: [MovieTag]?
    let actors: [String]?
    let actorProfiles: [MovieActorProfile]?
    let directors: [String]?
    let views: Int?
    let alternativeNames: [String]?
    let status: String?
    let tmdbId: String?
    let imdbId: String?
    let createdAt: String?
    let updatedAt: String?
    let servers: [MovieServer]?

    var id: String { apiID ?? slug }
    var posterURL: URL? { CinemaAPI.absoluteURL(poster ?? backdrop) }
    var backdropURL: URL? { CinemaAPI.absoluteURL(backdrop ?? poster) }
    var displayTitle: String { originName.map { "\(name) · \($0)" } ?? name }

    enum CodingKeys: String, CodingKey {
        case apiID = "id", slug, name, originName, poster, backdrop, year, quality
        case episodeCurrent, episodeTotal, time, lang, description, rating, categories
        case countries, actors, actorProfiles, directors, views, alternativeNames, status
        case tmdbId, imdbId, createdAt, updatedAt, servers
    }
}

struct MovieActorProfile: Decodable, Hashable, Identifiable {
    let name: String
    let image: String?

    var id: String { name }
    var imageURL: URL? { CinemaAPI.absoluteURL(image) }
}

struct MovieTag: Decodable, Hashable, Identifiable {
    let name: String
    let slug: String
    var id: String { slug }
}

struct MovieServer: Decodable, Hashable, Identifiable {
    let name: String
    let isAi: Bool
    let episodes: [MovieEpisode]
    var id: String { name }
}

struct MovieEpisode: Decodable, Hashable, Identifiable {
    let name: String
    let slug: String
    let filename: String
    let embedUrl: String?
    let streamUrl: String?
    var id: String { slug.isEmpty ? name : slug }
    var streamURL: URL? { CinemaAPI.absoluteURL(streamUrl) }
    var embedURL: URL? { CinemaAPI.absoluteURL(embedUrl) }
}

struct MoviePage: Decodable {
    let items: [Movie]
    let pagination: Pagination?
}

struct Pagination: Decodable {
    let totalPages: Int?
    let currentPage: Int?
    let hasNextPage: Bool?
    let totalItems: Int?
    let itemsPerPage: Int?
    let totalItemsPerPage: Int?

    enum CodingKeys: String, CodingKey {
        case totalPages, currentPage, hasNextPage, totalItems, itemsPerPage, totalItemsPerPage
        case total_pages, current_page, has_next_page, total_items, items_per_page
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalPages = try c.decodeIfPresent(Int.self, forKey: .totalPages) ?? c.decodeIfPresent(Int.self, forKey: .total_pages)
        currentPage = try c.decodeIfPresent(Int.self, forKey: .currentPage) ?? c.decodeIfPresent(Int.self, forKey: .current_page)
        hasNextPage = try c.decodeIfPresent(Bool.self, forKey: .hasNextPage) ?? c.decodeIfPresent(Bool.self, forKey: .has_next_page)
        totalItems = try c.decodeIfPresent(Int.self, forKey: .totalItems) ?? c.decodeIfPresent(Int.self, forKey: .total_items)
        itemsPerPage = try c.decodeIfPresent(Int.self, forKey: .itemsPerPage) ?? c.decodeIfPresent(Int.self, forKey: .items_per_page)
        totalItemsPerPage = try c.decodeIfPresent(Int.self, forKey: .totalItemsPerPage)
    }

    func hasMore(page: Int, received: Int) -> Bool {
        if let totalPages { return page < totalPages }
        if let hasNextPage { return hasNextPage }
        if let totalItems, let pageSize = totalItemsPerPage ?? itemsPerPage, pageSize > 0 { return page * pageSize < totalItems }
        return received >= 12
    }
}

struct CatalogMeta: Decodable {
    let categories: [MovieTag]
    let countries: [MovieTag]
    let years: [Int]
}
