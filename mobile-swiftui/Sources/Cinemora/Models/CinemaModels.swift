import Foundation

struct TvStream: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let streamUrl: String
    let audioUrl: String?
    let logoUrl: String?
    let posterUrl: String?
    let description: String?
    let sortOrder: Int
    let isActive: Bool
    let healthStatus: String?
    let healthMessage: String?
    let lastCheckedAt: String?

    var streamURL: URL? { CinemaAPI.tvStreamURL(streamUrl) }
    var audioURL: URL? { CinemaAPI.tvStreamURL(audioUrl) }
    var posterURL: URL? { CinemaAPI.absoluteURL(posterUrl ?? logoUrl) }
    var logoURL: URL? { CinemaAPI.absoluteURL(logoUrl) }
    var isOnline: Bool { healthStatus == "online" }
}

struct TvStreamSnapshot: Decodable {
    let version: Int
    let streams: [TvStream]
}

struct TvVideo: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let logoUrl: String?
    let description: String?
    let sortOrder: Int
    let isActive: Bool
    let allowPip: Bool?
    let episodes: [TvVideoEpisode]
    var logoURL: URL? { CinemaAPI.absoluteURL(logoUrl) }
}

struct TvVideoEpisode: Decodable, Identifiable, Hashable {
    let id: Int
    let videoId: Int
    let episodeNumber: Int
    let name: String
    let subtitleUrl: String?
    let bilingualSubtitleUrl: String?
    let qualities: [TvVideoQuality]
    var subtitleURL: URL? { CinemaAPI.absoluteURL(subtitleUrl) }
    var bilingualSubtitleURL: URL? { CinemaAPI.absoluteURL(bilingualSubtitleUrl) }
}

struct TvVideoQuality: Decodable, Identifiable, Hashable {
    let id: Int
    let episodeId: Int
    let label: String
    let streamUrl: String
    let subtitleUrl: String?
    let bilingualSubtitleUrl: String?
    var streamURL: URL? { CinemaAPI.tvStreamURL(streamUrl) }
    var subtitleURL: URL? { CinemaAPI.absoluteURL(subtitleUrl) }
    var bilingualSubtitleURL: URL? { CinemaAPI.absoluteURL(bilingualSubtitleUrl) }
}

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
    let allowPip: Bool?
    // Some API responses expose the same groups as `episodes` instead of `servers`.
    var episodeGroups: [MovieServer]?

    var id: String { apiID ?? slug }
    var posterURL: URL? { CinemaAPI.absoluteURL(poster ?? backdrop) }
    var backdropURL: URL? { CinemaAPI.absoluteURL(backdrop ?? poster) }
    var displayTitle: String { originName.map { "\(name) · \($0)" } ?? name }
    var availableServers: [MovieServer] {
        if let servers, !servers.isEmpty { return servers }
        return episodeGroups ?? []
    }

    enum CodingKeys: String, CodingKey {
        case apiID = "id", slug, name, originName, poster, backdrop, year, quality
        case episodeCurrent, episodeTotal, time, lang, description, rating, categories
        case countries, actors, actorProfiles, directors, views, alternativeNames, status
        case tmdbId, imdbId, createdAt, updatedAt, servers, episodeGroups = "episodes", allowPip
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

    init(name: String, isAi: Bool, episodes: [MovieEpisode]) {
        self.name = name
        self.isAi = isAi
        self.episodes = episodes
    }

    enum CodingKeys: String, CodingKey {
        case name, serverName = "server_name"
        case isAi, isAiSnake = "is_ai"
        case episodes, serverData = "server_data", serverDataCamel = "serverData"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .serverName)
            ?? "Nguồn phim"
        isAi = try container.decodeIfPresent(Bool.self, forKey: .isAi)
            ?? container.decodeIfPresent(Bool.self, forKey: .isAiSnake)
            ?? false
        if let value = try? container.decode([MovieEpisode].self, forKey: .episodes) {
            episodes = value
        } else if let value = try? container.decode([MovieEpisode].self, forKey: .serverData) {
            episodes = value
        } else {
            episodes = (try? container.decode([MovieEpisode].self, forKey: .serverDataCamel)) ?? []
        }
    }
}

struct MovieEpisode: Decodable, Hashable, Identifiable {
    let name: String
    let slug: String
    let filename: String
    let embedUrl: String?
    let streamUrl: String?
    let subtitleUrl: String?
    let bilingualSubtitleUrl: String?
    var id: String { slug.isEmpty ? name : slug }
    var streamURL: URL? { CinemaAPI.absoluteURL(streamUrl) }
    var embedURL: URL? { CinemaAPI.absoluteURL(embedUrl) }
    var subtitleURL: URL? { CinemaAPI.absoluteURL(subtitleUrl) }
    var bilingualSubtitleURL: URL? { CinemaAPI.absoluteURL(bilingualSubtitleUrl) }

    init(name: String, slug: String, filename: String, embedUrl: String?, streamUrl: String?, subtitleUrl: String? = nil, bilingualSubtitleUrl: String? = nil) {
        self.name = name
        self.slug = slug
        self.filename = filename
        self.embedUrl = embedUrl
        self.streamUrl = streamUrl
        self.subtitleUrl = subtitleUrl
        self.bilingualSubtitleUrl = bilingualSubtitleUrl
    }

    enum CodingKeys: String, CodingKey {
        case name, slug, filename
        case embedUrl, embedURLSnake = "embed_url", linkEmbed = "link_embed"
        case streamUrl, streamURLSnake = "stream_url", linkM3U8 = "link_m3u8", link
        case subtitleUrl, subtitleURLSnake = "subtitle_url", bilingualSubtitleUrl, bilingualSubtitleURLSnake = "bilingual_subtitle_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Tập phim"
        slug = try container.decodeIfPresent(String.self, forKey: .slug) ?? ""
        filename = try container.decodeIfPresent(String.self, forKey: .filename) ?? ""
        embedUrl = try container.decodeIfPresent(String.self, forKey: .embedUrl)
            ?? container.decodeIfPresent(String.self, forKey: .embedURLSnake)
            ?? container.decodeIfPresent(String.self, forKey: .linkEmbed)
        streamUrl = try container.decodeIfPresent(String.self, forKey: .streamUrl)
            ?? container.decodeIfPresent(String.self, forKey: .streamURLSnake)
            ?? container.decodeIfPresent(String.self, forKey: .linkM3U8)
            ?? container.decodeIfPresent(String.self, forKey: .link)
        subtitleUrl = try container.decodeIfPresent(String.self, forKey: .subtitleUrl)
            ?? container.decodeIfPresent(String.self, forKey: .subtitleURLSnake)
        bilingualSubtitleUrl = try container.decodeIfPresent(String.self, forKey: .bilingualSubtitleUrl)
            ?? container.decodeIfPresent(String.self, forKey: .bilingualSubtitleURLSnake)
    }
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
