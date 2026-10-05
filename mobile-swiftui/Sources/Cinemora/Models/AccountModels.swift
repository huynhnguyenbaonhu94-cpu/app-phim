import Foundation

struct AccountUser: Codable, Equatable {
    let id: Int
    let name: String?
    let email: String?
    let role: String
}

struct AccountAuthResponse: Decodable {
    let user: AccountUser
    let token: String
    let sessionId: String
    let expiresAt: String
}

struct AccountSuccessResponse: Decodable { let success: Bool }
struct AccountHeartbeatResponse: Decodable { let success: Bool; let serverTime: String }
struct AccountLogoutAllResponse: Decodable { let success: Bool; let revokedCount: Int }

struct AccountDevice: Decodable, Identifiable, Equatable {
    let sessionId: String
    let deviceId: String
    let name: String
    let model: String?
    let osVersion: String?
    let appVersion: String?
    let ipAddress: String?
    let createdAt: String
    let lastSeenAt: String
    let isCurrent: Bool
    let isOnline: Bool
    var id: String { sessionId }
}

struct SyncedFavorite: Decodable {
    let movieSlug: String
    let movieName: String
    let originName: String?
    let posterUrl: String?
    let year: Int?
    let addedAt: String?
}

struct SyncedHistoryRecord: Decodable {
    let movieSlug: String
    let movieName: String
    let originName: String?
    let posterUrl: String?
    let year: Int?
    let episodeSlug: String?
    let episodeName: String?
    let serverName: String?
    let watchedSeconds: Int
    let durationSeconds: Int
    let isCompleted: Bool?
    let lastWatchedAt: String
}

struct SyncedPreferences: Decodable {
    let preferences: PlaybackDefaults
    let updatedAt: String
}

struct AccountSyncResponse: Decodable {
    let favorites: [SyncedFavorite]
    let history: [SyncedHistoryRecord]
    let preferences: SyncedPreferences?
}
