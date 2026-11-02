import SwiftUI

struct HomeScreen: View {
    @Environment(CinemaStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var scrollToTopRequest = 0
    @State private var loadingBreath = false
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack {
            CinemaBackground()
            // `ScrollViewReader` instead of `.scrollPosition(id:)`: that binding
            // is written back by the scroll view while scrolling, and every write
            // re-rendered the whole screen — including when the tab was
            // re-selected. Scrolling to the top is now an explicit command.
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        CinemaHeader(eyebrow: "PHIM HAY MỖI NGÀY", title: "CINEMORA")
                            .id("home-header")
                            .auroraReveal(0)

                        if store.hasNewHomeContent {
                            newContentPill
                                .id("home-new")
                        }

                        if let hero = store.homeSections.first(where: { $0.id == "latest" })?.movies.first {
                            HeroParallax(movie: hero, coordinateSpace: "homeScroll")
                                .id("home-hero")
                                .auroraReveal(1)
                        }

                        content
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
                .coordinateSpace(.named("homeScroll"))
                .refreshable { await store.refreshHome() }
                .onChange(of: scrollToTopRequest) { _, _ in
                    withAnimation(Motion.enter) { scrollProxy.scrollTo("home-header", anchor: .top) }
                }
            }
        }
        .animation(Motion.enter, value: store.hasNewHomeContent)
        .toolbar(.hidden, for: .navigationBar)
        .task { await store.loadHome() }
        .onReceive(NotificationCenter.default.publisher(for: .cinemoraTabDidChange)) { note in
            // Quay lại tab Trang chủ: nạp lại để phim mới (API hoặc thêm thủ công)
            // hiện ngay đầu trang.
            guard let index = note.userInfo?["index"] as? Int,
                  CinemoraTab.allCases.indices.contains(index),
                  CinemoraTab.allCases[index] == .home else { return }
            Task { await store.autoRefreshHome() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !store.homeSections.isEmpty {
                Task { await store.autoRefreshHome() }
            }
        }
    }

    // MARK: - New content callout

