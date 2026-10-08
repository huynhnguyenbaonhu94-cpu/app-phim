import Combine
import Foundation

/// Bình luận của một bộ phim.
///
/// Cách hoạt động:
/// - Ưu tiên máy chủ (`cinema.comments` / `cinema.addComment` / `cinema.deleteComment`).
/// - Gửi theo kiểu lạc quan: bình luận hiện ngay với trạng thái "đang gửi", rồi được
///   thay bằng bản của máy chủ khi trả về — người dùng không phải chờ mạng.
/// - Trong lúc màn hình mở, danh sách được làm mới định kỳ nên bình luận của người
///   khác xuất hiện mà không cần thao tác gì.
/// - Nếu máy chủ chưa có endpoint bình luận, app tự chuyển sang lưu trên thiết bị
///   để tính năng vẫn dùng được, và tự quay về chế độ máy chủ khi backend sẵn sàng.
@MainActor
final class CommentsStore: ObservableObject {
    @Published private(set) var threads: [MovieCommentThread] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    /// Máy chủ chưa hỗ trợ bình luận → bình luận đang được lưu trên thiết bị này.
    @Published private(set) var isLocalOnly = false
    @Published private(set) var loadedOnce = false

    private var all: [MovieComment] = []
    private var slug = ""
    private var pollTask: Task<Void, Never>?
    private var lastLoad = Date.distantPast
    /// Số hiệu danh sách bình luận gần nhất máy chủ báo về.
    private var revision = 0

    private var api: CinemaAPI { .shared }

    var totalCount: Int { all.count }

    // MARK: - Vòng đời

