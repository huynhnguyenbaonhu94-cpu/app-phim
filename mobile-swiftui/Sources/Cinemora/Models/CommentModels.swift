import Foundation

// MARK: - Flexible primitives

/// Giải mã một giá trị có thể đến dưới dạng chuỗi hoặc số (id bình luận, id người dùng).
struct FlexibleID: Decodable, Hashable {
    let value: String

    init(_ raw: String) { value = raw }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else if let double = try? container.decode(Double.self) {
            value = String(Int(double))
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Không đọc được id")
        }
    }
}

/// Giải mã thời gian đến từ nhiều kiểu: ISO có/không có phần thập phân, epoch giây, epoch mili giây.
struct FlexibleDate: Decodable {
    let date: Date?

    init(_ date: Date?) { self.date = date }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let raw = try? container.decode(String.self) {
            date = Self.parse(raw)
        } else if let number = try? container.decode(Double.self) {
            // Giá trị lớn là mili giây, nhỏ là giây.
            let seconds = number > 10_000_000_000 ? number / 1000 : number
            date = Date(timeIntervalSince1970: seconds)
        } else {
            date = nil
        }
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let sqlStyle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    static func parse(_ raw: String) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let date = isoFractional.date(from: value) { return date }
        if let date = isoPlain.date(from: value) { return date }
        if let date = sqlStyle.date(from: value) { return date }
        if let number = Double(value) {
            return Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1000 : number)
        }
        return nil
    }
}

/// Người viết bình luận, khi máy chủ trả về dạng object lồng nhau.
private struct NestedCommentAuthor: Decodable {
    let id: FlexibleID?
    let name: String?
    let role: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case id, userId, user_id
        case name, userName, user_name, displayName, display_name
        case role, userRole, user_role
        case email
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(FlexibleID.self, forKey: .id)
            ?? container.decodeIfPresent(FlexibleID.self, forKey: .userId)
            ?? container.decodeIfPresent(FlexibleID.self, forKey: .user_id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .userName)
            ?? container.decodeIfPresent(String.self, forKey: .user_name)
            ?? container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .display_name)
        role = try container.decodeIfPresent(String.self, forKey: .role)
            ?? container.decodeIfPresent(String.self, forKey: .userRole)
            ?? container.decodeIfPresent(String.self, forKey: .user_role)
        email = try container.decodeIfPresent(String.self, forKey: .email)
    }
}

// MARK: - Comment

/// Một bình luận hoặc một trả lời cho một bộ phim.
///
/// Giải mã được viết dễ tính có chủ đích: endpoint bình luận có thể đặt tên trường
/// là `userName`, `user_name` hay `author`, thời gian là ISO hay epoch, và id có
/// thể là chuỗi hoặc số. App chấp nhận tất cả thay vì biến mọi bình luận thành
/// một lỗi giải mã.
struct MovieComment: Identifiable, Hashable, Codable {
    let id: String
    let parentID: String?
    let content: String
    let authorName: String
    let authorRole: String?
    let authorID: String?
    let authorEmail: String?
    let createdAt: Date?

    // Trạng thái phía client, không đến từ máy chủ.
    /// Bình luận chỉ nằm trên thiết bị này (máy chủ chưa hỗ trợ bình luận).
    var isLocal = false
    /// Đang gửi lên máy chủ.
    var isPending = false
    /// Gửi thất bại, có thể thử lại.
    var isFailed = false
    /// Do chính người dùng hiện tại viết.
    var isMine = false

    var isAdmin: Bool {
        let role = (authorRole ?? "")
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if role.contains("admin") || role.contains("quantri") || role.contains("moderator") { return true }
        // Đường dự phòng cho tới khi máy chủ trả `role`: chủ app thêm email của
        // mình vào `CommentAuthor.fallbackAdminEmails` là huy hiệu hiện ngay.
        guard let email = authorEmail?.lowercased(), !email.isEmpty else { return false }
        return CommentAuthor.fallbackAdminEmails.contains(email)
    }

