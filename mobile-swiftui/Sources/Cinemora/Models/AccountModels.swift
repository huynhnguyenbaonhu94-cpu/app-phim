import Foundation

struct AccountUser: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let email: String?
    let role: String
}

struct AccountDevice: Decodable, Identifiable, Hashable {
    let id: String
    let deviceName: String
    let deviceModel: String?
    let ipAddress: String?
    let createdAt: String
    let lastSeenAt: String
    let online: Bool
    let current: Bool
    let revoked: Bool
    let revokeReason: String?
    var name: String { deviceName }
}

struct AccountPlaybackPreferences: Codable, Equatable {
    var autoAdvanceEpisodes: Bool = true
    var stopTimer: String = "Tắt"
    var pictureInPicture: Bool = true
    var subtitlePreferences = SubtitlePreferences()
}

struct CloudFavorite: Decodable {
    let movieSlug: String
    let movieName: String
    let originName: String?
    let posterUrl: String?
    let year: Int?
}
struct CloudHistory: Decodable {
    let movieSlug: String
    let movieName: String
    let originName: String?
    let posterUrl: String?
    let year: Int?
    let episodeSlug: String?
    let episodeName: String?
    let watchedSeconds: Int
    let durationSeconds: Int
    let lastWatchedAt: String
}