    func start(slug: String, author: CommentAuthor) {
        if self.slug == slug {
            // Quay lại cùng một phim: chỉ làm mới, không dựng lại từ đầu.
            Task { await load(author: author, showSpinner: false) }
            return
        }
        stop()
        self.slug = slug
        all = []
        threads = []
        error = nil
        isLocalOnly = false
        loadedOnce = false
        Task { await load(author: author, showSpinner: true) }
        // Chờ bình luận mới kiểu long-poll: máy chủ giữ kết nối và trả về ngay khi
        // có người vừa bình luận, nên không phải làm mới theo chu kỳ cố định. Nếu
        // máy chủ không hỗ trợ (ví dụ dịch vụ PHP), tự lùi về làm mới mỗi 6 giây.
        pollTask = Task { [weak self] in
            let current = slug
            while !Task.isCancelled {
                guard let self, self.slug == current else { return }
                if self.isLocalOnly {
                    try? await Task.sleep(for: .seconds(5))
                    continue
                }
                do {
                    let feed = try await self.api.watchComments(slug: current, since: self.revision)
                    guard !Task.isCancelled else { return }
                    self.revision = feed.revision
                    if feed.changed, !feed.items.isEmpty {
                        self.applyRemote(feed.items, author: author)
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    await self.load(author: author, showSpinner: false)
                    try? await Task.sleep(for: .seconds(6))
                }
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh(author: CommentAuthor) async {
        await load(author: author, showSpinner: false)
    }

    // MARK: - Tải

    private func load(author: CommentAuthor, showSpinner: Bool) async {
        guard !slug.isEmpty else { return }
        // Tránh hai lượt tải chồng nhau ngay khi vừa mở màn hình.
        if !showSpinner, Date().timeIntervalSince(lastLoad) < 2.5 { return }
        lastLoad = Date()
        if showSpinner { isLoading = true }
        defer { if showSpinner { isLoading = false } }

        // Những bình luận chưa lên được máy chủ phải giữ nguyên qua mỗi lần tải.
        let drafts = all.filter { $0.isPending || $0.isFailed }

        do {
            let feed = try await api.comments(slug: slug)
            isLocalOnly = false
            error = nil
            loadedOnce = true
            revision = feed.revision
            merge(feed.items, drafts: drafts, author: author)
        } catch {
            loadedOnce = true
            if Self.isUnsupported(error) {
                isLocalOnly = true
                self.error = nil
                all = LocalCommentStore.load(slug: slug) + drafts
                rebuild()
            } else if all.isEmpty {
                self.error = error.localizedDescription
                rebuild()
            }
        }
    }

    /// Ghép danh sách từ máy chủ với bản nháp đang gửi và bản lưu trên máy.
    private func merge(_ remote: [MovieComment], drafts: [MovieComment], author: CommentAuthor) {
        var merged: [MovieComment] = remote.map { comment in
            var value = comment
            if author.matches(value) { value.isMine = true }
            return value
        }

        // Bình luận của chính mình đã lưu trên máy vẫn phải hiện, kể cả khi
        // máy chủ đã có danh sách riêng.
        let remoteIDs = Set(merged.map(\.id))
        for item in LocalCommentStore.load(slug: slug) where !remoteIDs.contains(item.id) {
            var value = item
            value.isLocal = true
            merged.insert(value, at: 0)
        }

        let mergedIDs = Set(merged.map(\.id))
        for draft in drafts where !mergedIDs.contains(draft.id) {
            merged.insert(draft, at: 0)
        }

        all = merged
        rebuild()
    }

    /// Danh sách mới từ long-poll: ghép y như lúc tải lần đầu.
    private func applyRemote(_ remote: [MovieComment], author: CommentAuthor) {
        let drafts = all.filter { $0.isPending || $0.isFailed }
        merge(remote, drafts: drafts, author: author)
    }

    /// tRPC trả 404 khi procedure không tồn tại — dấu hiệu backend chưa làm phần
    /// bình luận, không phải lỗi của người dùng.
    private static func isUnsupported(_ error: Error) -> Bool {
        if case APIError.http(404) = error { return true }
        if case APIError.server(let message) = error {
            return message.localizedCaseInsensitiveContains("No procedure found")
        }
        return false
    }

    // MARK: - Gửi

    @discardableResult
    func send(_ raw: String, replyingTo: MovieComment?, author: CommentAuthor) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !slug.isEmpty, !author.name.isEmpty else { return false }

        var parentID: String?
        if let replyingTo, !replyingTo.isPending, !replyingTo.isFailed {
            let root = rootID(for: replyingTo, in: index())
            if root != replyingTo.id { parentID = root }
        }

        let draft = MovieComment(
            id: "local-" + UUID().uuidString,
            parentID: parentID,
            content: text,
            authorName: author.name,
            authorRole: author.role,
            authorID: author.id,
            authorEmail: author.email,
            createdAt: Date(),
            isLocal: isLocalOnly,
            isPending: true,
            isFailed: false,
            isMine: true
        )
        all.insert(draft, at: 0)
        rebuild()
        Task { await upload(draft, author: author) }
        return true
    }

    func retry(_ comment: MovieComment, author: CommentAuthor) {
        guard comment.isFailed, let index = all.firstIndex(where: { $0.id == comment.id }) else { return }
        all[index].isFailed = false
        all[index].isPending = true
        let draft = all[index]
        rebuild()
        Task { await upload(draft, author: author) }
    }

    private func upload(_ draft: MovieComment, author: CommentAuthor) async {
        do {
            let saved = try await api.addComment(slug: slug, content: draft.content, parentID: draft.parentID)
            if let index = all.firstIndex(where: { $0.id == draft.id }) {
                var resolved = saved ?? draft
                // Máy chủ có thể trả về bản rút gọn; giữ lại nội dung người dùng đã gõ.
                if resolved.content.isEmpty {
                    resolved = MovieComment(
                        id: resolved.id,
                        parentID: resolved.parentID ?? draft.parentID,
                        content: draft.content,
                        authorName: resolved.authorName.isEmpty ? draft.authorName : resolved.authorName,
                        authorRole: resolved.authorRole ?? draft.authorRole,
                        authorID: resolved.authorID ?? draft.authorID,
                        authorEmail: resolved.authorEmail ?? draft.authorEmail,
                        createdAt: resolved.createdAt ?? draft.createdAt,
                        badge: resolved.badge,
                        avatar: resolved.avatar,
                        isPinned: resolved.isPinned,
                        canDelete: resolved.canDelete
                    )
                }
                resolved.isMine = true
                resolved.isPending = false
                resolved.isFailed = false
                resolved.isLocal = false
                all[index] = resolved
            }
            error = nil
            rebuild()
        } catch {
            if let index = all.firstIndex(where: { $0.id == draft.id }) {
                all[index].isPending = false
                if Self.isUnsupported(error) {
                    // Backend chưa làm bình luận: lưu trên thiết bị, coi như đã gửi.
                    isLocalOnly = true
                    all[index].isLocal = true
                    all[index].isFailed = false
                } else {
                    all[index].isFailed = true
                    self.error = error.localizedDescription
                }
            }
            if isLocalOnly { persist() }
            rebuild()
        }
    }

    // MARK: - Xoá

    func delete(_ comment: MovieComment, author: CommentAuthor) {
        guard comment.isMine else { return }
        let removed = all.filter { $0.id == comment.id || $0.parentID == comment.id }
        all.removeAll { $0.id == comment.id || $0.parentID == comment.id }
        rebuild()
        if comment.isLocal || isLocalOnly || comment.isPending || comment.isFailed {
            persist()
            return
        }
        Task {
            do {
                try await api.deleteComment(slug: slug, id: comment.id)
                persist()
            } catch {
                // Xoá thất bại thì trả bình luận về chỗ cũ thay vì im lặng làm mất.
                all.append(contentsOf: removed)
                self.error = error.localizedDescription
                rebuild()
            }
        }
    }

    // MARK: - Dựng cây

    private func index() -> [String: MovieComment] {
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Trả lời của trả lời được gắn về bình luận gốc để cây chỉ lồng một cấp.
    private func rootID(for comment: MovieComment, in index: [String: MovieComment]) -> String {
        var current = comment
        var hops = 0
        while let parent = current.parentID, !parent.isEmpty, hops < 12 {
            guard let next = index[parent] else { return comment.id }
            current = next
            hops += 1
        }
        return current.id
    }

    private func rebuild() {
        let index = index()
        var roots: [MovieComment] = []
        var byParent: [String: [MovieComment]] = [:]

        for comment in all {
            guard let parent = comment.parentID, !parent.isEmpty, index[parent] != nil else {
                roots.append(comment)
                continue
            }
            let root = rootID(for: comment, in: index)
            if root == comment.id {
                roots.append(comment)
            } else {
                byParent[root, default: []].append(comment)
            }
        }

        roots.sort { lhs, rhs in
            let left = rank(lhs)
            let right = rank(rhs)
            if left != right { return left > right }
            return (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
        }
        var built: [MovieCommentThread] = []
        for root in roots {
            let replies = (byParent[root.id] ?? []).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            built.append(MovieCommentThread(root: root, replies: replies))
        }
        threads = built
    }

    /// Thứ tự ưu tiên: đang gửi hoặc gửi lỗi (3), được ghim (2), còn lại (1).
    private func rank(_ comment: MovieComment) -> Int {
        if comment.isPending || comment.isFailed { return 3 }
        if comment.isPinned { return 2 }
        return 1
    }

    private func persist() {
        guard !slug.isEmpty else { return }
        LocalCommentStore.save(all.filter { !$0.isPending && !$0.isFailed }, slug: slug)
    }
}

// MARK: - Lưu tạm trên thiết bị

/// Kho nhỏ trên thiết bị, chỉ dùng khi máy chủ chưa có endpoint bình luận.
/// Nội dung nằm trong Application Support, tối đa 300 bình luận mỗi phim.
enum LocalCommentStore {
    private static let folderName = "CinemoraComments"
    private static let cap = 300

    private static func directory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = base.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    private static func fileURL(slug: String) -> URL? {
        let safe = slug
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "..", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safe.isEmpty else { return nil }
        return directory()?.appendingPathComponent("\(safe).json")
    }

    static func load(slug: String) -> [MovieComment] {
        guard let url = fileURL(slug: slug), let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([MovieComment].self, from: data)) ?? []
    }

    static func save(_ comments: [MovieComment], slug: String) {
        guard let url = fileURL(slug: slug) else { return }
        let trimmed = comments.count > cap ? Array(comments.suffix(cap)) : comments
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
