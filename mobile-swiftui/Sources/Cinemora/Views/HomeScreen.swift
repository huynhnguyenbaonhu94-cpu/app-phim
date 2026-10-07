import SwiftUI

struct HomeScreen: View {
    @EnvironmentObject private var store: CinemaStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var scrollPosition: String?
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack {
            CinemaBackground()
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
                .scrollTargetLayout()
            }
            .coordinateSpace(.named("homeScroll"))
            .scrollPosition(id: $scrollPosition)
            .refreshable { await store.refreshHome() }
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
            withAnimation(Motion.enter) { scrollPosition = "home-header" }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .black))
                    .symbolEffect(.pulse)
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
                if let first = section.movies.first {
                    NavigationLink(value: first) {
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
