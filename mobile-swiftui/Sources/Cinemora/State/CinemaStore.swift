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
    @Published private(set) var accountBusy = false
    @Published private(set) var accountSyncing = false
    @Published private(set) var accountSyncPending = false
    @Published private(set) var accountError: String?
    @Published var requiresLoginMessage: String?
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
    private let preferencesUpdatedAtKey = "cinemora.playback.defaults.updatedAt.v1"
    private let removedFavoritesKey = "cinemora.account.removedFavorites.v1"
    private let removedHistoryKey = "cinemora.account.removedHistory.v1"
    private let accountUserKey = "cinemora.account.cached-user.v1"
    private let syncPendingKey = "cinemora.account.sync-pending.v1"
    private let guestMigrationCompletedKey = "cinemora.account.guest-migration-completed.v1"
    private let guestMigrationOwnerKey = "cinemora.account.guest-migration-owner.v1"
    private var localDataRevision = 0
    private var accountMonitorTask: Task<Void, Never>?
    private var scheduledSyncTask: Task<Void, Never>?
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
        if let data = localDefaults.data(forKey: accountUserKey), let user = try? decoder.decode(AccountUser.self, from: data) {
            accountUser = user
        }
        let scopedFavoritesKey = accountUser.map { storageKey(favoritesKey, userId: $0.id) }
        let scopedHistoryKey = accountUser.map { storageKey(historyKey, userId: $0.id) }
        let scopedDefaultsKey = accountUser.map { storageKey(playbackDefaultsKey, userId: $0.id) }
        if let key = scopedFavoritesKey, let data = localDefaults.data(forKey: key), let records = try? decoder.decode([LocalMovieRecord].self, from: data) {
            localFavorites = records
        } else if let data = localDefaults.data(forKey: favoritesKey), let records = try? decoder.decode([LocalMovieRecord].self, from: data) { localFavorites = records }
        if let key = scopedHistoryKey, let data = localDefaults.data(forKey: key), let records = try? decoder.decode([LocalWatchRecord].self, from: data) {
            localHistory = records
        } else if let data = localDefaults.data(forKey: historyKey), let records = try? decoder.decode([LocalWatchRecord].self, from: data) { localHistory = records }
        let defaultsKey = scopedDefaultsKey.flatMap { localDefaults.data(forKey: $0) == nil ? nil : $0 } ?? playbackDefaultsKey
        if let data = localDefaults.data(forKey: defaultsKey), let defaults = try? decoder.decode(PlaybackDefaults.self, from: data) { playbackDefaults = defaults }
        accountSyncPending = localDefaults.bool(forKey: syncPendingKey)
    }

    deinit { tvEventsTask?.cancel(); tvVideoRefreshTask?.cancel(); accountMonitorTask?.cancel(); scheduledSyncTask?.cancel() }

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
            addRemovedFavorite(movie.slug)
        } else {
            removeRemovedFavorite(movie.slug)
            localFavorites.insert(LocalMovieRecord(movie: movie), at: 0)
            localFavorites = Array(localFavorites.prefix(100))
        }
        persistLocalLibrary()
    }

    func removeFavorite(_ record: LocalMovieRecord) {
        localFavorites.removeAll { $0.slug == record.slug }
        addRemovedFavorite(record.slug)
        persistLocalLibrary()
    }

    func recordLocalHistory(movie: Movie, episode: MovieEpisode?, serverName: String? = nil, watchedSeconds: Double = 0, durationSeconds: Double = 0, isCompleted: Bool = false) {
        let record = LocalWatchRecord(movie: LocalMovieRecord(movie: movie), episodeName: episode?.name, episodeSlug: episode?.slug, serverName: serverName, streamURL: episode?.streamUrl, embedURL: episode?.embedUrl, watchedSeconds: max(0, watchedSeconds), durationSeconds: max(0, durationSeconds), watchedAt: Date(), isCompleted: isCompleted)
        removeRemovedHistory(record.id)
        localHistory.removeAll { $0.id == record.id }
        localHistory.insert(record, at: 0)
        localHistory = Array(localHistory.prefix(100))
        persistLocalLibrary()
    }

    func removeHistory(_ record: LocalWatchRecord) {
        localHistory.removeAll { $0.id == record.id }
        addRemovedHistory(record.id)
        persistLocalLibrary()
    }

    func clearFavorites() {
        localFavorites.forEach { addRemovedFavorite($0.slug) }
        localFavorites.removeAll()
        persistLocalLibrary()
    }

    func clearHistory() {
        localHistory.forEach { addRemovedHistory($0.id) }
        localHistory.removeAll()
        persistLocalLibrary()
    }

    func savePlaybackDefaults() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(playbackDefaults) {
            localDefaults.set(data, forKey: currentPlaybackDefaultsKey())
            localDefaults.set(Date(), forKey: currentPreferencesUpdatedAtKey())
            localDataRevision += 1
            markAccountSyncPending()
        }
    }

    private func persistLocalLibrary() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(localFavorites) { localDefaults.set(data, forKey: currentFavoritesKey()) }
        if let data = try? encoder.encode(localHistory) { localDefaults.set(data, forKey: currentHistoryKey()) }
        localDataRevision += 1
        markAccountSyncPending()
    }

    private func dateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    func setAccountError(_ value: String?) { accountError = value }

    private func storageKey(_ base: String, userId: Int) -> String { "\(base).account.\(userId)" }
    private func currentFavoritesKey() -> String { accountUser.map { storageKey(favoritesKey, userId: $0.id) } ?? favoritesKey }
    private func currentHistoryKey() -> String { accountUser.map { storageKey(historyKey, userId: $0.id) } ?? historyKey }
    private func currentPlaybackDefaultsKey() -> String { accountUser.map { storageKey(playbackDefaultsKey, userId: $0.id) } ?? playbackDefaultsKey }
    private func currentPreferencesUpdatedAtKey() -> String { accountUser.map { storageKey(preferencesUpdatedAtKey, userId: $0.id) } ?? preferencesUpdatedAtKey }

    private func saveCurrentAccountSnapshot(userId: Int) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(localFavorites) { localDefaults.set(data, forKey: storageKey(favoritesKey, userId: userId)) }
        if let data = try? encoder.encode(localHistory) { localDefaults.set(data, forKey: storageKey(historyKey, userId: userId)) }
        if let data = try? encoder.encode(playbackDefaults) { localDefaults.set(data, forKey: storageKey(playbackDefaultsKey, userId: userId)) }
        if let date = localDefaults.object(forKey: currentPreferencesUpdatedAtKey()) as? Date {
            localDefaults.set(date, forKey: storageKey(preferencesUpdatedAtKey, userId: userId))
        }
    }

    private func loadGuestSnapshot() {
        let decoder = JSONDecoder()
        playbackDefaults = PlaybackDefaults()
        localFavorites = (localDefaults.data(forKey: favoritesKey).flatMap { try? decoder.decode([LocalMovieRecord].self, from: $0) }) ?? []
        localHistory = (localDefaults.data(forKey: historyKey).flatMap { try? decoder.decode([LocalWatchRecord].self, from: $0) }) ?? []
        if let data = localDefaults.data(forKey: playbackDefaultsKey), let defaults = try? decoder.decode(PlaybackDefaults.self, from: data) { playbackDefaults = defaults }
    }

    private func switchToAccount(_ user: AccountUser) {
        if let current = accountUser, current.id != user.id { saveCurrentAccountSnapshot(userId: current.id) }
        guard accountUser?.id != user.id else { accountUser = user; return }
        scheduledSyncTask?.cancel()
        accountUser = user
        let decoder = JSONDecoder()
        let favoritesKeyForUser = storageKey(favoritesKey, userId: user.id)
        let historyKeyForUser = storageKey(historyKey, userId: user.id)
        let defaultsKeyForUser = storageKey(playbackDefaultsKey, userId: user.id)
        let favData = localDefaults.data(forKey: favoritesKeyForUser)
        let historyData = localDefaults.data(forKey: historyKeyForUser)
        let preferencesData = localDefaults.data(forKey: defaultsKeyForUser)
        if favData != nil || historyData != nil || preferencesData != nil {
            localFavorites = favData.flatMap { try? decoder.decode([LocalMovieRecord].self, from: $0) } ?? []
            localHistory = historyData.flatMap { try? decoder.decode([LocalWatchRecord].self, from: $0) } ?? []
            playbackDefaults = preferencesData.flatMap { try? decoder.decode(PlaybackDefaults.self, from: $0) } ?? PlaybackDefaults()
            if !localDefaults.bool(forKey: guestMigrationCompletedKey) {
                localDefaults.set(true, forKey: guestMigrationCompletedKey)
            }
        } else if !localDefaults.bool(forKey: guestMigrationCompletedKey) {
            loadGuestSnapshot() // one-time import for the first account on this device
            localDefaults.set(true, forKey: guestMigrationCompletedKey)
            localDefaults.set(String(user.id), forKey: guestMigrationOwnerKey)
            saveCurrentAccountSnapshot(userId: user.id) // preserve the migration even if cloud sync is offline
        } else {
            localFavorites = []
            localHistory = []
            playbackDefaults = PlaybackDefaults()
        }
        localDataRevision += 1
    }

    private func cachedRemovedFavorites() -> [[String: String]] {
        scopedTombstones(from: localDefaults.stringArray(forKey: removedFavoritesKey) ?? []).map { ["movieSlug": $0.value, "deletedAt": $0.deletedAt] }
    }

    private func cachedRemovedHistory() -> [[String: String]] {
        scopedTombstones(from: localDefaults.stringArray(forKey: removedHistoryKey) ?? []).map { ["key": $0.value, "deletedAt": $0.deletedAt] }
    }

    private func scopedTombstones(from values: [String]) -> [(value: String, deletedAt: String)] {
        guard let userId = accountUser?.id else { return [] }
        let prefix = "\(userId)::"
        return values.compactMap { raw in
            guard raw.hasPrefix(prefix) else { return nil }
            let body = String(raw.dropFirst(prefix.count))
            guard let separator = body.range(of: "::") else { return nil }
            let deletedAt = String(body[..<separator.lowerBound])
            let value = String(body[separator.upperBound...])
            guard !value.isEmpty else { return nil }
            return (value, deletedAt)
        }
    }

    private func appendAccountTombstone(_ value: String, key: String) {
        guard let userId = accountUser?.id else { return }
        let prefix = "\(userId)::"
        var values = (localDefaults.stringArray(forKey: key) ?? []).filter { raw in
            guard raw.hasPrefix(prefix), let separator = raw.range(of: "::", range: raw.index(raw.startIndex, offsetBy: prefix.count)..<raw.endIndex) else { return true }
            return String(raw[separator.upperBound...]) != value
        }
        values.append("\(userId)::\(dateString(Date()))::\(value)")
        localDefaults.set(values, forKey: key)
    }

    private func clearCurrentAccountTombstones(key: String) {
        guard let userId = accountUser?.id else { return }
        let prefix = "\(userId)::"
        let remaining = (localDefaults.stringArray(forKey: key) ?? []).filter { !$0.hasPrefix(prefix) }
        localDefaults.set(remaining, forKey: key)
    }

    private func addRemovedFavorite(_ slug: String) {
        appendAccountTombstone(slug, key: removedFavoritesKey)
    }

    private func removeRemovedFavorite(_ slug: String) {
        guard let userId = accountUser?.id else { return }
        removeAccountTombstone(slug, key: removedFavoritesKey, userId: userId)
    }

    private func addRemovedHistory(_ id: String) {
        appendAccountTombstone(id, key: removedHistoryKey)
    }

    private func removeRemovedHistory(_ id: String) {
        guard let userId = accountUser?.id else { return }
        removeAccountTombstone(id, key: removedHistoryKey, userId: userId)
    }

    private func removeAccountTombstone(_ value: String, key: String, userId: Int) {
        let prefix = "\(userId)::"
        let remaining = (localDefaults.stringArray(forKey: key) ?? []).filter { raw in
            guard raw.hasPrefix(prefix), let separator = raw.range(of: "::", range: raw.index(raw.startIndex, offsetBy: prefix.count)..<raw.endIndex) else { return true }
            return String(raw[separator.upperBound...]) != value
        }
        localDefaults.set(remaining, forKey: key)
    }

    private func markAccountSyncPending() {
        accountSyncPending = true
        localDefaults.set(true, forKey: syncPendingKey)
        scheduleAccountSync()
    }

    private func scheduleAccountSync() {
        guard accountUser != nil, AccountCredentialStore.shared.readToken() != nil else { return }
        scheduledSyncTask?.cancel()
        scheduledSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.syncAccountData()
        }
    }

    func signIn(email: String, password: String) async {
        await authenticate { [api] in try await api.loginAccount(email: email, password: password) }
    }

    func createAccount(name: String, email: String, password: String) async {
        await authenticate { [api] in try await api.registerAccount(name: name, email: email, password: password) }
    }

    private func authenticate(_ request: () async throws -> AccountAuthResponse) async {
        accountBusy = true; accountError = nil
        defer { accountBusy = false }
        do {
            let response = try await request()
            guard AccountCredentialStore.shared.saveToken(response.token) else {
                throw APIError.server("Không thể lưu phiên đăng nhập an toàn vào Keychain.")
            }
            switchToAccount(response.user)
            requiresLoginMessage = nil
            if let data = try? JSONEncoder().encode(response.user) { localDefaults.set(data, forKey: accountUserKey) }
            accountSyncPending = true
            localDefaults.set(true, forKey: syncPendingKey)
            await refreshAccountDevices()
            await syncAccountData()
            startAccountMonitoring()
        } catch { accountError = error.localizedDescription }
    }

    func signOut() async {
        accountBusy = true; accountError = nil
        let token = AccountCredentialStore.shared.readToken()
        do { try await api.logoutAccount() }
        catch {
            if let token { AccountCredentialStore.shared.savePendingRevocation(token) }
            accountError = error.localizedDescription
        }
        AccountCredentialStore.shared.deleteToken()
        if let userId = accountUser?.id { saveCurrentAccountSnapshot(userId: userId) }
        accountUser = nil; accountDevices = []; loadGuestSnapshot()
        localDefaults.removeObject(forKey: accountUserKey)
        accountBusy = false
    }

    func refreshAccountDevices() async {
        guard accountUser != nil else { return }
        do { accountDevices = try await api.accountDevices(); accountError = nil }
        catch { accountError = error.localizedDescription; handleIfSessionWasRevoked(error) }
    }

    func kickDevice(_ device: AccountDevice) async {
        accountBusy = true; accountError = nil
        defer { accountBusy = false }
        do { try await api.kickAccountDevice(sessionId: device.sessionId); await refreshAccountDevices() }
        catch { accountError = error.localizedDescription; handleIfSessionWasRevoked(error) }
    }

    func changePassword(current: String, new: String) async -> Bool {
        accountBusy = true; accountError = nil
        defer { accountBusy = false }
        do { try await api.changeAccountPassword(current: current, new: new); return true }
        catch { accountError = error.localizedDescription; handleIfSessionWasRevoked(error); return false }
    }

    func logoutAllDevices() async -> Bool {
        accountBusy = true; accountError = nil
        defer { accountBusy = false }
        do {
            _ = try await api.logoutAllAccountDevices()
            expireLocalSession(message: "Đã đăng xuất khỏi tất cả thiết bị. Hãy đăng nhập lại để tiếp tục.")
            return true
        } catch { accountError = error.localizedDescription; handleIfSessionWasRevoked(error); return false }
    }

    func startAccountMonitoring() {
        guard accountMonitorTask == nil else { return }
        accountMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.flushPendingSessionRevocations()
            if AccountCredentialStore.shared.readToken() != nil { await self.validateRestoredSession() }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(35))
                guard !Task.isCancelled else { return }
                await self.flushPendingSessionRevocations()
                guard AccountCredentialStore.shared.readToken() != nil else { continue }
                do {
                    _ = try await self.api.accountHeartbeat()
                    if self.accountSyncPending { await self.syncAccountData() }
                    if self.accountUser != nil { await self.refreshAccountDevicesIfVisible() }
                } catch { self.handleIfSessionWasRevoked(error) }
            }
        }
    }

    private func flushPendingSessionRevocations() async {
        for token in AccountCredentialStore.shared.readPendingRevocations() {
            do {
                try await api.logoutAccount(usingToken: token)
                AccountCredentialStore.shared.removePendingRevocation(token)
            } catch {
                if isSessionFailure(error) { AccountCredentialStore.shared.removePendingRevocation(token) }
            }
        }
    }

    func checkAccountSessionOnForeground() async {
        guard AccountCredentialStore.shared.readToken() != nil else { return }
        do { _ = try await api.accountHeartbeat(); if accountSyncPending { await syncAccountData() } }
        catch { handleIfSessionWasRevoked(error) }
    }

    private func validateRestoredSession() async {
        do {
            let user = try await api.currentAccount()
            switchToAccount(user)
            if let data = try? JSONEncoder().encode(user) { localDefaults.set(data, forKey: accountUserKey) }
            await refreshAccountDevices()
            accountSyncPending = true
            localDefaults.set(true, forKey: syncPendingKey)
            await syncAccountData()
        } catch {
            if isSessionFailure(error) { expireLocalSession(message: "Phiên đăng nhập đã hết hạn hoặc bị thu hồi. Vui lòng đăng nhập lại.") }
            else { accountSyncPending = true; localDefaults.set(true, forKey: syncPendingKey) }
        }
    }

    private func isSessionFailure(_ error: Error) -> Bool {
        guard let apiError = error as? APIError else { return false }
        if case APIError.server(let message) = apiError {
            let text = message.lowercased()
            return text.contains("đăng nhập") || text.contains("kết thúc") || text.contains("unauthorized") || text.contains("authentication")
        }
        if case APIError.http(401) = apiError { return true }
        return false
    }

    private func handleIfSessionWasRevoked(_ error: Error) {
        guard isSessionFailure(error) else { return }
        expireLocalSession(message: "Thiết bị của bạn đã bị đăng xuất khỏi tài khoản.")
    }

    private func expireLocalSession(message: String) {
        AccountCredentialStore.shared.deleteToken()
        if let userId = accountUser?.id { saveCurrentAccountSnapshot(userId: userId) }
        accountUser = nil; accountDevices = []; requiresLoginMessage = message
        loadGuestSnapshot()
        localDefaults.removeObject(forKey: accountUserKey)
        accountMonitorTask?.cancel(); accountMonitorTask = nil
    }

    private func refreshAccountDevicesIfVisible() async {
        guard accountUser != nil else { return }
        do { accountDevices = try await api.accountDevices() } catch { handleIfSessionWasRevoked(error) }
    }

    func syncAccountData() async {
        guard !accountSyncing, accountUser != nil, AccountCredentialStore.shared.readToken() != nil else { return }
        accountSyncing = true; accountError = nil
        defer { accountSyncing = false }
        let revisionAtStart = localDataRevision
        let removedFavorites = cachedRemovedFavorites()
        let removedHistory = cachedRemovedHistory()
        let favoritePayload: [[String: Any]] = localFavorites.prefix(100).map { item in
            var value: [String: Any] = ["movieSlug": item.slug, "movieName": item.name, "addedAt": dateString(item.savedAt)]
            if let origin = item.originName { value["originName"] = origin }
            if let poster = item.poster, poster.hasPrefix("/api/cinema/image/") { value["posterUrl"] = poster }
            if let year = item.year { value["year"] = year }
            return value
        }
        let historyPayload: [[String: Any]] = localHistory.prefix(100).map { item in
            var value: [String: Any] = [
                "movieSlug": item.movie.slug, "movieName": item.movie.name,
                "episodeSlug": item.episodeSlug ?? "movie", "episodeName": item.episodeName ?? "Phim",
                "watchedSeconds": Int(max(0, item.watchedSeconds).rounded()),
                "durationSeconds": Int(max(0, item.durationSeconds).rounded()),
                "isCompleted": item.isCompleted || (item.durationSeconds > 0 && item.watchedSeconds >= item.durationSeconds - 1),
                "lastWatchedAt": dateString(item.watchedAt),
            ]
            if let origin = item.movie.originName { value["originName"] = origin }
            if let poster = item.movie.poster, poster.hasPrefix("/api/cinema/image/") { value["posterUrl"] = poster }
            if let year = item.movie.year { value["year"] = year }
            if let episodeName = item.episodeName { value["episodeName"] = episodeName }
            if let server = item.serverName { value["serverName"] = server }
            return value
        }
        var preferencesPayload: [String: Any]?
        var preferencesUpdatedAt: String?
        if localDefaults.data(forKey: currentPlaybackDefaultsKey()) != nil {
            let updatedAtKey = currentPreferencesUpdatedAtKey()
            let updatedAt = (localDefaults.object(forKey: updatedAtKey) as? Date) ?? Date()
            if localDefaults.object(forKey: updatedAtKey) == nil { localDefaults.set(updatedAt, forKey: updatedAtKey) }
            if let data = try? JSONEncoder().encode(playbackDefaults), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                preferencesPayload = object
                preferencesUpdatedAt = dateString(updatedAt)
            }
        }
        do {
            let result = try await api.syncAccount(favorites: favoritePayload, history: historyPayload,
                removedFavorites: removedFavorites, removedHistory: removedHistory,
                preferences: preferencesPayload, preferencesUpdatedAt: preferencesUpdatedAt)
            let serverFavorites = result.favorites.map { item in
                LocalMovieRecord(slug: item.movieSlug, name: item.movieName, originName: item.originName,
                    poster: item.posterUrl, year: item.year, savedAt: parseDate(item.addedAt) ?? Date())
            }
            let serverHistory = result.history.map { item in
                let movie = LocalMovieRecord(slug: item.movieSlug, name: item.movieName, originName: item.originName,
                    poster: item.posterUrl, year: item.year, savedAt: parseDate(item.lastWatchedAt) ?? Date())
                let episode = item.episodeSlug == "movie" ? nil : item.episodeSlug
                return LocalWatchRecord(movie: movie, episodeName: item.episodeName, episodeSlug: episode,
                    serverName: item.serverName, streamURL: nil, embedURL: nil,
                    watchedSeconds: Double(item.watchedSeconds), durationSeconds: Double(item.durationSeconds),
                    watchedAt: parseDate(item.lastWatchedAt) ?? Date(), isCompleted: item.isCompleted ?? false)
            }
            if localDataRevision == revisionAtStart {
                localFavorites = serverFavorites
                localHistory = serverHistory
                if let remote = result.preferences {
                    playbackDefaults = remote.preferences
                    localDefaults.set(try? JSONEncoder().encode(remote.preferences), forKey: currentPlaybackDefaultsKey())
                    if let date = parseDate(remote.updatedAt) { localDefaults.set(date, forKey: currentPreferencesUpdatedAtKey()) }
                }
                clearCurrentAccountTombstones(key: removedFavoritesKey)
                clearCurrentAccountTombstones(key: removedHistoryKey)
                let encoder = JSONEncoder()
                if let data = try? encoder.encode(localFavorites) { localDefaults.set(data, forKey: currentFavoritesKey()) }
                if let data = try? encoder.encode(localHistory) { localDefaults.set(data, forKey: currentHistoryKey()) }
                if localDefaults.string(forKey: guestMigrationOwnerKey) == accountUser.map({ String($0.id) }) {
                    localDefaults.removeObject(forKey: favoritesKey)
                    localDefaults.removeObject(forKey: historyKey)
                    localDefaults.removeObject(forKey: playbackDefaultsKey)
                    localDefaults.removeObject(forKey: preferencesUpdatedAtKey)
                }
                accountSyncPending = false
                localDefaults.set(false, forKey: syncPendingKey)
            } else {
                var mergedFavorites: [String: LocalMovieRecord] = [:]
                serverFavorites.forEach { mergedFavorites[$0.slug] = $0 }
                localFavorites.forEach { mergedFavorites[$0.slug] = $0 }
                localFavorites = Array(mergedFavorites.values)
                var mergedHistory: [String: LocalWatchRecord] = [:]
                serverHistory.forEach { mergedHistory[$0.id] = $0 }
                localHistory.forEach { mergedHistory[$0.id] = $0 }
                localHistory = Array(mergedHistory.values).sorted { $0.watchedAt > $1.watchedAt }
                accountSyncPending = true
                localDefaults.set(true, forKey: syncPendingKey)
                scheduleAccountSync()
            }
            await refreshAccountDevicesIfVisible()
        } catch {
            accountSyncPending = true
            localDefaults.set(true, forKey: syncPendingKey)
            accountError = error.localizedDescription
            handleIfSessionWasRevoked(error)
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