    var initials: String {
        let trimmed = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    /// "vừa xong", "5 phút", "3 giờ", "2 ngày", sau đó là ngày cụ thể.
    var relativeTime: String {
        guard let createdAt else { return "" }
        let seconds = Date().timeIntervalSince(createdAt)
        if seconds < 45 { return "vừa xong" }
        if seconds < 3600 { return "\(max(1, Int(seconds / 60))) phút" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) giờ" }
        if seconds < 604_800 { return "\(Int(seconds / 86_400)) ngày" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: createdAt)
    }

    init(
        id: String,
        parentID: String?,
        content: String,
        authorName: String,
        authorRole: String?,
        authorID: String?,
        authorEmail: String? = nil,
        createdAt: Date?,
        isLocal: Bool = false,
        isPending: Bool = false,
        isFailed: Bool = false,
        isMine: Bool = false
    ) {
        self.id = id
        self.parentID = parentID
        self.content = content
        self.authorName = authorName
        self.authorRole = authorRole
        self.authorID = authorID
        self.authorEmail = authorEmail
        self.createdAt = createdAt
        self.isLocal = isLocal
        self.isPending = isPending
        self.isFailed = isFailed
        self.isMine = isMine
    }

    private enum CodingKeys: String, CodingKey {
        case id, commentId, comment_id, _id
        case parentId, parent_id, parentID, replyTo, reply_to, parentCommentId, parent_comment_id
        case content, text, body, message
        case authorName, userName, user_name, author, fullName, full_name, name
        case authorRole, role, userRole, user_role
        case authorId, userId, user_id
        case authorEmail, userEmail, user_email, email
        case createdAt, created_at, time, date, timestamp
        case isMine, mine, isOwner, is_owner
        case user, author_user, authorUser
        case isLocal, isPending, isFailed
    }

    /// Mã hoá tường minh để bản lưu trên thiết bị đọc lại đúng những gì đã ghi.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(parentID, forKey: .parentID)
        try container.encode(content, forKey: .content)
        try container.encode(authorName, forKey: .authorName)
        try container.encodeIfPresent(authorRole, forKey: .authorRole)
        try container.encodeIfPresent(authorID, forKey: .authorId)
        try container.encodeIfPresent(authorEmail, forKey: .authorEmail)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encode(isLocal, forKey: .isLocal)
        try container.encode(isPending, forKey: .isPending)
        try container.encode(isFailed, forKey: .isFailed)
        try container.encode(isMine, forKey: .isMine)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let nested = try container.decodeIfPresent(NestedCommentAuthor.self, forKey: .user)
            ?? container.decodeIfPresent(NestedCommentAuthor.self, forKey: .authorUser)
            ?? container.decodeIfPresent(NestedCommentAuthor.self, forKey: .author_user)

        let rawID = try container.decodeIfPresent(FlexibleID.self, forKey: .id)
            ?? container.decodeIfPresent(FlexibleID.self, forKey: .commentId)
            ?? container.decodeIfPresent(FlexibleID.self, forKey: .comment_id)
            ?? container.decodeIfPresent(FlexibleID.self, forKey: ._id)
        id = rawID?.value ?? UUID().uuidString

        let rawParent = try container.decodeIfPresent(FlexibleID.self, forKey: .parentId)
            ?? container.decodeIfPresent(FlexibleID.self, forKey: .parentID)
            ?? container.decodeIfPresent(FlexibleID.self, forKey: .parent_id)
            ?? container.decodeIfPresent(FlexibleID.self, forKey: .replyTo)
            ?? container.decodeIfPresent(FlexibleID.self, forKey: .reply_to)
            ?? container.decodeIfPresent(FlexibleID.self, forKey: .parentCommentId)
            ?? container.decodeIfPresent(FlexibleID.self, forKey: .parent_comment_id)
        parentID = rawParent?.value

        content = try container.decodeIfPresent(String.self, forKey: .content)
            ?? container.decodeIfPresent(String.self, forKey: .text)
            ?? container.decodeIfPresent(String.self, forKey: .body)
            ?? container.decodeIfPresent(String.self, forKey: .message)
            ?? ""

        authorName = try container.decodeIfPresent(String.self, forKey: .authorName)
            ?? container.decodeIfPresent(String.self, forKey: .userName)
            ?? container.decodeIfPresent(String.self, forKey: .user_name)
            ?? container.decodeIfPresent(String.self, forKey: .author)
            ?? container.decodeIfPresent(String.self, forKey: .fullName)
            ?? container.decodeIfPresent(String.self, forKey: .full_name)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? nested?.name
            ?? "Người xem"

        authorRole = try container.decodeIfPresent(String.self, forKey: .authorRole)
            ?? container.decodeIfPresent(String.self, forKey: .role)
            ?? container.decodeIfPresent(String.self, forKey: .userRole)
            ?? container.decodeIfPresent(String.self, forKey: .user_role)
            ?? nested?.role

        authorID = (try container.decodeIfPresent(FlexibleID.self, forKey: .authorId)
            ?? container.decodeIfPresent(FlexibleID.self, forKey: .userId)
            ?? container.decodeIfPresent(FlexibleID.self, forKey: .user_id))?.value
            ?? nested?.id?.value

        authorEmail = try container.decodeIfPresent(String.self, forKey: .authorEmail)
            ?? container.decodeIfPresent(String.self, forKey: .userEmail)
            ?? container.decodeIfPresent(String.self, forKey: .user_email)
            ?? container.decodeIfPresent(String.self, forKey: .email)
            ?? nested?.email

        let flexible = try container.decodeIfPresent(FlexibleDate.self, forKey: .createdAt)
            ?? container.decodeIfPresent(FlexibleDate.self, forKey: .created_at)
            ?? container.decodeIfPresent(FlexibleDate.self, forKey: .time)
            ?? container.decodeIfPresent(FlexibleDate.self, forKey: .date)
            ?? container.decodeIfPresent(FlexibleDate.self, forKey: .timestamp)
        createdAt = flexible?.date

        isMine = (try container.decodeIfPresent(Bool.self, forKey: .isMine))
            ?? (try container.decodeIfPresent(Bool.self, forKey: .mine))
            ?? (try container.decodeIfPresent(Bool.self, forKey: .isOwner))
            ?? (try container.decodeIfPresent(Bool.self, forKey: .is_owner))
            ?? false
    }
}

