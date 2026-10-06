import Foundation

struct RemoteAccountUser: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let email: String?
    let role: String?
    let createdAt: String?
    var displayName: String { name?.isEmpty == false ? name! : email ?? "Cinemora User" }
}

struct RemoteOptionalUser: Decodable {
    let value: RemoteAccountUser?

    init(from decoder: Decoder) throws {
        if try decoder.singleValueContainer().decodeNil() { value = nil }
        else { value = try RemoteAccountUser(from: decoder) }
    }
}

struct RemoteAuthResponse: Decodable {
    let user: RemoteAccountUser
}

struct SuccessResponse: Decodable {
    let success: Bool
}

struct RemoteAccountDevice: Decodable, Identifiable, Hashable {
    let id: Int
    let deviceId: String
    let deviceName: String
    let ipAddress: String
    let location: String
    let userAgent: String
    let createdAt: String
    let lastSeenAt: String
    let isOnline: Bool
}

struct RemoteFavorite: Decodable, Identifiable {
    let id: Int
    let movieSlug: String
    let movieName: String
    let originName: String?
    let posterUrl: String?
    let year: Int?
    let addedAt: String?

    var localRecord: LocalMovieRecord {
        LocalMovieRecord(slug: movieSlug, name: movieName, originName: originName, poster: posterUrl, year: year, quality: nil, savedAt: Date())
    }
}

struct RemoteHistory: Decodable, Identifiable {
    let id: Int
    let movieSlug: String
    let movieName: String
    let originName: String?
    let posterUrl: String?
    let year: Int?
    let episodeSlug: String?
    let episodeName: String?
    let watchedSeconds: Int
    let durationSeconds: Int
    let lastWatchedAt: String?

    var localRecord: LocalWatchRecord {
        let movie = LocalMovieRecord(slug: movieSlug, name: movieName, originName: originName, poster: posterUrl, year: year, quality: nil, savedAt: Date())
        return LocalWatchRecord(movie: movie, episodeName: episodeName, episodeSlug: episodeSlug, serverName: nil, streamURL: nil, embedURL: nil, watchedSeconds: Double(watchedSeconds), durationSeconds: Double(durationSeconds), watchedAt: ISO8601DateFormatter().date(from: lastWatchedAt ?? "") ?? Date())
    }
}
