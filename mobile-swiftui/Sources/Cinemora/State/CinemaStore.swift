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
    @Published var playbackDefaults = PlaybackDefaults()
    @Published private(set) var accountUser: AccountUser?
    @Published private(set) var accountDevices: [AccountDevice] = []
    @Published private(set) var accountError: String?
    @Published var requiresLoginMessage: String?
    @Published private(set) var accountBusy = false
    @Published private(set) var accountSyncing = false
    @Published private(set) var accountSyncPending = false
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
        if let index = localFavorites.firstIndex(where: { $0.slug == movie.slug }) {
            localFavorites.remove(at: index)
        } else {
            localFavorites.insert(LocalMovieRecord(movie: movie), at: 0)
            localFavorites = Array(localFavorites.prefix(100))
        }
        persistLocalLibrary()
    }

    func removeFavorite(_ record: LocalMovieRecord) {
        localFavorites.removeAll { $0.slug == record.slug }
        persistLocalLibrary()
    }

    func recordLocalHistory(movie: Movie, episode: MovieEpisode?, serverName: String? = nil, watchedSeconds: Double = 0, durationSeconds: Double = 0) {
        let record = LocalWatchRecord(movie: LocalMovieRecord(movie: movie), episodeName: episode?.name, episodeSlug: episode?.slug, serverName: serverName, streamURL: episode?.streamUrl, embedURL: episode?.embedUrl, watchedSeconds: watchedSeconds, durationSeconds: durationSeconds, watchedAt: Date())
        localHistory.removeAll { $0.movie.slug == movie.slug }
        localHistory.insert(record, at: 0)
        localHistory = Array(localHistory.prefix(100))
        persistLocalLibrary()
    }

    func removeHistory(_ record: LocalWatchRecord) {
        localHistory.removeAll { $0.id == record.id }
        persistLocalLibrary()
    }

    func clearFavorites() {
        localFavorites.removeAll()
        persistLocalLibrary()
    }

    func clearHistory() {
        localHistory.removeAll()
        persistLocalLibrary()
    }

    func savePlaybackDefaults() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(playbackDefaults) {
            localDefaults.set(data, forKey: playbackDefaultsKey)
        }
    }

    func login(email: String, password: String) async {
        accountBusy = true; accountSyncPending = true
        defer { accountBusy = false; accountSyncPending = false }
        do { accountUser = try await api.login(email: email, password: password); try await syncAccount(); accountError = nil }
        catch { accountError = error.localizedDescription }
    }

    func register(name: String, email: String, password: String) async {
        accountBusy = true; accountSyncPending = true
        defer { accountBusy = false; accountSyncPending = false }
        do { accountUser = try await api.register(name: name, email: email, password: password); try await syncAccount(); accountError = nil }
        catch { accountError = error.localizedDescription }
    }

    func logout() async { accountBusy = true; defer { accountBusy = false }; try? await api.logout(); accountUser = nil; accountDevices = [] }
    func refreshAccountDevices() async { do { accountDevices = try await api.devices() } catch { accountError = error.localizedDescription } }
    func kickDevice(_ device: AccountDevice) async { accountBusy = true; defer { accountBusy = false }; do { try await api.kickDevice(sessionId: device.id); await refreshAccountDevices() } catch { accountError = error.localizedDescription } }
    func logoutAllDevices() async { accountBusy = true; defer { accountBusy = false }; do { try await api.logoutAllDevices(); accountUser = nil; accountDevices = [] } catch { accountError = error.localizedDescription } }
    func syncAccountData() async {
        guard accountUser != nil else {
            requiresLoginMessage = "Vui lòng đăng nhập để đồng bộ dữ liệu tài khoản."
            return
        }
        accountBusy = true
        accountSyncPending = true
        defer { accountBusy = false; accountSyncPending = false }
        do {
            try await syncAccount()
            requiresLoginMessage = nil
            accountError = nil
        } catch {
            accountError = error.localizedDescription
            requiresLoginMessage = error.localizedDescription
        }
    }
    func changePassword(current: String, new: String, confirm: String, logoutAll: Bool) async -> Bool {
        accountBusy = true; defer { accountBusy = false }
        do { let result = try await api.changePassword(current: current, new: new, confirm: confirm, logoutAll: logoutAll); if result.loggedOutCurrent { accountUser = nil }; return result.success }
        catch { accountError = error.localizedDescription; return false }
    }

    private func syncAccount() async throws {
        accountSyncing = true
        defer { accountSyncing = false }
        async let favorites = api.favorites()
        async let history = api.history()
        async let preferences = api.preferences()
        let (cloudFavorites, cloudHistory, cloudPreferences) = try await (favorites, history, preferences)
        localFavorites = cloudFavorites.map { item in LocalMovieRecord(movie: Movie(apiID: nil, slug: item.movieSlug, name: item.movieName, originName: item.originName, poster: item.posterUrl, backdrop: item.posterUrl, year: item.year, quality: nil, episodeCurrent: nil, episodeTotal: nil, time: nil, lang: nil, description: nil, rating: nil, categories: nil, countries: nil, actors: nil, actorProfiles: nil, directors: nil, views: nil, alternativeNames: nil, status: nil, tmdbId: nil, imdbId: nil, createdAt: nil, updatedAt: nil, servers: nil, allowPip: nil, episodeGroups: nil)) }
        localHistory = cloudHistory.map { item in LocalWatchRecord(movie: LocalMovieRecord(movie: Movie(apiID: nil, slug: item.movieSlug, name: item.movieName, originName: item.originName, poster: item.posterUrl, backdrop: item.posterUrl, year: item.year, quality: nil, episodeCurrent: nil, episodeTotal: nil, time: nil, lang: nil, description: nil, rating: nil, categories: nil, countries: nil, actors: nil, actorProfiles: nil, directors: nil, views: nil, alternativeNames: nil, status: nil, tmdbId: nil, imdbId: nil, createdAt: nil, updatedAt: nil, servers: nil, allowPip: nil, episodeGroups: nil)), episodeName: item.episodeName, episodeSlug: item.episodeSlug, serverName: nil, streamURL: nil, embedURL: nil, watchedSeconds: Double(item.watchedSeconds), durationSeconds: Double(item.durationSeconds), watchedAt: ISO8601DateFormatter().date(from: item.lastWatchedAt) ?? Date()) }
        if let cloudPreferences {
            playbackDefaults.autoAdvanceEpisodes = cloudPreferences.autoAdvanceEpisodes
            playbackDefaults.stopTimer = cloudPreferences.stopTimer
            playbackDefaults.pictureInPicture = cloudPreferences.pictureInPicture
            playbackDefaults.subtitlePreferences = cloudPreferences.subtitlePreferences
            savePlaybackDefaults()
        }
        await refreshAccountDevices()
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
