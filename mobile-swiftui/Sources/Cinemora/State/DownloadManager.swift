import Foundation
import UIKit

/// Quản lý phim tải về để xem khi không có wifi.
///
/// Nguồn phim của Cinemora là HLS (`.m3u8`) nên không thể tải bằng một
/// `URLSessionDownloadTask`: phải tải playlist, chọn biến thể chất lượng cao
/// nhất, tải lần lượt từng phân đoạn rồi nối lại thành một tệp `.ts` — định dạng
/// mà `AVPlayer` phát được trực tiếp từ bộ nhớ máy.
///
/// Ghi chú kỹ thuật:
/// - Phân đoạn được tải theo lô 3 và ghi **theo đúng thứ tự**, nhờ vậy tệp tạm
///   luôn là một đoạn phim hợp lệ và có thể tải tiếp từ phân đoạn dang dở.
/// - Playlist có `#EXT-X-KEY` (AES-128) không tải offline được, trạng thái được
///   đánh dấu `unsupported` kèm lời giải thích thay vì tải về một tệp hỏng.
@MainActor
@Observable
final class DownloadManager {
    enum Phase: String, Codable {
        case waiting, downloading, paused, finished, failed, unsupported

        var title: String {
            switch self {
            case .waiting: "Đang chờ"
            case .downloading: "Đang tải"
            case .paused: "Tạm dừng"
            case .finished: "Đã tải xong"
            case .failed: "Lỗi"
            case .unsupported: "Không hỗ trợ"
            }
        }
    }

    struct Item: Identifiable, Codable, Equatable {
        var id: String
        var movieSlug: String
        var movieName: String
        var poster: String?
        var serverName: String
        var episodeName: String
        var episodeSlug: String
        var quality: String?
        var sourceURL: String
        var fileName: String
        var phase: Phase
        var receivedBytes: Int64
        var totalBytes: Int64
        var doneSegments: Int
        var totalSegments: Int
        var message: String?
        var updatedAt: Date
        /// Tổng thời lượng phim (giây) lấy từ các thẻ #EXTINF của playlist.
        var durationSeconds: Double?
        /// Băng thông của biến thể đã chọn (bit/giây) lấy từ #EXT-X-STREAM-INF.
        var bandwidth: Int?
        /// Tốc độ tải trung bình của phiên hiện tại (byte/giây).
        var speed: Double?
        /// Thời điểm bắt đầu tải phiên hiện tại.
        var startedAt: Date?

        var progress: Double {
            if totalSegments > 0 { return min(1, Double(doneSegments) / Double(totalSegments)) }
            if totalBytes > 0 { return min(1, Double(receivedBytes) / Double(totalBytes)) }
            return phase == .finished ? 1 : 0
        }
        var isRunning: Bool { phase == .downloading || phase == .waiting }

        /// Tổng dung lượng ước tính của cả tập phim. Khi đã tải đủ phân đoạn thì
        /// suy ra từ số đo thực tế (chính xác nhất); trước đó dùng băng thông khai
        /// báo trong playlist nhân với tổng thời lượng.
        var estimatedTotalBytes: Int64 {
            if phase == .finished { return max(receivedBytes, 0) }
            let measured: Int64 = (doneSegments >= 3 && receivedBytes > 0 && totalSegments > 0)
                ? Int64(Double(receivedBytes) / Double(doneSegments) * Double(totalSegments))
                : 0
            var declared: Int64 = 0
            if let bandwidth, bandwidth > 0, let durationSeconds, durationSeconds > 0 {
                declared = Int64(Double(bandwidth) / 8 * durationSeconds)
            }
            if measured > 0 && declared > 0 {
                // Playlist tổng có thể khai băng thông gấp nhiều lần thực tế; khi
                // hai con số lệch quá xa thì tin vào số đo.
                return measured > declared * 3 ? measured : max(measured, declared)
            }
            return measured > 0 ? measured : declared
        }

        /// "1,2 GB / 50 GB" — đúng dạng người dùng cần thấy.
        var sizeText: String {
            let done = ByteCountFormatter.string(fromByteCount: max(receivedBytes, 0), countStyle: .file)
            let total = estimatedTotalBytes
            guard total > 0 else { return done }
            return "\(done) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
        }