    private var newContentPill: some View {
        Button {
            store.clearNewHomeContent()
            scrollToTopRequest += 1
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .black))
                Text("Có phim mới — chạm để xem")
                    .font(.auroraLabel(12, weight: .bold))
                Spacer(minLength: 0)
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .black))
            }
            .foregroundStyle(Color.auroraVoid)
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .background(Capsule().fill(LinearGradient.auroraPrimary))
            .auroraShimmer()
            .clipShape(Capsule())
            .auroraHalo(.auroraViolet, radius: 18, opacity: 0.45)
        }
        .buttonStyle(.auroraPress(scale: 0.97))
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityLabel("Có phim mới, chạm để xem")
        // Thẻ "Đề xuất hôm nay" được đẩy lên theo hiệu ứng parallax nên nếu không
        // nâng thông báo lên lớp trên, nó sẽ bị thẻ đề xuất che mất.
        .zIndex(1)
        .task(id: store.hasNewHomeContent) {
            // Tự ẩn sau ít giây để thông báo không nằm lại chắn nội dung khi lướt.
            guard store.hasNewHomeContent else { return }
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { store.clearNewHomeContent() }
        }
    }

    // MARK: - Body content

    @ViewBuilder
    private var content: some View {
        if store.homeLoading && store.homeSections.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 11) {
                        ZStack {
                            Circle()
                                .fill(Color.auroraViolet.opacity(loadingBreath ? 0.19 : 0.10))
                                .frame(width: 34, height: 34)
                                .scaleEffect(loadingBreath ? 1.08 : 0.94)
                            Image(systemName: "sparkles.tv.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(LinearGradient.auroraPrimary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("CINEMORA")
                                .font(.auroraLabel(9, weight: .heavy))
                                .tracking(2.2)
                                .foregroundStyle(Color.auroraViolet)
                            Text("Đang tải phim")
                                .font(.auroraDisplay(23))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        ProgressView()
                            .tint(.auroraViolet)
                            .scaleEffect(0.85)
                    }
                    SkeletonBlock(cornerRadius: 2)
                        .frame(height: 2)
                        .frame(maxWidth: 88, alignment: .leading)
                        .opacity(loadingBreath ? 0.72 : 0.42)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                        loadingBreath = true
                    }
                }
                .auroraReveal(2)
                SkeletonPosterGrid(count: 6)
            }
        } else if !store.homeSections.isEmpty {
            ForEach(Array(store.homeSections.enumerated()), id: \.element.id) { index, section in
                sectionBlock(section, index: index)
                    .id("home-section-\(section.id)")
            }
        } else if let error = store.homeError {
            StateMessage(icon: "wifi.exclamationmark", title: "Chưa thể tải phim", detail: error, actionTitle: "Thử lại") {
                Task { await store.refreshHome() }
            }
            .auroraReveal(2)
        } else {
            StateMessage(icon: "film", title: "Chưa có phim", detail: "Kéo xuống để cập nhật danh sách.")
                .auroraReveal(2)
        }
    }

    private func sectionBlock(_ section: HomeSection, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                SectionHeading(eyebrow: index == 0 ? "MỚI CẬP NHẬT" : "CINEMORA", title: section.title)
                Spacer(minLength: 8)
                // Opens the whole section. It used to link to `section.movies.first`,
                // which is why "Xem thêm" kept landing on the hero movie.
                NavigationLink(value: SectionListRoute(kind: section.id, title: section.title)) {
                    HStack(spacing: 3) {
                        Text("Xem thêm")
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .black))
                    }
                    .font(.auroraLabel(11, weight: .bold))
                    .foregroundStyle(Color.auroraViolet)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.auroraViolet.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(Color.auroraViolet.opacity(0.28), lineWidth: 0.7))
                }
                .buttonStyle(.auroraPress(scale: 0.94))
            }
            .auroraReveal(index + 2)

            if index == 0 {
                let shelfMovies = Array(section.movies.dropFirst().prefix(14))
                if !shelfMovies.isEmpty {
                    MovieShelf(movies: shelfMovies)
                        .padding(.horizontal, -20)
                }
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(Array(section.movies.enumerated()), id: \.element.catalogIdentity) { cardIndex, movie in
                        MoviePosterCard(movie: movie, revealIndex: cardIndex)
                            .id("home-movie-\(movie.catalogIdentity)")
                    }
                }
            }
        }
    }
}


// MARK: - Section list

/// Route for a home section's "Xem thêm" button. Only the section's kind and
/// title travel in the navigation path; the movies are loaded by the screen.
struct SectionListRoute: Hashable {
    let kind: String
    let title: String
}

/// Every movie in one home section, paged in as you scroll.
///
/// It pages `CinemaAPI` itself rather than using `CinemaStore.catalogMovies`,
/// because the library tab owns that state and the two would otherwise overwrite
/// each other's listings.
struct SectionListScreen: View {
    let kind: String
    let title: String

    @Environment(CinemaStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var movies: [Movie] = []
    @State private var page = 1
    @State private var loading = false
    @State private var reachedEnd = false
    @State private var loadError: String?
    @State private var restored = false
    @State private var latestUsesDailyUpdates = true
    @State private var noProgressPages = 0

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    CinemaHeader(eyebrow: "DANH SÁCH PHIM", title: title)
                        .id("section-list-header")
                        .auroraReveal(0)

                    if movies.isEmpty && loading {
                        SkeletonPosterGrid(count: 6)
                    } else if movies.isEmpty, let loadError {
                        StateMessage(icon: "wifi.exclamationmark", title: "Chưa tải được danh sách", detail: loadError, actionTitle: "Thử lại") {
                            Task { await load(reset: true) }
                        }
                    } else {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(Array(movies.enumerated()), id: \.element.catalogIdentity) { index, movie in
                                MoviePosterCard(movie: movie, revealIndex: index)
                                    .id("section-movie-\(movie.catalogIdentity)")
                            }
                        }
                        if let loadError {
                            StateMessage(icon: "wifi.exclamationmark", title: "Chưa tải được trang tiếp theo", detail: loadError, actionTitle: "Thử lại") {
                                self.loadError = nil
                                Task { await load(reset: false) }
                            }
                        } else if reachedEnd && noProgressPages >= 2 {
                            StateMessage(icon: "arrow.triangle.2.circlepath", title: "Trang tiếp theo đang lặp phim", detail: "Đã dừng tự tải để tránh hiển thị trùng. Bạn có thể yêu cầu kiểm tra trang kế tiếp.", actionTitle: "Tiếp tục") {
                                reachedEnd = false
                            }
                        } else if !reachedEnd {
                            ProgressView()
                                .tint(.auroraViolet)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .task(id: "section-page-trigger-\(page)") {
                                    while loading {
                                        do { try await Task.sleep(for: .milliseconds(100)) }
                                        catch { return }
                                        guard !Task.isCancelled else { return }
                                    }
                                    guard !reachedEnd else { return }
                                    await load(reset: false)
                                }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 58)
                .padding(.bottom, 112)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .topLeading) {
            AuroraBackButton(title: "Trở lại") { dismiss() }
                .padding(.leading, 20)
                .padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        // Vuốt từ mép trái sang phải để trở ra, giống màn chi tiết phim.
        .modifier(EdgeBackDrag { dismiss() })
        // Danh sách đã có trong bộ nhớ đệm của cửa hàng thì hiện ra ngay, không tải
        // lại từ đầu. Trước đây màn này bị dựng lại khi quay ra từ trang chi tiết nên
        // người dùng thấy trắng danh sách rồi phim trượt vào như đang tải lại.
        .task {
            restoreFromCache()
            guard movies.isEmpty else { return }
            await load(reset: true)
        }
    }

