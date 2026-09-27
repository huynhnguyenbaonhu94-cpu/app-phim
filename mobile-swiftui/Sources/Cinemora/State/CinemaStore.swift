import Combine
import Foundation

@MainActor
final class CinemaStore: ObservableObject {
    @Published private(set) var homeMovies: [Movie] = []
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

    private let api = CinemaAPI.shared
    private var homePage = 1
    private var detailTask: Task<Void, Never>?
    private var catalogTask: Task<Void, Never>?
    private var detailRequestID = 0
    private var catalogRequestID = 0
    private var searchRequestID = 0

    func loadHome() async {
        guard homeMovies.isEmpty, !homeLoading else { return }
        homeLoading = true; homeError = nil
        defer { homeLoading = false }
        do {
            let page = try await api.home()
            homeMovies = page.items
            homePage = 1
            homeHasMore = page.pagination?.hasMore(page: 1, received: page.items.count) ?? (page.items.count >= 12)
        } catch { homeError = error.localizedDescription }
    }

    func refreshHome() async {
        homeError = nil
        do {
            let page = try await api.home()
            homeMovies = page.items
            homePage = 1
            homeHasMore = page.pagination?.hasMore(page: 1, received: page.items.count) ?? (page.items.count >= 12)
        } catch { homeError = error.localizedDescription }
    }

    func loadMoreHome() async {
        guard homeHasMore, !homeLoadingMore else { return }
        homeLoadingMore = true; homeError = nil
        defer { homeLoadingMore = false }
        let next = homePage + 1
        do {
            let page = try await api.home(page: next)
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