        var percentText: String { "\(Int((progress * 100).rounded()))%" }

        var speedText: String {
            guard let speed, speed > 0 else { return "" }
            return "\(ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file))/s"
        }

        /// Thời gian còn lại ước tính, chỉ hiện khi đã có số đo tốc độ.
        var etaText: String {
            guard let speed, speed > 0, phase == .downloading else { return "" }
            let remaining = Double(estimatedTotalBytes) - Double(receivedBytes)
            guard remaining > 0 else { return "" }
            let seconds = Int(remaining / speed)
            if seconds < 60 { return "còn <1 phút" }
            if seconds < 3600 { return "còn ~\(seconds / 60) phút" }
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return "còn ~\(hours) giờ \(minutes) phút"
        }

        /// Tệp có sẵn trong máy và đang chờ xoá hay không.
        var canStart: Bool { phase == .paused || phase == .failed || phase == .waiting }
    }

    private(set) var items: [Item] = []
    /// Thông báo cho màn cài đặt khi thư mục đổi hoặc quyền truy cập bị thu hồi.
    var folderMessage: String?

    private var tasks: [String: Task<Void, Never>] = [:]
    /// Số tập tải song song tối đa.
    private let maxConcurrent = 2
    /// Thư mục mặc định nằm trong Documents để hiện được trong app Tệp.
    private let defaultRoot: URL
    /// Nơi lưu danh sách tải xuống (dữ liệu nội bộ, không phải phim).
    private let metadataRoot: URL
    private var customBookmark: Data?
    private var scopedRoot: URL?
    private var storeURL: URL { metadataRoot.appendingPathComponent("downloads.json") }
    private let session: URLSession
    private static let bookmarkKey = "cinemora.downloadFolderBookmark"

    /// Thư mục đang dùng để chứa phim tải về.
    var root: URL { scopedRoot ?? defaultRoot }
    var isUsingDefaultFolder: Bool { scopedRoot == nil }
    var folderName: String { isUsingDefaultFolder ? "Cinemora/Downloads" : root.lastPathComponent }
    var folderPath: String { root.path }

