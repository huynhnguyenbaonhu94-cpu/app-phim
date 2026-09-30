import SwiftUI

struct HomeScreen: View {
    @EnvironmentObject private var store: CinemaStore
    @State private var scrollPosition: String?
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    CinemaHeader(eyebrow: "PHIM HAY MỖI NGÀY", title: "CINEMORA")
                        .id("home-header")
                    if let hero = store.homeSections.first(where: { $0.id == "latest" })?.movies.first {
                        FeaturedMovieCard(movie: hero)
                            .id("home-hero")
                    }

                    topViewedSection

                    if store.homeLoading && store.homeSections.isEmpty {
                        ProgressView().tint(.cinemaAccent).frame(maxWidth: .infinity).padding(.top, 110)
                        Text("Đang cập nhật danh sách phim…")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(maxWidth: .infinity)
                    } else if !store.homeSections.isEmpty {
                        ForEach(store.homeSections) { section in
                            VStack(alignment: .leading, spacing: 11) {
                                HStack(alignment: .lastTextBaseline) {
                                    SectionHeading(eyebrow: "CINEMORA", title: section.title)
                                    Spacer(minLength: 8)
                                    if let first = section.movies.first {
                                        NavigationLink("Xem thêm  ›", value: first)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(Color.cinemaAccent)
                                    }
                                }
                                LazyVGrid(columns: columns, spacing: 20) {
                                    ForEach(section.movies) { movie in
                                        MoviePosterCard(movie: movie)
                                            .id("home-movie-\(movie.id)")
                                    }
                                }
                            }
                            .id("home-section-\(section.id)")
                        }
                    } else if let error = store.homeError {
                        StateMessage(icon: "wifi.exclamationmark", title: "Chưa thể tải phim", detail: error, actionTitle: "Thử lại") {
                            Task { await store.refreshHome() }
                        }
                    } else {
                        StateMessage(icon: "film", title: "Chưa có phim", detail: "Kéo xuống để cập nhật danh sách.")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 36)
                .scrollTargetLayout()
            }
            .scrollPosition(id: $scrollPosition)
            .refreshable {
                await store.refreshHome()
                await store.loadTopViewed(refresh: true)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await store.loadHome()
            await store.loadTopViewed()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await store.loadTopViewed(refresh: true)
            }
        }
    }

    @ViewBuilder
    private var topViewedSection: some View {
        if store.topViewedLoading && store.topViewedMovies.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                SectionHeading(eyebrow: "CẬP NHẬT LIÊN TỤC", title: "Top lượt xem")
                ProgressView().tint(.cinemaAccent).frame(maxWidth: .infinity).padding(.vertical, 28)
            }
        } else if !store.topViewedMovies.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .lastTextBaseline) {
                    SectionHeading(eyebrow: "CẬP NHẬT LIÊN TỤC", title: "Top lượt xem")
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text("LIVE").font(.system(size: 9, weight: .black, design: .rounded)).tracking(1).foregroundStyle(.white.opacity(0.58))
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 13) {
                        ForEach(Array(store.topViewedMovies.enumerated()), id: \.element.id) { index, movie in
                            topViewedCard(movie, rank: index + 1)
                                .id("top-viewed-\(movie.id)-\(movie.views ?? 0)")
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(.easeInOut(duration: 0.32), value: store.topViewedMovies)
        } else if let error = store.topViewedError {
            Text("Top lượt xem tạm thời chưa khả dụng: \(error)")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.48))
        }
    }

    private func topViewedCard(_ movie: Movie, rank: Int) -> some View {
        NavigationLink(value: movie) {
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .bottomLeading) {
                    PosterArt(url: movie.posterURL)
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                    Text("\(rank)")
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.55), radius: 8)
                        .padding(.leading, 9).padding(.bottom, 4)
                    if let views = movie.views {
                        Label(formatViews(views), systemImage: "eye.fill")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(.black.opacity(0.68), in: Capsule())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(8)
                    }
                }
                .frame(width: 145, height: 211)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.13), lineWidth: 0.7))
                Text(movie.name).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(2)
                Text(movie.originName ?? "Đang được quan tâm").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            .frame(width: 145, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func formatViews(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return String(value)
    }
}
