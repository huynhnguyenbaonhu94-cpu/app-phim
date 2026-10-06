import Combine
import Foundation

struct HomeSection: Identifiable {
    let id: String
    let title: String
    let movies: [Movie]
}

@MainActor
final class CinemaStore: ObservableObject {
    @Published private(set) var homeMovies: [Movie] = []
    @Published private(set) var homeSections: [HomeSection] = []
    @Published private(set) var homeLoading = false
    @Published private(set) var homeLoadingMore = false
    @Published private(set) var homeHasMore = false
    @Published private(set) var homeError: String?
    @Published private(set) var catalogMeta: CatalogMeta?
    @Published private(set) var searchResults: [Movie] = []
    @Published private(set) var searchLoading = false
    @Published private(set) var searchError: String?
    @Published private(set) var detailMovie: Movie?
    @Published private(set) var detailLoading = false
    @Published private(set) var detailError: String?
    @Published private(set) var catalogMovies: [Movie] = []
    @Published private(set) var catalogLoading = false
    @Published private(set) var catalogError: String?
    @Published private(set) var catalogHasMore = false
    @Published private(set) var catalogPage = 1
    @Published private(set) var localFavorites: [LocalMovieRecord] = []
    @Published private(set) var localHistory: [LocalWatchRecord] = []
    @Published private(set) var accountUser: RemoteAccountUser?
    @Published private(set) var accountDevices: [RemoteAccountDevice] = []
    @Published private(set) var accountLoading = false
    @Published private(set) var accountError: String?
    @Published var playbackDefaults = PlaybackDefaults()
    @Published private(set) var tvStreams: [TvStream] = []
    @Published private(set) var tvVideos: [TvVideo] = []
    @Published private(set) var tvLoading = false
    @Published private(set) var tvError: String?
    @Published private(set) var hasNewHomeContent = false

    private let api = CinemaAPI.shared
    private let localDefaults = UserDefaults.standard
    private let playbackDefaultsKey = "cinemora.playback.defaults.v1"
    private var homePage = 1
    private var detailTask: Task<Void, Never>?
    private var catalogTask: Task<Void, Never>?
    private var detailRequestID = 0
    private var catalogRequestID = 0
    private var searchRequestID = 0
    private var nextAuthAttemptAt = Date.distantPast
    private var tvEventsTask: Task<Void, Never>?
    private var tvVideoRefreshTask: Task<Void, Never>?
    private var lastHomeRefreshAt: Date?
    private let homeSectionConfig: [(kind: String, title: String)] = [
        ("latest", "Phim Mới"),
        ("series", "Phim Bộ"),
        ("single", "Phim Lẻ"),
        ("shows", "Shows"),
        ("animation", "Hoạt Hình"),
        ("vietsub", "Phim Vietsub"),
        ("thuyetminh", "Phim Thuyết Minh"),
        ("longtieng", "Phim Lồng Tiếng"),
        ("ongoing", "Phim Bộ Đang Chiếu"),
        ("completed", "Phim Bộ Đã Hoàn Thành"),
        ("subteam", "Subteam"),
        ("theatrical", "Phim Chiếu Rạp"),
    ]

    init() {
        let decoder = JSONDecoder()
        // Library data is account-scoped. Remove data written by older builds
        // so an anonymous device can never show a previous user's library.
        clearLegacyLocalLibrary()
        if let data = localDefaults.data(forKey: playbackDefaultsKey), let defaults = try? decoder.decode(PlaybackDefaults.self, from: data) {
            playbackDefaults = defaults
        }
    }

    deinit { tvEventsTask?.cancel(); tvVideoRefreshTask?.cancel() }

