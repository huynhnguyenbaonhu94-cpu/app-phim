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
            .refreshable { await store.refreshHome() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await store.loadHome() }
    }
}