    /// Dung lượng còn trống của thiết bị, hiển thị trong màn cài đặt.
    var freeSpaceText: String {
        let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let free = values?.volumeAvailableCapacityForImportantUsage ?? 0
        guard free > 0 else { return "Không xác định" }
        return ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
    }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        metadataRoot = support.appendingPathComponent("Cinemora", isDirectory: true)
        try? FileManager.default.createDirectory(at: metadataRoot, withIntermediateDirectories: true)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? support
        defaultRoot = documents.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: defaultRoot, withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.httpAdditionalHeaders = ["User-Agent": "Cinemora/1.0 (iOS)"]
        session = URLSession(configuration: configuration)
        customBookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey)
        resolveCustomFolder()
        // Bản cũ lưu trong Application Support — chuyển sang thư mục mặc định mới.
        moveFiles(into: defaultRoot, from: [metadataRoot.appendingPathComponent("Downloads", isDirectory: true)])
        load()
    }

    // MARK: - Thư mục

    /// Người dùng vừa chọn thư mục trong app Tệp.
    func chooseFolder(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            folderMessage = "Không lưu được quyền truy cập vào thư mục này. Hãy chọn thư mục khác."
            return
        }
        let previous = root
        customBookmark = data
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        resolveCustomFolder()
        guard scopedRoot != nil else { return }
        moveFiles(into: root, from: [previous])
        folderMessage = "Đã chuyển thư mục tải xuống sang \u{201C}\(folderName)\u{201D}."
    }

    /// Quay về thư mục mặc định của app.
    func useDefaultFolder() {
        let previous = root
        scopedRoot?.stopAccessingSecurityScopedResource()
        scopedRoot = nil
        customBookmark = nil
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        moveFiles(into: defaultRoot, from: [previous])
        folderMessage = "Đang dùng lại thư mục mặc định của Cinemora."
    }

    /// Mở thư mục hiện tại trong app Tệp.
    ///
    /// `UIApplication.open` **không** mở được URL trỏ tới một thư mục, nên phải
    /// dùng scheme riêng của app Tệp (`shareddocuments://`) kèm đường dẫn.
    func openCurrentFolder() {
        let path = root.path
        let isDefault = isUsingDefaultFolder
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "shareddocuments://" + encoded) else {
            folderMessage = "Không tạo được liên kết tới thư mục này."
            return
        }
        UIApplication.shared.open(url, options: [:]) { [weak self] success in
            guard !success else { return }
            Task { @MainActor in
                self?.folderMessage = isDefault
                    ? "App Tệp không mở trực tiếp được thư mục này. Hãy mở app Tệp → Trên iPhone của tôi → Cinemora → Downloads."
                    : "App Tệp không mở trực tiếp được thư mục này. Hãy mở app Tệp rồi chọn thư mục bạn đã đặt, hoặc bấm “Sao chép đường dẫn” để dán vào ô tìm kiếm."
            }
        }
    }

    /// Sao chép đường dẫn thư mục để người dùng dán vào app Tệp.
    func copyFolderPath() {
        UIPasteboard.general.string = root.path
        folderMessage = "Đã sao chép đường dẫn thư mục."
    }

    /// Tạm dừng mọi bản đang tải.
    func pauseAll() {
        for item in items where item.phase == .downloading || item.phase == .waiting {
            pause(item.id)
        }
    }

    /// Xoá toàn bộ bản đã tải xong (không đụng tới bản đang tải dở).
    func removeFinished() {
        for item in items where item.phase == .finished {
            remove(item.id)
        }
    }

    private func resolveCustomFolder() {
        scopedRoot?.stopAccessingSecurityScopedResource()
        scopedRoot = nil
        guard let bookmark = customBookmark else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else {
            // Quyền bị thu hồi (xoá app Tệp, đổi máy…) — quay về mặc định thay vì
            // để mọi bản tải xuống thất bại trong im lặng.
            customBookmark = nil
            UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
            folderMessage = "Không còn quyền ghi vào thư mục đã chọn, Cinemora đã quay về thư mục mặc định."
            return
        }
        scopedRoot = url
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if stale, let refreshed = try? url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil) {
            customBookmark = refreshed
            UserDefaults.standard.set(refreshed, forKey: Self.bookmarkKey)
        }
    }

    /// Chuyển các tệp phim đã tải sang thư mục mới, bỏ qua tệp đã có ở đích.
    private func moveFiles(into destination: URL, from sources: [URL]) {
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for source in sources where source.standardizedFileURL != destination.standardizedFileURL {
            guard let files = try? FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.pathExtension.lowercased() == "ts" {
                let target = destination.appendingPathComponent(file.lastPathComponent)
                guard !FileManager.default.fileExists(atPath: target.path) else { continue }
                try? FileManager.default.moveItem(at: file, to: target)
            }
        }
    }

    // MARK: - Truy vấn

    func item(movieSlug: String, episodeSlug: String) -> Item? {
        items.first { $0.movieSlug == movieSlug && $0.episodeSlug == episodeSlug }
    }

    func item(id: String) -> Item? { items.first { $0.id == id } }

    /// Tra mục tải xuống theo tên tệp trong thư mục.
    func item(fileName: String) -> Item? { items.first { $0.fileName == fileName } }

    /// Tệp đã tải xong của một tập, dùng để phát offline.
    func localURL(movieSlug: String, episodeSlug: String) -> URL? {
        guard let item = item(movieSlug: movieSlug, episodeSlug: episodeSlug),
              item.phase == .finished else { return nil }
        let url = root.appendingPathComponent(item.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var finishedCount: Int { items.filter { $0.phase == .finished }.count }
    var activeCount: Int { items.filter(\.isRunning).count }
    var totalBytes: Int64 { items.filter { $0.phase == .finished }.reduce(0) { $0 + max($1.receivedBytes, 0) } }
    var totalSizeText: String { ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file) }

    // MARK: - Hàng đợi

    @discardableResult
    func enqueue(movie: Movie, serverName: String, episode: MovieEpisode, quality: String? = nil) -> Item? {
        guard let url = episode.playbackURL else { return nil }
        let slug = episode.slug.isEmpty ? episode.name : episode.slug
        let id = "\(movie.slug)|\(serverName)|\(slug)"
        if let index = items.firstIndex(where: { $0.id == id }) {
            if items[index].phase != .finished { start(id) }
            return items[index]
        }
        let safeName = Self.fileName(movie: movie.slug, episode: slug)
        let item = Item(
            id: id,
            movieSlug: movie.slug,
            movieName: movie.name,
            poster: movie.poster,
            serverName: serverName,
            episodeName: episode.name,
            episodeSlug: slug,
            quality: quality,
            sourceURL: url.absoluteString,
            fileName: safeName,
            phase: .waiting,
            receivedBytes: 0,
            totalBytes: 0,
            doneSegments: 0,
            totalSegments: 0,
            message: nil,
            updatedAt: Date()
        )
        items.insert(item, at: 0)
        save()
        start(id)
        return item
    }

    func start(_ id: String) {
        guard tasks[id] == nil, let item = item(id: id), item.phase != .finished else { return }
        // Tải cả bộ phim có thể là hàng chục tập: chỉ chạy vài tập cùng lúc để
        // không nghẽn mạng và không hao pin, phần còn lại xếp hàng chờ.
        guard tasks.count < maxConcurrent else {
            mutate(id) { if $0.phase == .downloading { $0.phase = .waiting } }
            save()
            return
        }
        mutate(id) { $0.phase = .downloading; $0.message = nil }
        tasks[id] = Task { [weak self] in
            await self?.run(id)
            guard let self else { return }
            self.tasks[id] = nil
            self.pump()
        }
    }

    /// Mở khoá hàng đợi: chạy tiếp các mục đang chờ khi có chỗ trống.
    private func pump() {
        for item in items where item.phase == .waiting {
            if tasks.count >= maxConcurrent { break }
            start(item.id)
        }
    }

    /// Đánh dấu tạm dừng mà không báo lỗi, giữ nguyên phân đoạn đã tải.
    private func markPaused(_ id: String) {
        mutate(id) {
            if $0.phase == .downloading || $0.phase == .waiting {
                $0.phase = .paused
                $0.message = nil
            }
        }
        save()
    }

    func pause(_ id: String) {
        // Đổi trạng thái trước khi huỷ để tác vụ đang chạy không ghi đè thành lỗi.
        markPaused(id)
        tasks[id]?.cancel()
        tasks[id] = nil
    }

    /// Tải tiếp đúng tiến trình đang dừng: tệp tạm đã có sẵn các phân đoạn đầu
    /// nên chỉ tải những phân đoạn còn lại.
    func retry(_ id: String) {
        mutate(id) { $0.phase = .waiting; $0.message = nil }
        start(id)
    }

    /// Xoá một bản tải xuống: **xoá luôn tệp phim trong thư mục tải xuống**,
    /// người dùng không phải xoá thủ công lần nữa.
    ///
    /// Nếu tệp không xoá được (thường là do mất quyền truy cập thư mục đã chọn)
    /// thì mục được giữ lại kèm lời báo, thay vì biến mất khỏi danh sách trong khi
    /// tệp vẫn còn chiếm dung lượng máy.
    func remove(_ id: String) {
        guard let item = item(id: id) else { return }
        tasks[id]?.cancel()
        tasks[id] = nil
        let file = root.appendingPathComponent(item.fileName)
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
        } catch {
            mutate(id) { $0.message = "Không xoá được tệp trong thư mục tải xuống. Hãy kiểm tra quyền truy cập thư mục rồi thử lại." }
            save()
            return
        }
        items.removeAll { $0.id == id }
        save()
    }

    /// Xoá tệp trực tiếp theo đường dẫn (dùng cho trình duyệt tệp).
    @discardableResult
    func deleteFile(at url: URL) -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            if let item = item(fileName: url.lastPathComponent) { remove(item.id) }
            return true
        } catch {
            return false
        }
    }

    /// Tải cả một nguồn: dùng cho nút "Tải tất cả" trong danh sách tập.
    func enqueueAll(movie: Movie, serverName: String, episodes: [MovieEpisode]) {
        for episode in episodes { enqueue(movie: movie, serverName: serverName, episode: episode) }
    }

    // MARK: - Tải

    private func run(_ id: String) async {
        guard let start = item(id: id), let url = URL(string: start.sourceURL) else { return }
        do {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let session = self.session
            let playlist = try await Self.text(from: try await Self.fetch(url, session: session))
            let resolved = try await Self.resolvePlaylist(playlist, base: url, fetch: { try await Self.fetch($0, session: session) })
            if resolved.encrypted {
                mutate(id) { $0.phase = .unsupported; $0.message = "Nguồn này mã hoá AES-128 nên không tải offline được." }
                save()
                return
            }
            guard !resolved.segments.isEmpty else { throw DownloadError.empty }

            let fileURL = root.appendingPathComponent(start.fileName)
            var written = start.doneSegments
            var bytes = start.receivedBytes
            // Tệp cũ đã có sẵn `doneSegments` phân đoạn đầu, ghi tiếp vào cuối tệp.
            if written == 0 {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
                bytes = 0
            }
            guard let handle = try? FileHandle(forWritingTo: fileURL) else { throw DownloadError.storage }
            defer { try? handle.close() }
            try handle.seekToEnd()

            mutate(id) {
                $0.phase = .downloading
                $0.totalSegments = resolved.segments.count
                $0.doneSegments = written
                $0.receivedBytes = bytes
                $0.durationSeconds = resolved.duration > 0 ? resolved.duration : $0.durationSeconds
                $0.bandwidth = resolved.bandwidth > 0 ? resolved.bandwidth : $0.bandwidth
                $0.startedAt = Date()
                $0.speed = nil
            }

            var index = written
            while index < resolved.segments.count {
                try Task.checkCancellation()
                let end = min(index + 3, resolved.segments.count)
                let batch = Array(resolved.segments[index..<end])
                let datas = try await withThrowingTaskGroup(of: (Int, Data).self) { group -> [(Int, Data)] in
                    for (offset, segment) in batch.enumerated() {
                        group.addTask { (offset, try await DownloadManager.fetch(segment, session: session)) }
                    }
                    var collected: [(Int, Data)] = []
                    for try await value in group { collected.append(value) }
                    return collected.sorted { $0.0 < $1.0 }
                }
                for (_, data) in datas {
                    try handle.write(contentsOf: data)
                    bytes += Int64(data.count)
                    index += 1
                }
                mutate(id) {
                    $0.doneSegments = index
                    $0.receivedBytes = bytes
                    $0.totalBytes = max($0.totalBytes, bytes)
                    if let started = $0.startedAt {
                        let elapsed = Date().timeIntervalSince(started)
                        if elapsed > 1 { $0.speed = Double(bytes) / elapsed }
                    }
                }
                save()
            }

            mutate(id) {
                $0.phase = .finished
                $0.doneSegments = resolved.segments.count
                $0.totalSegments = resolved.segments.count
                $0.receivedBytes = bytes
                $0.totalBytes = bytes
                $0.message = nil
            }
            save()
        } catch is CancellationError {
            // Người dùng bấm Dừng: giữ nguyên tiến trình, không phải lỗi.
            markPaused(id)
        } catch let error as URLError where error.code == .cancelled {
            // URLSession huỷ tác vụ giữa chừng cũng là do bấm Dừng.
            markPaused(id)
        } catch {
            mutate(id) {
                // Tác vụ có thể kết thúc sau khi người dùng đã bấm Dừng; lúc đó
                // trạng thái đã là "Tạm dừng" và không được ghi đè thành lỗi.
                if $0.phase == .paused { return }
                $0.phase = .failed
                $0.message = (error as? LocalizedError)?.errorDescription ?? "Tải thất bại. Kiểm tra kết nối rồi thử lại."
            }
            save()
        }
    }

    /// Hàm tĩnh, chỉ nhận `URLSession` (Sendable) nên tác vụ tải chạy ngoài
    /// main actor — giao diện không bị ảnh hưởng khi tải nhiều phân đoạn.
    nonisolated private static func fetch(_ url: URL, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DownloadError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }

    // MARK: - Playlist

    private struct ResolvedPlaylist {
        var segments: [URL]
        var encrypted: Bool
        /// Tổng thời lượng (giây) tính từ các thẻ #EXTINF.
        var duration: Double
        /// Băng thông biến thể đã chọn (bit/giây), 0 nếu playlist không khai.
        var bandwidth: Int
    }

    /// Trả về danh sách phân đoạn. Nếu là playlist tổng (có `#EXT-X-STREAM-INF`)
    /// thì chọn biến thể băng thông cao nhất rồi đọc tiếp playlist đó.
    nonisolated private static func resolvePlaylist(
        _ text: String,
        base: URL,
        fetch: (URL) async throws -> Data
    ) async throws -> ResolvedPlaylist {
        var body = text
        var currentBase = base
        var depth = 0
        var bandwidth = 0
        while body.contains("#EXT-X-STREAM-INF") && depth < 3 {
            guard let variant = bestVariant(in: body, base: currentBase) else { break }
            bandwidth = max(bandwidth, Self.variantBandwidth(in: body, base: currentBase))
            body = try await Self.text(from: try await fetch(variant))
            currentBase = variant
            depth += 1
        }
        let duration = body.split(separator: "\n").reduce(0.0) { total, rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("#EXTINF") else { return total }
            let value = line.dropFirst("#EXTINF:".count).split(separator: ",").first ?? ""
            return total + (Double(value.trimmingCharacters(in: .whitespaces)) ?? 0)
        }
        let encrypted = body.split(separator: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("#EXT-X-KEY") && !trimmed.contains("METHOD=NONE")
        }
        var segments: [URL] = []
        for rawLine in body.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if let url = URL(string: line, relativeTo: currentBase)?.absoluteURL { segments.append(url) }
        }
        return ResolvedPlaylist(segments: segments, encrypted: encrypted, duration: duration, bandwidth: bandwidth)
    }

    /// Băng thông của biến thể tốt nhất trong playlist tổng.
    nonisolated private static func variantBandwidth(in text: String, base: URL) -> Int {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        var best = 0
        for (index, line) in lines.enumerated() where line.hasPrefix("#EXT-X-STREAM-INF") {
            guard index + 1 < lines.count, !lines[index + 1].hasPrefix("#") else { continue }
            best = max(best, Int(attribute("BANDWIDTH", in: line) ?? "") ?? 0)
        }
        return best
    }

    /// Biến thể có BANDWIDTH lớn nhất — tương ứng chất lượng cao nhất có sẵn.
    nonisolated private static func bestVariant(in text: String, base: URL) -> URL? {
        var best: (bandwidth: Int, url: URL)?
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        for (index, line) in lines.enumerated() where line.hasPrefix("#EXT-X-STREAM-INF") {
            let bandwidth = Int(Self.attribute("BANDWIDTH", in: line) ?? "") ?? 0
            guard index + 1 < lines.count else { continue }
            let next = lines[index + 1]
            guard !next.hasPrefix("#"), let url = URL(string: next, relativeTo: base)?.absoluteURL else { continue }
            if best == nil || bandwidth > best!.bandwidth { best = (bandwidth, url) }
        }
        return best?.url
    }

    nonisolated private static func attribute(_ name: String, in line: String) -> String? {
        guard let range = line.range(of: "\(name)=") else { return nil }
        let rest = line[range.upperBound...]
        return rest.split(separator: ",").first.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
    }

    nonisolated private static func text(from data: Data) throws -> String {
        guard let value = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw DownloadError.playlist
        }
        return value
    }

    // MARK: - Lưu trữ

    private func mutate(_ id: String, _ change: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        items[index].updatedAt = Date()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let stored = try? JSONDecoder().decode([Item].self, from: data) else { return }
        // Tác vụ tải không sống qua lần khởi động app, nên việc dang dở chuyển
        // thành tạm dừng để người dùng bấm tiếp tục.
        items = stored.map { item in
            var copy = item
            if copy.phase == .downloading || copy.phase == .waiting { copy.phase = .paused }
            return copy
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private enum DownloadError: LocalizedError {
        case empty, storage, playlist, http(Int)

        var errorDescription: String? {
            switch self {
            case .empty: "Nguồn phim không có phân đoạn nào để tải."
            case .storage: "Không ghi được vào bộ nhớ máy."
            case .playlist: "Không đọc được danh sách phân đoạn của nguồn phim."
            case .http(let code): code == 404 ? "Nguồn phim đã hết hạn, hãy chọn nguồn khác." : "Máy chủ nguồn phim trả lỗi \(code)."
            }
        }
    }

    private static func fileName(movie: String, episode: String) -> String {
        let raw = "\(movie)-\(episode)"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(cleaned).prefix(120) + ".ts"
    }
}
