import Foundation

struct PlaybackDefaults: Codable, Equatable {
    var autoAdvanceEpisodes = true
    var stopTimer = "Tắt"
    var pictureInPicture = true
    var subtitlePreferences = SubtitlePreferences()

    private enum CodingKeys: String, CodingKey {
        case autoAdvanceEpisodes, stopTimer, pictureInPicture, subtitlePreferences
    }

    init() {}
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoAdvanceEpisodes = try container.decodeIfPresent(Bool.self, forKey: .autoAdvanceEpisodes) ?? true
        stopTimer = try container.decodeIfPresent(String.self, forKey: .stopTimer) ?? "Tắt"
        pictureInPicture = try container.decodeIfPresent(Bool.self, forKey: .pictureInPicture) ?? true
        subtitlePreferences = try container.decodeIfPresent(SubtitlePreferences.self, forKey: .subtitlePreferences) ?? SubtitlePreferences()
    }
}

struct LocalMovieRecord: Codable, Identifiable, Hashable {
    let slug: String
    let name: String
    let originName: String?
    let poster: String?
    let year: Int?
    let quality: String?
    let savedAt: Date

    var id: String { slug }

    var movie: Movie {
        Movie(apiID: nil, slug: slug, name: name, originName: originName, poster: poster, backdrop: poster, year: year, quality: quality, episodeCurrent: nil, episodeTotal: nil, time: nil, lang: nil, description: nil, rating: nil, categories: nil, countries: nil, actors: nil, actorProfiles: nil, directors: nil, views: nil, alternativeNames: nil, status: nil, tmdbId: nil, imdbId: nil, createdAt: nil, updatedAt: nil, servers: nil, allowPip: nil, episodeGroups: nil)
    }

    init(movie: Movie, savedAt: Date = Date()) {
        self.slug = movie.slug
        self.name = movie.name
        self.originName = movie.originName
        self.poster = movie.poster ?? movie.backdrop
        self.year = movie.year
        self.quality = movie.quality
        self.savedAt = savedAt
    }

    init(slug: String, name: String, originName: String? = nil, poster: String? = nil, year: Int? = nil, quality: String? = nil, savedAt: Date = Date()) {
        self.slug = slug; self.name = name; self.originName = originName
        self.poster = poster; self.year = year; self.quality = quality; self.savedAt = savedAt
    }
}

struct LocalWatchRecord: Codable, Identifiable, Hashable {
    let movie: LocalMovieRecord
    let episodeName: String?
    let episodeSlug: String?
    let serverName: String?
    let streamURL: String?
    let embedURL: String?
    let watchedSeconds: Double
    let durationSeconds: Double
    let watchedAt: Date
    let isCompleted: Bool

    var id: String { "\(movie.slug)::\(episodeSlug ?? "movie")" }

    init(movie: LocalMovieRecord, episodeName: String? = nil, episodeSlug: String? = nil, serverName: String? = nil, streamURL: String? = nil, embedURL: String? = nil, watchedSeconds: Double, durationSeconds: Double, watchedAt: Date = Date(), isCompleted: Bool = false) {
        self.movie = movie; self.episodeName = episodeName; self.episodeSlug = episodeSlug
        self.serverName = serverName; self.streamURL = streamURL; self.embedURL = embedURL
        self.watchedSeconds = watchedSeconds; self.durationSeconds = durationSeconds
        self.watchedAt = watchedAt; self.isCompleted = isCompleted
    }

    private enum CodingKeys: String, CodingKey {
        case movie, episodeName, episodeSlug, serverName, streamURL, embedURL
        case watchedSeconds, durationSeconds, watchedAt, isCompleted
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        movie = try values.decode(LocalMovieRecord.self, forKey: .movie)
        episodeName = try values.decodeIfPresent(String.self, forKey: .episodeName)
        episodeSlug = try values.decodeIfPresent(String.self, forKey: .episodeSlug)
        serverName = try values.decodeIfPresent(String.self, forKey: .serverName)
        streamURL = try values.decodeIfPresent(String.self, forKey: .streamURL)
        embedURL = try values.decodeIfPresent(String.self, forKey: .embedURL)
        watchedSeconds = try values.decodeIfPresent(Double.self, forKey: .watchedSeconds) ?? 0
        durationSeconds = try values.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        watchedAt = try values.decodeIfPresent(Date.self, forKey: .watchedAt) ?? Date.distantPast
        isCompleted = try values.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
    }
}