    func startTvLiveUpdates() async {
        guard tvEventsTask == nil else { return }
        tvLoading = tvStreams.isEmpty
        do {
            async let streams = api.tvStreams()
            async let videos = api.tvVideos()
            tvStreams = try await streams
            tvVideos = (try? await videos) ?? []
            tvError = nil
        } catch {
            tvError = error.localizedDescription
        }
        tvLoading = false
        tvVideoRefreshTask?.cancel()
        tvVideoRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled else { return }
                if let videos = try? await self.api.tvVideos() { self.tvVideos = videos }
            }
        }
        tvEventsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let bytes = try await self.api.tvEventBytes()
                    var eventData = ""
                    for try await line in bytes.lines {
                        if Task.isCancelled { return }
                        if line.hasPrefix("data:") {
                            eventData = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        } else if line.isEmpty && !eventData.isEmpty {
                            self.applyTvEvent(eventData)
                            eventData = ""
                        }
                    }
                } catch {
                    if Task.isCancelled { return }
                    try? await Task.sleep(for: .seconds(3))
                }
            }
        }
    }

    func stopTvLiveUpdates() {
        tvEventsTask?.cancel()
        tvVideoRefreshTask?.cancel()
        tvEventsTask = nil
        tvVideoRefreshTask = nil
    }

    func refreshTvStreams() async {
        do {
            async let streams = api.tvStreams()
            async let videos = api.tvVideos()
            tvStreams = try await streams
            tvVideos = (try? await videos) ?? tvVideos
            tvError = nil
        } catch {
            tvError = error.localizedDescription
        }
        if tvEventsTask == nil { await startTvLiveUpdates() }
    }

    func clearNewHomeContent() {
        hasNewHomeContent = false
    }

    private func applyTvEvent(_ payload: String) {
        guard let data = payload.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(TvStreamSnapshot.self, from: data) else { return }
        tvStreams = snapshot.streams
        tvError = nil
    }

    func isFavorite(_ movie: Movie) -> Bool {
        localFavorites.contains { $0.slug == movie.slug }
    }

    func toggleFavorite(_ movie: Movie) {
        guard accountUser != nil else { return }
        let adding = !isFavorite(movie)
        if let index = localFavorites.firstIndex(where: { $0.slug == movie.slug }) {
            localFavorites.remove(at: index)
        } else {
            localFavorites.insert(LocalMovieRecord(movie: movie), at: 0)
            localFavorites = Array(localFavorites.prefix(100))
        }
        Task {
            do {
                if adding { try await api.addFavorite(movie: movie) }
                else { try await api.removeFavorite(slug: movie.slug) }
            } catch { await MainActor.run { self.accountError = error.localizedDescription } }
        }
    }

    func removeFavorite(_ record: LocalMovieRecord) {
        localFavorites.removeAll { $0.slug == record.slug }
        guard accountUser != nil else { return }
        Task { try? await api.removeFavorite(slug: record.slug) }
    }

    func recordLocalHistory(movie: Movie, episode: MovieEpisode?, serverName: String? = nil, watchedSeconds: Double = 0, durationSeconds: Double = 0) {
        guard accountUser != nil else { return }
        let record = LocalWatchRecord(movie: LocalMovieRecord(movie: movie), episodeName: episode?.name, episodeSlug: episode?.slug, serverName: serverName, streamURL: episode?.streamUrl, embedURL: episode?.embedUrl, watchedSeconds: watchedSeconds, durationSeconds: durationSeconds, watchedAt: Date())
        localHistory.removeAll { $0.movie.slug == movie.slug }
        localHistory.insert(record, at: 0)
        localHistory = Array(localHistory.prefix(100))
        Task { try? await api.recordHistory(movie: movie, episode: episode, watchedSeconds: watchedSeconds, durationSeconds: durationSeconds) }
    }

    func removeHistory(_ record: LocalWatchRecord) {
        localHistory.removeAll { $0.id == record.id }
        guard accountUser != nil else { return }
        Task { try? await api.removeHistory(slug: record.movie.slug, episodeSlug: record.episodeSlug) }
    }

    func clearFavorites() {
        let records = localFavorites
        localFavorites.removeAll()
        guard accountUser != nil else { return }
        for record in records { Task { try? await api.removeFavorite(slug: record.slug) } }
    }

    func clearHistory() {
        localHistory.removeAll()
        guard accountUser != nil else { return }
        Task { try? await api.clearHistory() }
    }

    func restoreAccount() async {
        do {
            let response = try await api.me()
            accountUser = response.value
            if accountUser != nil { await refreshCloudLibrary() }
        } catch {
            if let apiError = error as? APIError, apiError.isUnauthorized {
                clearAccountState()
            } else { accountError = error.localizedDescription }
        }
    }

    func checkAccountSession() async {
        guard accountUser != nil else { return }
        do {
            let response = try await api.me()
            if let user = response.value { accountUser = user }
            else {
                clearAccountState()
            }
        } catch {
            if let apiError = error as? APIError, apiError.isUnauthorized {
                clearAccountState()
            } else if accountUser != nil { accountError = error.localizedDescription }
        }
    }

    func login(email: String, password: String) async throws {
        try enforceAuthInput(email: email, password: password)
        try enforceAuthCooldown()
        accountLoading = true; accountError = nil
        defer { accountLoading = false }
        do {
            accountUser = try await api.login(email: email, password: password)
            clearLocalCacheAfterAccountLogin()
            Task {
                async let cloudRefresh: Void = refreshCloudLibrary()
                async let deviceRefresh: Void = refreshAccountDevices()
                await cloudRefresh
                await deviceRefresh
            }
        } catch {
            nextAuthAttemptAt = Date().addingTimeInterval(3)
            accountError = error.localizedDescription
            throw error
        }
    }

    func register(name: String, email: String, password: String) async throws {
        try enforceAuthInput(name: name, email: email, password: password)
        try enforceAuthCooldown()
        accountLoading = true; accountError = nil
        defer { accountLoading = false }
        do {
            accountUser = try await api.register(name: name, email: email, password: password)
            clearLocalCacheAfterAccountLogin()
            Task {
                async let cloudRefresh: Void = refreshCloudLibrary()
                async let deviceRefresh: Void = refreshAccountDevices()
                await cloudRefresh
                await deviceRefresh
            }
        } catch {
            nextAuthAttemptAt = Date().addingTimeInterval(3)
            accountError = error.localizedDescription
            throw error
        }
    }

    private func enforceAuthInput(name: String? = nil, email: String, password: String) throws {
        if let name, name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
            accountError = "Họ tên phải có ít nhất 2 ký tự."
            throw APIError.server("Họ tên phải có ít nhất 2 ký tự.")
        }
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedEmail.count <= 320, normalizedEmail.contains("@"), normalizedEmail.contains(".") else {
            accountError = "Email không đúng định dạng."
            throw APIError.server("Email không đúng định dạng.")
        }
        guard password.count >= 8, password.count <= 128 else {
            accountError = "Mật khẩu phải có từ 8 đến 128 ký tự."
            throw APIError.server("Mật khẩu phải có từ 8 đến 128 ký tự.")
        }
    }

    private func enforceAuthCooldown() throws {
        let remaining = Int(ceil(nextAuthAttemptAt.timeIntervalSinceNow))
        guard remaining <= 0 else {
            accountError = "Bạn thao tác quá nhanh. Vui lòng thử lại sau khoảng \(max(1, remaining)) giây."
            throw APIError.rateLimited(seconds: remaining)
        }
    }

    func createQrLogin() async throws -> RemoteQrChallenge {
        try await api.createQrLogin()
    }

    func qrLoginStatus(nonce: String) async throws -> RemoteQrStatus {
        try await api.qrLoginStatus(nonce: nonce)
    }

    func approveQrLogin(nonce: String, approved: Bool) async throws -> RemoteQrStatus {
        try await api.approveQrLogin(nonce: nonce, approved: approved)
    }

    func completeQrLogin(nonce: String) async throws {
        accountError = nil
        accountUser = try await api.completeQrLogin(nonce: nonce)
        clearLocalCacheAfterAccountLogin()
        Task {
            async let cloudRefresh: Void = refreshCloudLibrary()
            async let deviceRefresh: Void = refreshAccountDevices()
            await cloudRefresh
            await deviceRefresh
        }
    }

    func logout() async {
        clearAccountState()
        try? await api.logout()
    }

    func changePassword(currentPassword: String, newPassword: String) async throws {
        guard accountUser != nil else { throw APIError.server("Vui lòng đăng nhập để đổi mật khẩu.") }
        guard currentPassword.count > 0 else { throw APIError.server("Vui lòng nhập mật khẩu hiện tại.") }
        guard newPassword.count >= 8, newPassword.count <= 128 else {
            throw APIError.server("Mật khẩu mới phải có từ 8 đến 128 ký tự.")
        }
        guard currentPassword != newPassword else {
            throw APIError.server("Mật khẩu mới phải khác mật khẩu hiện tại.")
        }
        accountLoading = true
        accountError = nil
        defer { accountLoading = false }
        do {
            try await api.changePassword(currentPassword: currentPassword, newPassword: newPassword)
            await refreshAccountDevices()
        } catch {
            accountError = error.localizedDescription
            throw error
        }
    }

    func refreshCloudLibrary() async {
        guard let expectedUserID = accountUser?.id else { return }
        do {
            async let favorites = api.accountFavorites()
            async let history = api.accountHistory()
            let remoteFavorites = try await favorites
            let remoteHistory = try await history
            guard accountUser?.id == expectedUserID else { return }
            localFavorites = remoteFavorites.map(\.localRecord)
            localHistory = remoteHistory.map(\.localRecord)
        } catch {
            if accountUser != nil { accountError = error.localizedDescription }
        }
    }

    func refreshAccountDevices() async {
        guard let expectedUserID = accountUser?.id else { return }
        do {
            let devices = try await api.accountDevices()
            guard accountUser?.id == expectedUserID else { return }
            accountDevices = devices
        }
        catch {
            if accountUser != nil { accountError = error.localizedDescription }
        }
    }

    func refreshAccountDevicesAfterQrApproval() async {
        // Device B creates its session just after A receives the approval.
        // Retry briefly so A shows the new device without leaving the screen.
        for delay in [0, 400, 900, 1_500, 2_500] {
            guard accountUser != nil else { return }
            if delay > 0 { try? await Task.sleep(for: .milliseconds(delay)) }
            await refreshAccountDevices()
        }
    }

    func logoutDevice(id: Int, deviceId: String? = nil) async {
        let isCurrentDevice = deviceId.map(api.isCurrentDevice) ?? false
        do {
            try await api.logoutDevice(id: id)
            if isCurrentDevice {
                clearAccountState()
            } else {
                await refreshAccountDevices()
            }
        } catch {
            if isCurrentDevice {
                clearAccountState()
            } else { accountError = error.localizedDescription }
        }
    }

    func logoutAllDevices() async {
        clearAccountState()
        try? await api.logoutAllDevices()
    }

    func clearAccountError() {
        accountError = nil
    }

    private func clearLegacyLocalLibrary() {
        localDefaults.removeObject(forKey: "cinemora.local.favorites.v1")
        localDefaults.removeObject(forKey: "cinemora.local.history.v1")
        localFavorites = []; localHistory = []
    }

    private func clearLocalCacheAfterAccountLogin() {
        clearLegacyLocalLibrary()
    }

    private func clearAccountState() {
        accountUser = nil
        accountDevices = []
        localFavorites = []
        localHistory = []
        accountError = nil
        clearLegacyLocalLibrary()
    }

    func savePlaybackDefaults() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(playbackDefaults) {
            localDefaults.set(data, forKey: playbackDefaultsKey)
        }
    }

    func loadHome() async {
        guard homeSections.isEmpty, !homeLoading else { return }
        await loadHomeSections(refresh: false)
    }

    func refreshHome() async {
        lastHomeRefreshAt = Date()
        await loadHomeSections(refresh: true)
    }

    func autoRefreshHome() async {
        if let lastHomeRefreshAt, Date().timeIntervalSince(lastHomeRefreshAt) < 60 { return }
        await refreshHome()
    }

    private func loadHomeSections(refresh: Bool) async {
        guard !homeLoading else { return }
        homeLoading = true
        homeError = nil
        defer { homeLoading = false }

        let config = homeSectionConfig
        var results: [(Int, [Movie], String?)] = []
        for batchStart in stride(from: 0, to: config.count, by: 4) {
            let batchEnd = min(batchStart + 4, config.count)
            let batch = await withTaskGroup(of: (Int, [Movie], String?).self, returning: [(Int, [Movie], String?)].self) { group in
                for index in batchStart..<batchEnd {
                    let section = config[index]
                    group.addTask {
                        do {
                            let page: MoviePage
                            if refresh && section.kind == "latest" {
                                do {
                                    page = try await self.api.dailyUpdates()
                                } catch {
                                    if Self.isCancellation(error) { return (index, [], nil) }
                                    page = try await self.api.list(kind: "latest")
                                }
                            } else {
                                page = try await self.api.list(kind: section.kind)
                            }
                            return (index, page.items, nil)
                        } catch {
                            if Self.isCancellation(error) { return (index, [], nil) }
                            return (index, [], error.localizedDescription)
                        }
                    }
                }
                var collected: [(Int, [Movie], String?)] = []
                for await result in group { collected.append(result) }
                return collected
            }
            results.append(contentsOf: batch)
            if Task.isCancelled { return }
        }
        results.sort { $0.0 < $1.0 }

        let previousLatest = Set(homeSections.first(where: { $0.id == "latest" })?.movies.map(\.id) ?? [])
        let nextLatest = Set(results.first(where: { $0.0 == 0 })?.1.map(\.id) ?? [])
        if refresh && !previousLatest.isEmpty && !nextLatest.isEmpty && previousLatest != nextLatest {
            hasNewHomeContent = true
        }
        homeSections = results.enumerated().compactMap { index, result in
            guard !result.1.isEmpty else { return nil }
            return HomeSection(id: config[index].kind, title: config[index].title, movies: result.1)
        }
        homeMovies = homeSections.first(where: { $0.id == "latest" })?.movies ?? []
        homePage = 1
        homeHasMore = homeMovies.count >= 12
        if homeMovies.isEmpty {
            homeError = results.compactMap(\.2).first
        }
    }

    private nonisolated static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    func loadMoreHome() async {
        guard homeHasMore, !homeLoadingMore else { return }
        homeLoadingMore = true; homeError = nil
        defer { homeLoadingMore = false }
        let next = homePage + 1
        do {
            let page = try await api.list(page: next, kind: "latest")
            let existing = Set(homeMovies.map(\.slug))
            homeMovies.append(contentsOf: page.items.filter { !existing.contains($0.slug) })
            homePage = next
            homeHasMore = page.pagination?.hasMore(page: next, received: page.items.count) ?? (page.items.count >= 12)
        } catch { homeError = error.localizedDescription }
    }

    func loadMeta() async {
        guard catalogMeta == nil else { return }
        do { catalogMeta = try await api.meta() }
        catch { catalogError = error.localizedDescription }
    }

    func search(_ keyword: String) async {
        let value = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 2 else { searchResults = []; return }
        searchRequestID += 1
        let requestID = searchRequestID
        searchLoading = true; searchError = nil
        defer { if requestID == searchRequestID { searchLoading = false } }
        do {
            let results = try await api.search(value).items
            guard requestID == searchRequestID else { return }
            searchResults = results
        } catch {
            guard requestID == searchRequestID else { return }
            searchResults = []; searchError = error.localizedDescription
        }
    }

    func clearSearch() {
        searchRequestID += 1
        searchResults = []
        searchError = nil
        searchLoading = false
    }

    func loadDetail(slug: String) {
        detailTask?.cancel()
        detailRequestID += 1
        let requestID = detailRequestID
        detailMovie = nil; detailLoading = true; detailError = nil
        detailTask = Task {
            defer { if requestID == detailRequestID { detailLoading = false } }
            do {
                let value = try await api.detail(slug: slug)
                guard !Task.isCancelled, requestID == detailRequestID else { return }
                detailMovie = value
            } catch {
                guard !Task.isCancelled, requestID == detailRequestID else { return }
                detailError = error.localizedDescription
            }
        }
    }

    func loadCatalog(kind: String = "latest", category: String? = nil, country: String? = nil, year: Int? = nil, reset: Bool = true) {
        if !reset && catalogLoading { return }
        catalogTask?.cancel()
        catalogRequestID += 1
        let requestID = catalogRequestID
        let nextPage = reset ? 1 : catalogPage + 1
        if reset { catalogMovies = []; catalogPage = 1; catalogHasMore = false }
        catalogLoading = true; catalogError = nil
        catalogTask = Task {
            defer { if requestID == catalogRequestID { catalogLoading = false } }
            do {
                let page = try await api.list(page: nextPage, kind: kind, category: category, country: country, year: year)
                guard !Task.isCancelled, requestID == catalogRequestID else { return }
                if reset { catalogMovies = page.items }
                else {
                    let existing = Set(catalogMovies.map(\.slug))
                    catalogMovies.append(contentsOf: page.items.filter { !existing.contains($0.slug) })
                }
                catalogPage = nextPage
                catalogHasMore = page.pagination?.hasMore(page: nextPage, received: page.items.count) ?? (page.items.count >= 12)
            } catch {
                guard !Task.isCancelled, requestID == catalogRequestID else { return }
                catalogError = error.localizedDescription
            }
        }
    }
}
