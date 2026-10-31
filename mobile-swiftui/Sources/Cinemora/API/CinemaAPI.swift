import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Security)
import Security
#endif

struct CinemaAPI {
    static let shared = CinemaAPI()
    static let baseURL = URL(string: (Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String) ?? "https://cungcapicloud.id.vn")!

    /// Máy chủ bình luận. Bỏ trống trong Info.plist thì dùng luôn máy chủ chính —
    /// như vậy app hoạt động đúng cả khi backend chính tự thêm procedure bình luận,
    /// lẫn khi bình luận được chạy như một dịch vụ riêng trên hosting.
    static let commentsBaseURL: URL = {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "COMMENTS_API_BASE_URL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty, let url = URL(string: raw), url.host != nil else { return baseURL }
        return url
    }()

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.httpCookieStorage = HTTPCookieStorage.shared
            configuration.httpShouldSetCookies = true
            self.session = URLSession(configuration: configuration)
        }
    }

    /// Cookie phiên của máy chủ chính, gửi kèm khi gọi máy chủ bình luận ở tên miền
    /// khác. Máy chủ bình luận dùng chính cookie này để biết ai đang gửi.
    private static func forwardedSessionCookie(for host: URL) -> String? {
        guard let domain = host.host?.lowercased() else { return nil }
        let cookies = HTTPCookieStorage.shared.cookies ?? []
        let matched = cookies.filter { cookie in
            let cookieDomain = cookie.domain.lowercased().hasPrefix(".")
                ? String(cookie.domain.lowercased().dropFirst())
                : cookie.domain.lowercased()
            guard !cookieDomain.isEmpty else { return false }
            return domain == cookieDomain || domain.hasSuffix("." + cookieDomain)
        }
        guard !matched.isEmpty else { return nil }
        return matched.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    private var deviceId: String {
        let key = "app.serval4238.cinemora.account.device.id.v2"
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key,
            kSecAttrAccount as String: "device",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8),
           !value.isEmpty { return value }
        #endif
        let value = UserDefaults.standard.string(forKey: "cinemora.account.device.id.v1") ?? UUID().uuidString
        #if canImport(Security)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key,
            kSecAttrAccount as String: "device",
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(attributes as CFDictionary, nil)
        UserDefaults.standard.removeObject(forKey: "cinemora.account.device.id.v1")
        #endif
        return value
    }

    private var deviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "Cinemora SwiftUI"
        #endif
    }

    static func absoluteURL(_ value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    /// DHCN requires a baothanhhoa.vn Origin/Referer and cannot be opened
    /// directly by AVPlayer. The server proxy adds those headers and rewrites
    /// the playlist's key and segment URLs as well.
    static func tvStreamURL(_ value: String?) -> URL? {
        guard let absolute = absoluteURL(value),
              let host = absolute.host?.lowercased(),
              host == "d4.dhcn.vn" || host == "media.dhcn.vn" else {
            return absoluteURL(value)
        }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/tv/proxy"
        components?.queryItems = [URLQueryItem(name: "url", value: absolute.absoluteString)]
        return components?.url
    }

    /// Master playlist bọc link M3U8 kèm phụ đề rời.
    ///
    /// AVFoundation chỉ đưa phụ đề vào PiP khi phụ đề nằm trong media của
    /// AVPlayerItem, mà phụ đề rời (.vtt) thì không. Bọc bằng EXT-X-MEDIA để
    /// trình phát có nhóm phụ đề hợp lệ.
    static func subtitledPlaylistURL(video: URL, subtitle: URL) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/cinema/subtitled.m3u8"
        components?.queryItems = [
            URLQueryItem(name: "video", value: video.absoluteString),
            URLQueryItem(name: "sub", value: subtitle.absoluteString),
        ]
        return components?.url
    }

    func home(page: Int = 1) async throws -> MoviePage {
        try await query("cinema.home", input: ["page": page])
    }

    func dailyUpdates(page: Int = 1) async throws -> MoviePage {
        try await query("cinema.dailyUpdates", input: ["page": page])
    }

    func list(
        page: Int = 1,
        kind: String = "latest",
        category: String? = nil,
        country: String? = nil,
        year: Int? = nil,
        kinds: [String] = [],
        categories: [String] = [],
        countries: [String] = [],
        years: [Int] = []
    ) async throws -> MoviePage {
        let serverKind = kind == "ongoing" || kind == "completed" ? "series" : kind
        var input: [String: Any] = ["page": page, "kind": serverKind]
        if let category, !category.isEmpty { input["category"] = category }
        if let country, !country.isEmpty { input["country"] = country }
        if let year { input["year"] = year }
        // Bộ lọc nhiều lựa chọn: máy chủ gộp kết quả của từng tổ hợp.
        if !kinds.isEmpty { input["kinds"] = kinds }
        if !categories.isEmpty { input["categories"] = categories }
        if !countries.isEmpty { input["countries"] = countries }
        if !years.isEmpty { input["years"] = years }
        let pageResult: MoviePage = try await query("cinema.list", input: input)
        guard kind == "ongoing" || kind == "completed" else { return pageResult }
        let items = kind == "completed" ? pageResult.items.filter(isCompletedSeries) : pageResult.items.filter { !isCompletedSeries($0) }
        return MoviePage(items: items, pagination: pageResult.pagination)
    }

    func search(_ keyword: String) async throws -> MoviePage {
        try await query("cinema.search", input: ["keyword": keyword, "page": 1])
    }

    func detail(slug: String) async throws -> Movie {
        try await query("cinema.detail", input: ["slug": slug])
    }

    /// Đếm số phim của từng lựa chọn lọc (thể loại / quốc gia / năm) theo bộ lọc đang bật.
    func filterCounts(
        dimension: String,
        options: [String],
        kind: String = "latest",
        kinds: [String] = [],
        categories: [String] = [],
        countries: [String] = [],
        years: [Int] = []
    ) async throws -> [String: Int] {
        guard !options.isEmpty else { return [:] }
        let serverKind = kind == "ongoing" || kind == "completed" ? "series" : kind
        var input: [String: Any] = ["kind": serverKind, "dimension": dimension, "options": options]
        if !kinds.isEmpty { input["kinds"] = kinds }
        if !categories.isEmpty { input["categories"] = categories }
        if !countries.isEmpty { input["countries"] = countries }
        if !years.isEmpty { input["years"] = years }
        return try await query("cinema.filterCounts", input: input)
    }

    func meta() async throws -> CatalogMeta {
        try await query("cinema.meta", input: nil)
    }

    func tvStreams() async throws -> [TvStream] {
        try await query("tv.list", input: nil)
    }

    func tvVideos() async throws -> [TvVideo] {
        try await query("tv.videos", input: ["refresh": Int(Date().timeIntervalSince1970 * 1000)])
    }

    func tvEventBytes() async throws -> URLSession.AsyncBytes {
        var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/api/tv/events"
        guard let url = components.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 0
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return bytes
    }

    func submitMovieRequest(title: String, link: String?, priority: String, notes: String?, imageData: Data?, imageMimeType: String?) async throws {
        var input: [String: Any] = ["title": title, "priority": priority]
        if let link, !link.isEmpty { input["link"] = link }
        if let notes, !notes.isEmpty { input["notes"] = notes }
        if let imageData {
            input["imageBase64"] = imageData.base64EncodedString()
            input["imageMimeType"] = imageMimeType ?? "image/jpeg"
        }
        let _: MovieRequestResponse = try await mutate("cinema.submitRequest", input: input)
    }

    /// Lịch sử chỉ tồn tại với tài khoản đã đăng nhập; khách không gọi endpoint này.
    func movieRequestHistory() async throws -> [RemoteMovieRequest] {
        try await query("cinema.myRequests", input: nil)
    }

    // MARK: - Bình luận

    func comments(slug: String) async throws -> MovieCommentFeed {
        try await query("cinema.comments", input: ["slug": slug], base: Self.commentsBaseURL)
    }

    /// Chờ bình luận mới. Máy chủ giữ kết nối tối đa 25 giây và trả về ngay khi có
    /// thay đổi, nên bình luận của người khác hiện lên gần như tức thì.
    func watchComments(slug: String, since: Int) async throws -> MovieCommentFeed {
        try await query("cinema.watchComments", input: ["slug": slug, "since": since], base: Self.commentsBaseURL)
    }

    func setAvatar(dataUrl: String) async throws {
        let _: SuccessResponse = try await mutate("account.setAvatar", input: ["dataUrl": dataUrl])
    }

    func clearAvatar() async throws {
        let _: SuccessResponse = try await mutate("account.clearAvatar", input: [:])
    }

    func addComment(slug: String, content: String, parentID: String?) async throws -> MovieComment? {
        var input: [String: Any] = ["slug": slug, "content": content]
        if let parentID, !parentID.isEmpty { input["parentId"] = parentID }
        let response: MovieCommentEnvelope = try await mutate("cinema.addComment", input: input, base: Self.commentsBaseURL)
        return response.comment
    }

    func deleteComment(slug: String, id: String) async throws {
        let _: SuccessResponse = try await mutate("cinema.deleteComment", input: ["slug": slug, "id": id], base: Self.commentsBaseURL)
    }

    func me() async throws -> RemoteOptionalUser { try await query("auth.me", input: nil) }

    func register(name: String, email: String, password: String) async throws -> RemoteAccountUser {
        let response: RemoteAuthResponse = try await mutate("auth.register", input: ["name": name, "email": email, "password": password, "deviceId": deviceId, "deviceName": deviceName])
        return response.user
    }

    func login(email: String, password: String) async throws -> RemoteAccountUser {
        let response: RemoteAuthResponse = try await mutate("auth.login", input: ["email": email, "password": password, "deviceId": deviceId, "deviceName": deviceName])
        return response.user
    }

    func createQrLogin() async throws -> RemoteQrChallenge {
        try await mutate("auth.qrCreate", input: ["deviceId": deviceId, "deviceName": deviceName])
    }

    func qrLoginStatus(nonce: String) async throws -> RemoteQrStatus {
        try await query("auth.qrStatus", input: ["nonce": nonce])
    }

    func approveQrLogin(nonce: String, approved: Bool) async throws -> RemoteQrStatus {
        try await mutate("auth.qrApprove", input: ["nonce": nonce, "approved": approved])
    }

    func completeQrLogin(nonce: String) async throws -> RemoteAccountUser {
        let response: RemoteAuthResponse = try await mutate("auth.qrComplete", input: ["nonce": nonce, "deviceId": deviceId, "deviceName": deviceName])
        return response.user
    }

    func logout() async throws { let _: SuccessResponse = try await mutate("auth.logout", input: [:]) }
    func changePassword(currentPassword: String, newPassword: String) async throws {
        let _: SuccessResponse = try await mutate("account.changePassword", input: ["currentPassword": currentPassword, "newPassword": newPassword])
    }

    func accountDevices() async throws -> [RemoteAccountDevice] { try await query("account.devices", input: nil) }
    func isCurrentDevice(_ remoteDeviceId: String) -> Bool { remoteDeviceId == deviceId }
    func logoutDevice(id: Int) async throws { let _: SuccessResponse = try await mutate("account.logoutDevice", input: ["id": id]) }
    func logoutAllDevices() async throws { let _: SuccessResponse = try await mutate("account.logoutAll", input: [:]) }

    func accountFavorites() async throws -> [RemoteFavorite] { try await query("account.favorites", input: nil) }
    func accountHistory() async throws -> [RemoteHistory] { try await query("account.history", input: nil) }

    func accountSubtitlePreferences() async throws -> SubtitlePreferences? {
        let payload: AccountSubtitlePreferencesPayload? = try await query("account.getSubtitlePreferences", input: nil)
        return payload?.localValue
    }

    func setAccountSubtitlePreferences(_ preferences: SubtitlePreferences) async throws {
        let payload = AccountSubtitlePreferencesPayload(preferences)
        let encoded = try JSONEncoder().encode(payload)
        guard let input = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        let _: SuccessResponse = try await mutate("account.setSubtitlePreferences", input: input)
    }

    // MARK: - Chat riêng tài khoản đặc quyền

    func specialChatMessages(afterId: Int? = nil) async throws -> [RemoteSpecialChatMessage] {
        var input: [String: Any]? = nil
        if let afterId { input = ["afterId": afterId] }
        return try await query("account.specialChatMessages", input: input)
    }

    func sendSpecialChatMessage(text: String?, attachmentId: Int?, clientRequestId: String? = nil) async throws -> RemoteSpecialChatMessage {
        var input: [String: Any] = [:]
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { input["text"] = text }
        if let attachmentId { input["attachmentId"] = attachmentId }
        if let clientRequestId, !clientRequestId.isEmpty { input["clientRequestId"] = clientRequestId }
        return try await mutate("account.sendSpecialChatMessage", input: input)
    }

    func uploadSpecialChatMedia(data: Data, filename: String, mimeType: String, mediaWidth: Int? = nil, mediaHeight: Int? = nil) async throws -> RemoteSpecialChatMedia {
        var input: [String: Any] = [
            "base64": data.base64EncodedString(),
            "filename": filename,
            "mimeType": mimeType,
        ]
        if let mediaWidth, let mediaHeight {
            input["mediaWidth"] = mediaWidth
            input["mediaHeight"] = mediaHeight
        }
        return try await mutate("account.uploadSpecialChatMedia", input: input, timeoutInterval: 90)
    }

    /// Lấy tệp chat từ route bảo vệ; backend xác nhận quyền sở hữu trước khi
    /// chuyển hướng ngắn hạn tới vùng lưu trữ media.
    func specialChatMediaData(path: String) async throws -> Data {
        guard let url = URL(string: path, relativeTo: Self.baseURL)?.absoluteURL,
              url.host?.lowercased() == Self.baseURL.host?.lowercased() else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 50)
        request.httpShouldHandleCookies = true
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("image/*, video/*, application/octet-stream", forHTTPHeaderField: "Accept")
        if let cookie = Self.forwardedSessionCookie(for: Self.baseURL) {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        for attempt in 0...2 {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
                guard (200..<300).contains(http.statusCode) else {
                    if attempt < 2, http.statusCode >= 500 {
                        try await Task.sleep(for: .milliseconds(350 * (attempt + 1)))
                        continue
                    }
                    throw APIError.http(http.statusCode)
                }
                let responseType = (http.value(forHTTPHeaderField: "Content-Type") ?? "")
                    .split(separator: ";", maxSplits: 1).first.map(String.init)?.lowercased() ?? ""
                guard !data.isEmpty,
                      responseType != "text/html",
                      responseType != "application/json",
                      responseType != "text/plain" else {
                    throw APIError.invalidResponse
                }
                return data
            } catch {
                guard attempt < 2, Self.isRetryableMediaError(error) else { throw error }
                try await Task.sleep(for: .milliseconds(350 * (attempt + 1)))
            }
        }
        throw APIError.invalidResponse
    }

    private static func isRetryableMediaError(_ error: Error) -> Bool {
        if let apiError = error as? APIError {
            if case .http(let status) = apiError { return status >= 500 }
            return false
        }
        if let urlError = error as? URLError {
            return [.timedOut, .networkConnectionLost, .notConnectedToInternet,
                    .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(urlError.code)
        }
        return false
    }

    func addFavorite(movie: Movie) async throws {
        let _: SuccessResponse = try await mutate("account.addFavorite", input: movieSnapshot(movie))
    }

    func removeFavorite(slug: String) async throws {
        let _: SuccessResponse = try await mutate("account.removeFavorite", input: ["movieSlug": slug])
    }

    func recordHistory(movie: Movie, episode: MovieEpisode?, watchedSeconds: Double = 0, durationSeconds: Double = 0) async throws {
        var input = movieSnapshot(movie)
        input["episodeSlug"] = episode?.slug
        input["episodeName"] = episode?.name
        input["watchedSeconds"] = Int(watchedSeconds)
        input["durationSeconds"] = Int(durationSeconds)
        let _: SuccessResponse = try await mutate("account.recordHistory", input: input)
    }

    func removeHistory(slug: String, episodeSlug: String?) async throws {
        var input: [String: Any] = ["movieSlug": slug]
        if let episodeSlug { input["episodeSlug"] = episodeSlug }
        let _: SuccessResponse = try await mutate("account.removeHistory", input: input)
    }

    func clearHistory() async throws { let _: SuccessResponse = try await mutate("account.clearHistory", input: [:]) }

    private func movieSnapshot(_ movie: Movie) -> [String: Any] {
        var input: [String: Any] = ["movieSlug": movie.slug, "movieName": movie.name]
        if let originName = movie.originName { input["originName"] = originName }
        if let poster = movie.poster { input["posterUrl"] = poster }
        if let year = movie.year { input["year"] = year }
        return input
    }

    private func query<T: Decodable>(_ procedure: String, input: [String: Any]?, base: URL = CinemaAPI.baseURL) async throws -> T {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.path = "/api/trpc/\(procedure)"
        if let input {
            let inputData = try JSONSerialization.data(withJSONObject: ["json": input], options: [.sortedKeys])
            components.queryItems = [URLQueryItem(name: "input", value: String(data: inputData, encoding: .utf8))]
        }
        guard let url = components.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue(deviceId, forHTTPHeaderField: "X-Cinemora-Device-Id")
        request.setValue(deviceName, forHTTPHeaderField: "X-Cinemora-Device-Name")
        let cookieHost = base == CinemaAPI.baseURL ? base : CinemaAPI.baseURL
        if let cookie = Self.forwardedSessionCookie(for: cookieHost) {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let root = try JSONSerialization.jsonObject(with: data)
        guard let envelope = root as? [String: Any] else { throw APIError.invalidResponse }
        if let error = envelope["error"] as? [String: Any],
           let message = (error["json"] as? [String: Any])?["message"] as? String {
            throw APIError.server(message)
        }
        let result = envelope["result"] as? [String: Any]
        let resultData = result?["data"] as? [String: Any]
        let payload = resultData?["json"] ?? resultData?["data"] ?? envelope
        if payload is NSNull {
            do { return try JSONDecoder().decode(T.self, from: Data("null".utf8)) }
            catch { throw APIError.decoding(error.localizedDescription) }
        }
        guard JSONSerialization.isValidJSONObject(payload) else { throw APIError.invalidResponse }
        let decodedData = try JSONSerialization.data(withJSONObject: payload)
        do { return try JSONDecoder().decode(T.self, from: decodedData) }
        catch { throw APIError.decoding(error.localizedDescription) }
    }

    private func mutate<T: Decodable>(_ procedure: String, input: [String: Any], base: URL = CinemaAPI.baseURL, timeoutInterval: TimeInterval = 12) async throws -> T {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.path = "/api/trpc/\(procedure)"
        guard let url = components.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Cinemora-Device-Id")
        request.setValue(deviceName, forHTTPHeaderField: "X-Cinemora-Device-Name")
        request.timeoutInterval = timeoutInterval
        let cookieHost = base == CinemaAPI.baseURL ? base : CinemaAPI.baseURL
        if let cookie = Self.forwardedSessionCookie(for: cookieHost) {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["json": input], options: [.sortedKeys])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = root["error"] as? [String: Any],
               let message = (error["json"] as? [String: Any])?["message"] as? String {
                throw APIError.server(message)
            }
            throw APIError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let root = try JSONSerialization.jsonObject(with: data)
        guard let envelope = root as? [String: Any] else { throw APIError.invalidResponse }
        if let error = envelope["error"] as? [String: Any],
           let message = (error["json"] as? [String: Any])?["message"] as? String {
            throw APIError.server(message)
        }
        let result = envelope["result"] as? [String: Any]
        let resultData = result?["data"] as? [String: Any]
        let payload = resultData?["json"] ?? resultData?["data"] ?? envelope
        if payload is NSNull {
            do { return try JSONDecoder().decode(T.self, from: Data("null".utf8)) }
            catch { throw APIError.decoding(error.localizedDescription) }
        }
        guard JSONSerialization.isValidJSONObject(payload) else { throw APIError.invalidResponse }
        let decodedData = try JSONSerialization.data(withJSONObject: payload)
        do { return try JSONDecoder().decode(T.self, from: decodedData) }
        catch { throw APIError.decoding(error.localizedDescription) }
    }

    private func isCompletedSeries(_ movie: Movie) -> Bool {
        let marker = "\(movie.status ?? "") \(movie.episodeCurrent ?? "")"
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
        if marker.contains("hoan tat") || marker.contains("hoan thanh") || marker.contains("full") || marker.contains("completed") || marker.contains("complete") || marker.contains("end") {
            return true
        }
        if let total = movie.episodeTotal, let current = movie.episodeCurrent,
           let last = current.split(whereSeparator: { !$0.isNumber }).compactMap({ Int($0) }).last {
            return last >= total
        }
        return false
    }
}

private struct MovieRequestResponse: Decodable {
    let success: Bool
}

private struct AccountSubtitlePreferencesPayload: Codable {
    var enabled: Bool
    var fontName: String
    var bold: Bool
    var fontSize: Double
    var bottomSpacing: Double
    var alignment: String
    var textColorHex: String
    var outlineColorHex: String
    var outlineWidth: Double
    var bilingual: Bool
    var backgroundEnabled: Bool
    var backgroundColorHex: String
    var backgroundOpacity: Double
    var backgroundCornerRadius: Double
    var letterSpacing: Double
    var lineSpacing: Double

    init(_ local: SubtitlePreferences) {
        enabled = local.enabled
        fontName = local.fontName
        bold = local.bold
        fontSize = local.fontSize
        bottomSpacing = local.bottomSpacing
        switch local.alignment {
        case "Trái", "left": alignment = "left"
        case "Phải", "right": alignment = "right"
        default: alignment = "center"
        }
        textColorHex = local.textColorHex
        outlineColorHex = local.outlineColorHex
        outlineWidth = local.outlineWidth
        bilingual = local.bilingual
        backgroundEnabled = local.backgroundEnabled
        backgroundColorHex = local.backgroundColorHex
        backgroundOpacity = local.backgroundOpacity
        backgroundCornerRadius = local.cornerRadius
        letterSpacing = local.letterSpacing
        lineSpacing = local.lineSpacing
    }

    var localValue: SubtitlePreferences {
        var local = SubtitlePreferences()
        local.enabled = enabled
        local.fontName = fontName
        local.bold = bold
        local.fontSize = fontSize
        local.bottomSpacing = bottomSpacing
        switch alignment {
        case "left": local.alignment = "Trái"
        case "right": local.alignment = "Phải"
        default: local.alignment = "Giữa"
        }
        local.textColorHex = textColorHex
        local.outlineColorHex = outlineColorHex
        local.outlineWidth = outlineWidth
        local.bilingual = bilingual
        local.backgroundEnabled = backgroundEnabled
        local.backgroundColorHex = backgroundColorHex
        local.backgroundOpacity = backgroundOpacity
        local.cornerRadius = backgroundCornerRadius
        local.letterSpacing = letterSpacing
        local.lineSpacing = lineSpacing
        return local
    }
}

enum APIError: LocalizedError {
    case invalidURL, invalidResponse
    case rateLimited(seconds: Int)
    case http(Int)
    case server(String)
    case decoding(String)

    var isUnauthorized: Bool {
        switch self {
        case .http(let code): return code == 401
        case .server(let message): return message.contains("401") || message.localizedCaseInsensitiveContains("unauthorized") || message.localizedCaseInsensitiveContains("unauthenticated")
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Địa chỉ API không hợp lệ."
        case .invalidResponse: return "Máy chủ trả về dữ liệu chưa đúng định dạng."
        case .rateLimited(let seconds): return "Bạn thao tác quá nhanh. Vui lòng thử lại sau khoảng \(max(1, seconds)) giây."
        case .http(let code): return "Máy chủ phản hồi lỗi (\(code)). Vui lòng thử lại."
        case .server(let message): return Self.friendlyServerMessage(message)
        case .decoding(let message): return "Không đọc được dữ liệu phim: \(message)"
        }
    }

    private static func friendlyServerMessage(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let issues = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return raw
        }
        let messages = issues.compactMap { issue -> String? in
            guard let message = issue["message"] as? String, !message.isEmpty else { return nil }
            let path = (issue["path"] as? [Any])?.compactMap { $0 as? String }.joined(separator: ".") ?? ""
            if path == "password" && message.lowercased().contains("too small") { return "Mật khẩu phải có ít nhất 8 ký tự." }
            if path == "email" && message.lowercased().contains("invalid") { return "Email không đúng định dạng." }
            if path == "name" && message.lowercased().contains("too small") { return "Họ tên phải có ít nhất 2 ký tự." }
            return message
        }
        return messages.isEmpty ? raw : messages.map { "• \($0)" }.joined(separator: "\n")
    }
}
