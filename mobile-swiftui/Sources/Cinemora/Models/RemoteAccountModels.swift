import Foundation

struct RemoteAccountUser: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let email: String?
    let role: String?
    /// Nhãn cũ do admin đặt, ví dụ "VIP".
    let badge: String?
    /// Danh sách nhãn mới, có thể là chữ, ảnh/GIF, màu và hiệu ứng.
    let badges: [CommentBadge]
    /// Màu và hiệu ứng làm nổi bật tên người dùng.
    let nameStyle: CommentNameStyle?
    /// Ảnh đại diện dạng data URL.
    let avatar: String?
    let createdAt: String?

    var displayName: String { name?.isEmpty == false ? name! : email ?? "Cinemora User" }

    var visibleBadges: [CommentBadge] {
        if !badges.isEmpty { return badges }
        guard let badge, !badge.isEmpty else { return [] }
        return [CommentBadge(legacyText: badge)]
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, email, role, badge, badges, nameStyle, avatar, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        badge = try container.decodeIfPresent(String.self, forKey: .badge)
        if let decoded = try? container.decode(FlexibleBadges.self, forKey: .badges) {
            badges = decoded.badges
        } else {
            badges = []
        }
        if let decoded = try? container.decode(FlexibleNameStyle.self, forKey: .nameStyle) {
            nameStyle = decoded.style
        } else {
            nameStyle = nil
        }
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }
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

struct RemoteQrChallenge: Decodable {
    let nonce: String
    let payload: String
    let expiresAt: String
}

struct RemoteQrStatus: Decodable {
    let status: String
    let expiresAt: String?
    let deviceName: String?
    let approver: RemoteQrApprover?
}

struct RemoteQrApprover: Decodable {
    let name: String?
    let email: String?
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

struct RemoteMovieRequest: Decodable, Identifiable {
    let id: Int
    let userId: Int?
    let requesterName: String?
    let requesterEmail: String?
    let title: String
    let link: String?
    let priority: String
    let notes: String?
    let posterUrl: String?
    let status: String
    let adminMessage: String?
    let createdAt: FlexibleDate?
    let updatedAt: FlexibleDate?
    let statusUpdatedAt: FlexibleDate?

    var statusTitle: String {
        switch status {
        case "processing": return "Đang Xử Lý"
        case "updated": return "Đã Cập Nhật"
        case "other": return "Khác"
        default: return "Đã Tiếp Nhận"
        }
    }

    var statusTint: ColorKey {
        switch status {
        case "processing": return .amber
        case "updated": return .mint
        case "other": return .violet
        default: return .sky
        }
    }
}

enum ColorKey: Hashable {
    case amber, mint, violet, sky
}