    private func restoreFromCache() {
        guard !restored else { return }
        restored = true
        guard let cache = store.sectionList(kind) else { return }
        var seen = Set<String>()
        movies = cache.movies.filter { seen.insert($0.catalogIdentity).inserted }
        page = cache.page
        reachedEnd = cache.reachedEnd
        latestUsesDailyUpdates = cache.latestUsesDailyUpdates ?? (kind == "latest")
        noProgressPages = cache.noProgressPages
    }

    private func load(reset: Bool) async {
        guard !loading else { return }
        if reset {
            movies = []
            page = 1
            reachedEnd = false
            loadError = nil
            latestUsesDailyUpdates = true
            noProgressPages = 0
        }
        guard !reachedEnd else { return }
        loading = true
        defer { loading = false }
        do {
            let requestedPage = page
            let result: MoviePage
            if kind == "latest", latestUsesDailyUpdates {
                do {
                    result = try await CinemaAPI.shared.dailyUpdates(page: requestedPage)
                } catch {
                    guard !Task.isCancelled else { throw error }
                    latestUsesDailyUpdates = false
                    result = try await CinemaAPI.shared.list(page: requestedPage, kind: kind)
                }
            } else {
                result = try await CinemaAPI.shared.list(page: requestedPage, kind: kind)
            }
            var known = Set((reset ? [] : movies).map(\.catalogIdentity))
            let baseMovies = reset ? [] : movies
            let nextMovies = baseMovies + result.items.filter { known.insert($0.catalogIdentity).inserted }
            let addedCount = nextMovies.count - baseMovies.count
            let serverHasMore = result.pagination?.hasMore(page: requestedPage, received: result.items.count) ?? (result.items.count >= 12)
            var nextNoProgressPages = reset ? 0 : noProgressPages
            if addedCount == 0 && !result.items.isEmpty {
                nextNoProgressPages += 1
            } else {
                nextNoProgressPages = 0
            }
            let nextReachedEnd = result.items.isEmpty || !serverHasMore || nextNoProgressPages >= 2
            let nextPage = requestedPage + 1
            guard !Task.isCancelled else { return }
            store.storeSectionList(
                kind: kind,
                movies: nextMovies,
                page: nextPage,
                reachedEnd: nextReachedEnd,
                latestUsesDailyUpdates: kind == "latest" ? latestUsesDailyUpdates : nil,
                noProgressPages: nextNoProgressPages
            )
            // Commit cache first: updating the footer state below changes the page
            // sentinel ID and can cancel this .task(id:) after it has done its work.
            movies = nextMovies
            noProgressPages = nextNoProgressPages
            reachedEnd = nextReachedEnd
            loadError = nil
            page = nextPage
        } catch {
            if Task.isCancelled { return }
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
            loadError = error.localizedDescription
        }
    }
}