/// Danh sách bình luận trả về từ máy chủ, chấp nhận mảng trần hoặc object bọc.
/// Một phần tử hỏng chỉ bị bỏ qua, không làm mất cả danh sách.
private struct IgnoredValue: Decodable {
    init(from decoder: Decoder) throws {}
}

private struct LenientCommentList: Decodable {
    let items: [MovieComment]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [MovieComment] = []
        while !container.isAtEnd {
            if let comment = try? container.decode(MovieComment.self) {
                result.append(comment)
            } else {
                // Tiêu thụ phần tử hỏng để vòng lặp tiến tiếp.
                _ = try? container.decode(IgnoredValue.self)
            }
        }
        items = result
    }
}

struct MovieCommentPage: Decodable {
    let items: [MovieComment]

    init(_ items: [MovieComment]) { self.items = items }

    private enum Keys: String, CodingKey {
        case items, comments, data, list, results, rows
    }

    init(from decoder: Decoder) throws {
        if let array = try? LenientCommentList(from: decoder) {
            items = array.items
            return
        }
        let container = try decoder.container(keyedBy: Keys.self)
        for key in [Keys.items, .comments, .data, .list, .results, .rows] {
            if let value = try? container.decode(LenientCommentList.self, forKey: key) {
                items = value.items
                return
            }
        }
        items = []
    }
}

/// Phản hồi khi gửi bình luận: có thể là chính bình luận, hoặc object bọc nó.
struct MovieCommentEnvelope: Decodable {
    let comment: MovieComment?

    init(_ comment: MovieComment?) { self.comment = comment }

    private enum Keys: String, CodingKey {
        case comment, item, data, result
    }

    init(from decoder: Decoder) throws {
        if let single = try? MovieComment(from: decoder) {
            comment = single
            return
        }
        let container = try decoder.container(keyedBy: Keys.self)
        comment = try container.decodeIfPresent(MovieComment.self, forKey: .comment)
            ?? container.decodeIfPresent(MovieComment.self, forKey: .item)
            ?? container.decodeIfPresent(MovieComment.self, forKey: .data)
            ?? container.decodeIfPresent(MovieComment.self, forKey: .result)
    }
}

/// Một bình luận gốc kèm các trả lời của nó (chỉ lồng một cấp).
struct MovieCommentThread: Identifiable, Hashable {
    let root: MovieComment
    var replies: [MovieComment]

    var id: String { root.id }
}

/// Người đang đăng nhập, dùng để dựng bình luận lạc quan và nhận biết quản trị.
struct CommentAuthor: Equatable {
    let id: String?
    let name: String
    let role: String?
    let email: String?

    init(id: String?, name: String, role: String?, email: String?) {
        self.id = id
        self.name = name
        self.role = role
        self.email = email
    }

    /// Dựng từ tài khoản đang đăng nhập.
    init(account: RemoteAccountUser) {
        self.id = String(account.id)
        self.name = account.displayName
        self.role = account.role
        self.email = account.email
    }

    var isAdmin: Bool {
        let value = (role ?? "")
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
        return value.contains("admin") || value.contains("quantri")
    }

    static let guest = CommentAuthor(id: nil, name: "", role: nil, email: nil)

    /// Tên hiển thị nào cũng có thể được coi là quản trị nếu máy chủ chưa trả role.
    /// Đặt email ở đây để gắn huy hiệu cho chủ app ngay cả trước khi backend xong.
    static let fallbackAdminEmails: Set<String> = []

    func matches(_ comment: MovieComment) -> Bool {
        if let id, let authorID = comment.authorID, !authorID.isEmpty { return id == authorID }
        return !name.isEmpty && comment.authorName.caseInsensitiveCompare(name) == .orderedSame
    }
}
