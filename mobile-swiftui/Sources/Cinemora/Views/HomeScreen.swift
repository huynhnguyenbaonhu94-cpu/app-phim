import SwiftUI

struct HomeScreen: View {
    @EnvironmentObject private var store: CinemaStore
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    CinemaHeader(eyebrow: "PHIM HAY MỖI NGÀY", title: "CINEMORA")
                    if let hero = store.homeMovies.first {
                        FeaturedMovieCard(movie: hero)
                        HStack {
                            SectionHeading(eyebrow: "MỚI CẬP NHẬT", title: "Phim mới nhất")
                            Spacer()
                            NavigationLink("Khám phá  ›", value: hero)
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.cinemaAccent)
                        }
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(store.homeMovies.dropFirst()) { movie in
                                MoviePosterCard(movie: movie)
                                    .task {
                                        if store.homeMovies.suffix(4).contains(where: { $0.id == movie.id }) { await store.loadMoreHome() }
                                    }
                            }
                        }
                        if store.homeLoadingMore { ProgressView().tint(.cinemaAccent).frame(maxWidth: .infinity).padding() }
                        if let error = store.homeError { Text(error).font(.system(size: 11)).foregroundStyle(.red.opacity(0.85)).frame(maxWidth: .infinity).padding(.top, 8) }
                        if !store.homeHasMore { Text("Bạn đã xem hết danh sách hiện có.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.42)).frame(maxWidth: .infinity).padding(.top, 12) }
                    } else if store.homeLoading {
                        ProgressView().tint(.cinemaAccent).frame(maxWidth: .infinity).padding(.top, 110)
                        Text("Đang chọn phim hay cho bạn…").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.55)).frame(maxWidth: .infinity)
                    } else if let error = store.homeError {
                        StateMessage(icon: "wifi.exclamationmark", title: "Chưa thể tải phim", detail: error, actionTitle: "Thử lại") { Task { await store.refreshHome() } }
                    } else {
                        StateMessage(icon: "film", title: "Chưa có phim", detail: "Kéo xuống để cập nhật danh sách.")
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 36)
            }
            .refreshable { await store.refreshHome() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await store.loadHome() }
    }

}
