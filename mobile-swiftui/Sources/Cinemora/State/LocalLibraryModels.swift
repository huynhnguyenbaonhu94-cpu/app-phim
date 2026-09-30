import Foundation

struct PlaybackDefaults: Codable, Equatable {
    var autoAdvanceEpisodes = true
    var stopTimer = "Tắt"
    var pictureInPicture = true
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
        Movie(apiID: nil, slug: slug, name: name, originName: originName, poster: poster, backdrop: poster, year: year, quality: quality, episodeCurrent: nil, episodeTotal: nil, time: nil, lang: nil, description: nil, rating: nil, categories: nil, countries: nil, actors: nil, actorProfiles: nil, directors: nil, views: nil, alternativeNames: nil, status: nil, tmdbId: nil, imdbId: nil, createdAt: nil, updatedAt: nil, servers: nil, episodeGroups: nil)
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

    var id: String { movie.slug }
}
