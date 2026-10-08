import SwiftUI

struct HomeScreen: View {
    @Environment(CinemaStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var scrollToTopRequest = 0
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
    }

    // MARK: - Body content

    @ViewBuilder
    private var content: some View {
        if store.homeLoading && store.homeSections.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeading(eyebrow: "CINEMORA", title: "Đang tải phim")
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
                MovieShelf(movies: Array(section.movies.prefix(14)))
                    .padding(.horizontal, -20)
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(Array(section.movies.enumerated()), id: \.element.id) { cardIndex, movie in
                        MoviePosterCard(movie: movie, revealIndex: cardIndex)
                            .id("home-movie-\(movie.id)")
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

    @Environment(\.dismiss) private var dismiss
    @State private var movies: [Movie] = []
    @State private var page = 1
    @State private var loading = false
    @State private var reachedEnd = false
    @State private var loadError: String?

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
                            ForEach(Array(movies.enumerated()), id: \.element.id) { index, movie in
                                MoviePosterCard(movie: movie, revealIndex: index)
                                    .id("section-movie-\(movie.id)")
                            }
                        }
                        if !reachedEnd {
                            ProgressView()
                                .tint(.auroraViolet)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .onAppear { Task { await load(reset: false) } }
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
        .task { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        guard !loading else { return }
        if reset {
            movies = []
            page = 1
            reachedEnd = false
            loadError = nil
        }
        guard !reachedEnd else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await CinemaAPI.shared.list(page: page, kind: kind)
            let known = Set(movies.map(\.id))
            let fresh = result.items.filter { !known.contains($0.id) }
            movies += fresh
            page += 1
            if fresh.isEmpty { reachedEnd = true }
        } catch {
            loadError = error.localizedDescription
            reachedEnd = true
        }
    }
}
