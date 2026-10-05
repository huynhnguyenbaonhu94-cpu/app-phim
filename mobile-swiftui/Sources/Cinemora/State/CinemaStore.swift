import Combine
import Foundation
import UIKit

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
    @Published var playbackDefaults = PlaybackDefaults()
    @Published private(set) var accountUser: AccountUser?
    @Published private(set) var accountIsBusy = false
    @Published private(set) var accountSyncMessage: String?
    @Published var requiresRelogin = false
    @Published var reloginMessage = "Thiết bị này đã bị đăng xuất khỏi tài khoản. Vui lòng đăng nhập lại."
    @Published private(set) var tvStreams: [TvStream] = []
    @Published private(set) var tvVideos: [TvVideo] = []
    @Published private(set) var tvLoading = false
    @Published private(set) var tvError: String?
    @Published private(set) var hasNewHomeContent = false

    private let api = CinemaAPI.shared
    private let localDefaults = UserDefaults.standard
    private let favoritesKey = "cinemora.local.favorites.v1"
    private let historyKey = "cinemora.local.history.v1"
    private let playbackDefaultsKey = "cinemora.playback.defaults.v1"
    private var homePage = 1
    private var detailTask: Task<Void, Never>?
    private var catalogTask: Task<Void, Never>?
    private var detailRequestID = 0
    private var catalogRequestID = 0
    private var searchRequestID = 0
    private var tvEventsTask: Task<Void, Never>?
    private var tvVideoRefreshTask: Task<Void, Never>?
    private var accountHeartbeatTask: Task<Void, Never>?
    private var historyCloudSyncTask: Task<Void, Never>?
    private var preferencesCloudSyncTask: Task<Void, Never>?
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
        if let data = localDefaults.data(forKey: favoritesKey), let records = try? decoder.decode([LocalMovieRecord].self, from: data) {
            localFavorites = records
        }
        if let data = localDefaults.data(forKey: historyKey), let records = try? decoder.decode([LocalWatchRecord].self, from: data) {
            localHistory = records
        }
        if let data = localDefaults.data(forKey: playbackDefaultsKey), let defaults = try? decoder.decode(PlaybackDefaults.self, from: data) {
            playbackDefaults = defaults
        }
    }

    deinit { tvEventsTask?.cancel(); tvVideoRefreshTask?.cancel(); accountHeartbeatTask?.cancel(); historyCloudSyncTask?.cancel(); preferencesCloudSyncTask?.cancel() }

    func refreshAccount() async {
        guard AccountTokenStore.read() != nil else { return }
        do {
            guard let user = try await api.accountMe() else {
                clearAccountLocally(kicked: true)
                return
            }
            accountUser = user
            startAccountHeartbeat()
            await synchronizeAccount()
        } catch {
            accountSyncMessage = "Chưa kiểm tra được phiên đăng nhập: \(error.localizedDescription)"
        }
    }

    func loginAccount(email: String, password: String) async throws {
        accountIsBusy = true
        defer { accountIsBusy = false }
        let response = try await api.loginAccount(email: email, password: password, deviceName: UIDevice.current.name, deviceModel: UIDevice.current.model)
        try acceptAuthentication(response)
        await synchronizeAccount()
    }

    func registerAccount(name: String, email: String, password: String) async throws {
        accountIsBusy = true
        defer { accountIsBusy = false }
        let response = try await api.registerAccount(name: name, email: email, password: password, deviceName: UIDevice.current.name, deviceModel: UIDevice.current.model)
        try acceptAuthentication(response)
        await synchronizeAccount()
    }

    private func acceptAuthentication(_ response: AccountAuthResponse) throws {
        guard let token = response.token, !token.isEmpty else { throw APIError.server("Máy chủ chưa trả về token cho ứng dụng. Hãy cập nhật backend rồi thử lại.") }
        AccountTokenStore.save(token)
        accountUser = response.user
        requiresRelogin = false
        accountSyncMessage = nil
        startAccountHeartbeat()
    }

    private func startAccountHeartbeat() {
        accountHeartbeatTask?.cancel()
        accountHeartbeatTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled, AccountTokenStore.read() != nil else { return }
                do {
                    guard let user = try await self.api.accountMe() else {
                        self.clearAccountLocally(kicked: true)
                        return
                    }
                    self.accountUser = user
                } catch let error as APIError {
                    if case .http(let status) = error, status == 401 {
                        self.clearAccountLocally(kicked: true)
                        return
                    }
                } catch { }
            }
        }
    }

    private func synchronizeAccount() async {
        guard accountUser != nil else { return }
        do {
            async let remoteFavoritesTask = api.cloudFavorites()
            async let remoteHistoryTask = api.cloudHistory()
            let remoteFavorites = try await remoteFavoritesTask
            let remoteHistory = try await remoteHistoryTask

            var mergedFavorites = Dictionary(uniqueKeysWithValues: remoteFavorites.map { item in
                (item.movieSlug, LocalMovieRecord(slug: item.movieSlug, name: item.movieName, originName: item.originName, poster: item.posterUrl, year: item.year, savedAt: parseAccountDate(item.addedAt) ?? .distantPast))
            })
            for local in localFavorites {
                if mergedFavorites[local.slug].map({ $0.savedAt < local.savedAt }) ?? true { mergedFavorites[local.slug] = local }
            }
            localFavorites = Array(mergedFavorites.values.sorted { $0.savedAt > $1.savedAt }.prefix(100))

            var mergedHistory: [String: LocalWatchRecord] = [:]
            for item in remoteHistory {
                let movie = LocalMovieRecord(slug: item.movieSlug, name: item.movieName, originName: item.originName, poster: item.posterUrl, year: item.year)
                let record = LocalWatchRecord(movie: movie, episodeName: item.episodeName, episodeSlug: item.episodeSlug, serverName: nil, streamURL: nil, embedURL: nil, watchedSeconds: Double(item.watchedSeconds), durationSeconds: Double(item.durationSeconds), watchedAt: parseAccountDate(item.lastWatchedAt) ?? .distantPast)
                if mergedHistory[item.movieSlug].map({ $0.watchedAt < record.watchedAt }) ?? true { mergedHistory[item.movieSlug] = record }
            }
            for local in localHistory {
                if mergedHistory[local.movie.slug].map({ $0.watchedAt < local.watchedAt }) ?? true { mergedHistory[local.movie.slug] = local }
            }
            localHistory = Array(mergedHistory.values.sorted { $0.watchedAt > $1.watchedAt }.prefix(100))
            persistLocalLibrary()

            // Upload any pre-account local library once it has been merged with cloud data.
            for item in localFavorites { try? await api.addCloudFavorite(item) }
            for item in localHistory { try? await api.recordCloudHistory(item) }

            if let remoteDefaults = try await api.cloudPlaybackDefaults() {
                playbackDefaults = remoteDefaults
                persistPlaybackDefaults()
            } else {
                try await api.saveCloudPlaybackDefaults(playbackDefaults)
            }
            accountSyncMessage = "Đã đồng bộ lịch sử, yêu thích và cài đặt với tài khoản."
        } catch {
            accountSyncMessage = "Đăng nhập được nhưng đồng bộ chưa hoàn tất: \(error.localizedDescription)"
        }
    }

    func listAccountDevices() async throws -> [AccountDevice] { try await api.accountDevices() }

    func kickAccountDevice(_ device: AccountDevice) async throws {
        _ = try await api.kickDevice(device.id)
        if device.current { clearAccountLocally(kicked: true) }
    }

    func changeAccountPassword(current: String, new: String, confirm: String) async throws {
        _ = try await api.changePassword(current: current, new: new, confirm: confirm)
    }

    func logoutAllAccountDevices() async throws {
        _ = try await api.logoutAllDevices()
        clearAccountLocally(kicked: true, message: "Bạn đã đăng xuất khỏi tất cả thiết bị. Hãy đăng nhập lại nếu muốn tiếp tục.")
    }

    func logoutAccount() async {
        do { _ = try await api.logoutCurrent() }
        catch { accountSyncMessage = "Đã xóa phiên trên máy này; máy chủ có thể chưa nhận được yêu cầu đăng xuất." }
        clearAccountLocally(kicked: false)
    }

    private func clearAccountLocally(kicked: Bool, message: String? = nil) {
        accountHeartbeatTask?.cancel()
        historyCloudSyncTask?.cancel()
        preferencesCloudSyncTask?.cancel()
        AccountTokenStore.clear()
        accountUser = nil
        localFavorites = []
        localHistory = []
        localDefaults.removeObject(forKey: favoritesKey)
        localDefaults.removeObject(forKey: historyKey)
        playbackDefaults = PlaybackDefaults()
        persistPlaybackDefaults()
        requiresRelogin = kicked
        if let message { reloginMessage = message }
    }

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
        if let index = localFavorites.firstIndex(where: { $0.slug == movie.slug }) {
            localFavorites.remove(at: index)
            if accountUser != nil { Task { try? await api.removeCloudFavorite(movie.slug) } }
        } else {
            let record = LocalMovieRecord(movie: movie)
            localFavorites.insert(record, at: 0)
            localFavorites = Array(localFavorites.prefix(100))
            if accountUser != nil { Task { try? await api.addCloudFavorite(record) } }
        }
        persistLocalLibrary()
    }

    func removeFavorite(_ record: LocalMovieRecord) {
        localFavorites.removeAll { $0.slug == record.slug }
        if accountUser != nil { Task { try? await api.removeCloudFavorite(record.slug) } }
        persistLocalLibrary()
    }

    func recordLocalHistory(movie: Movie, episode: MovieEpisode?, serverName: String? = nil, watchedSeconds: Double = 0, durationSeconds: Double = 0) {
        let record = LocalWatchRecord(movie: LocalMovieRecord(movie: movie), episodeName: episode?.name, episodeSlug: episode?.slug, serverName: serverName, streamURL: episode?.streamUrl, embedURL: episode?.embedUrl, watchedSeconds: watchedSeconds, durationSeconds: durationSeconds, watchedAt: Date())
        localHistory.removeAll { $0.movie.slug == movie.slug }
        localHistory.insert(record, at: 0)
        localHistory = Array(localHistory.prefix(100))
        persistLocalLibrary()
        scheduleCloudHistorySync(record)
    }

    func removeHistory(_ record: LocalWatchRecord) {
        localHistory.removeAll { $0.id == record.id }
        if accountUser != nil { Task { try? await api.deleteCloudHistory(record) } }
        persistLocalLibrary()
    }

    func clearFavorites() {
        if accountUser != nil {
            let old = localFavorites
            Task { for item in old { try? await api.removeCloudFavorite(item.slug) } }
        }
        localFavorites.removeAll()
        persistLocalLibrary()
    }

    func clearHistory() {
        localHistory.removeAll()
        if accountUser != nil { Task { try? await api.clearCloudHistory() } }
        persistLocalLibrary()
    }

    func savePlaybackDefaults() {
        persistPlaybackDefaults()
        guard accountUser != nil else { return }
        preferencesCloudSyncTask?.cancel()
        preferencesCloudSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled, self.accountUser != nil else { return }
            try? await self.api.saveCloudPlaybackDefaults(self.playbackDefaults)
        }
    }

    private func persistPlaybackDefaults() {
        if let data = try? JSONEncoder().encode(playbackDefaults) { localDefaults.set(data, forKey: playbackDefaultsKey) }
    }

    private func scheduleCloudHistorySync(_ record: LocalWatchRecord) {
        guard accountUser != nil else { return }
        historyCloudSyncTask?.cancel()
        historyCloudSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled, self.accountUser != nil else { return }
            try? await self.api.recordCloudHistory(record)
        }
    }

    private func persistLocalLibrary() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(localFavorites) { localDefaults.set(data, forKey: favoritesKey) }
        if let data = try? encoder.encode(localHistory) { localDefaults.set(data, forKey: historyKey) }
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
