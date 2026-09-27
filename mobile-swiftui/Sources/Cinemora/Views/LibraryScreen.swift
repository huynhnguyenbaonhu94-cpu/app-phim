import SwiftUI

private struct LibraryFilterOption: Identifiable {
    let title: String
    let value: String
    var id: String { value }
}

struct LibraryScreen: View {
    @EnvironmentObject private var store: CinemaStore
    @State private var kind = "latest"
    @State private var category = ""
    @State private var country = ""
    @State private var year: Int?
    @State private var showClearHistoryAlert = false
    @State private var showClearFavoritesAlert = false
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
    private let kinds = [
        LibraryFilterOption(title: "Phim Mới", value: "latest"),
        LibraryFilterOption(title: "Phim Bộ", value: "series"),
        LibraryFilterOption(title: "Phim Lẻ", value: "single"),
        LibraryFilterOption(title: "Shows", value: "shows"),
        LibraryFilterOption(title: "Hoạt Hình", value: "animation"),
        LibraryFilterOption(title: "Phim Vietsub", value: "vietsub"),
        LibraryFilterOption(title: "Phim Thuyết Minh", value: "thuyetminh"),
        LibraryFilterOption(title: "Phim Lồng Tiếng", value: "longtieng"),
        LibraryFilterOption(title: "Phim Bộ Đang Chiếu", value: "ongoing"),
        LibraryFilterOption(title: "Phim Bộ Đã Hoàn Thành", value: "completed"),
        LibraryFilterOption(title: "Subteam", value: "subteam"),
        LibraryFilterOption(title: "Phim Chiếu Rạp", value: "theatrical"),
    ]

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CinemaHeader(eyebrow: "KHÁM PHÁ THEO GU", title: "THƯ VIỆN")
                    if !store.localHistory.isEmpty {
                        historyShelf
                    }
                    if !store.localFavorites.isEmpty {
                        favoritesShelf
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 9) {
                            ForEach(kinds) { option in
                                Button { selectKind(option.value) } label: { filterChip(option.title, selected: kind == option.value) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    if let meta = store.catalogMeta {
                        filterGroup("THỂ LOẠI", values: meta.categories.map { LibraryFilterOption(title: $0.name, value: $0.slug) }, selected: category) { value in
                            category = category == value ? "" : value
                            load()
                        }
                        filterGroup("QUỐC GIA", values: meta.countries.map { LibraryFilterOption(title: $0.name, value: $0.slug) }, selected: country) { value in
                            country = country == value ? "" : value
                            load()
                        }
                        filterGroup("NĂM", values: meta.years.prefix(10).map { LibraryFilterOption(title: String($0), value: String($0)) }, selected: year.map { String($0) } ?? "") { value in
                            year = year == Int(value) ? nil : Int(value)
                            load()
                        }
                    } else if store.catalogLoading {
                        ProgressView().tint(.cinemaAccent)
                    }
                    HStack(alignment: .lastTextBaseline) {
                        SectionHeading(eyebrow: "TUYỂN CHỌN CINEMORA", title: "Phim dành cho bạn")
                        Spacer()
                        if store.catalogLoading { ProgressView().tint(.cinemaAccent).scaleEffect(0.8) }
                    }
                    if let error = store.catalogError, store.catalogMovies.isEmpty {
                        StateMessage(icon: "wifi.exclamationmark", title: "Không tải được thư viện", detail: error, actionTitle: "Thử lại") { load() }
                    } else if !store.catalogLoading && store.catalogMovies.isEmpty {
                        StateMessage(icon: "film", title: "Chưa có kết quả", detail: "Hãy đổi bộ lọc để khám phá thêm phim.")
                    } else {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(store.catalogMovies) { movie in
                                MoviePosterCard(movie: movie)
                                    .task {
                                        if store.catalogHasMore && store.catalogMovies.suffix(4).contains(where: { $0.id == movie.id }) {
                                            store.loadCatalog(kind: kind, category: category.isEmpty ? nil : category, country: country.isEmpty ? nil : country, year: year, reset: false)
                                        }
                                    }
                            }
                        }
                        if store.catalogLoading && !store.catalogMovies.isEmpty { ProgressView().tint(.cinemaAccent).frame(maxWidth: .infinity).padding() }
                        if !store.catalogHasMore && !store.catalogMovies.isEmpty { Text("Đã hiển thị hết kết quả.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).frame(maxWidth: .infinity).padding(.top, 12) }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 38)
            }
            .refreshable { load() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await store.loadMeta(); load() }
        .alert("Xóa toàn bộ lịch sử xem?", isPresented: $showClearHistoryAlert) {
            Button("Xóa tất cả", role: .destructive) { store.clearHistory() }
            Button("Hủy", role: .cancel) { }
        } message: {
            Text("Tất cả lịch sử xem được lưu trên thiết bị sẽ bị xóa.")
        }
        .alert("Xóa toàn bộ yêu thích?", isPresented: $showClearFavoritesAlert) {
            Button("Xóa tất cả", role: .destructive) { store.clearFavorites() }
            Button("Hủy", role: .cancel) { }
        } message: {
            Text("Danh sách phim yêu thích trên thiết bị sẽ bị xóa.")
        }
    }

    private func selectKind(_ value: String) {
        kind = value
        load()
    }

    private func load() {
        store.loadCatalog(kind: kind, category: category.isEmpty ? nil : category, country: country.isEmpty ? nil : country, year: year)
    }

    private func filterGroup(_ title: String, values: [LibraryFilterOption], selected: String, action: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionEyebrow(text: title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(values) { option in
                        Button { action(option.value) } label: { filterChip(option.title, selected: selected == option.value) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func filterChip(_ title: String, selected: Bool) -> some View {
        HStack(spacing: 5) {
            if selected { Image(systemName: "checkmark").font(.system(size: 9, weight: .black)) }
            Text(title).font(.system(size: 10, weight: .bold, design: .rounded)).lineLimit(1)
        }
        .foregroundStyle(selected ? Color.cinemaInk : .white.opacity(0.74))
        .padding(.horizontal, 13).padding(.vertical, 10)
        .background(selected ? Color.cinemaAccent : Color.white.opacity(0.065), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(selected ? 0.42 : 0.1), lineWidth: 0.7))
    }

    private var historyShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                SectionHeading(eyebrow: "LƯU TRÊN THIẾT BỊ", title: "Đang xem")
                Spacer()
                Button("Xóa tất cả") { showClearHistoryAlert = true }
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(Color.cinemaAccent)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(store.localHistory) { record in
                        localMovieCard(movie: record.movie.movie, subtitle: [record.episodeName, record.serverName].compactMap { $0 }.joined(separator: " · "), progress: record.durationSeconds > 0 ? record.watchedSeconds / record.durationSeconds : nil, progressLabel: record.durationSeconds > 0 ? "\(formatTime(record.watchedSeconds)) / \(formatTime(record.durationSeconds))" : nil) {
                            store.removeHistory(record)
                        }
                    }
                }
            }
        }
    }

    private var favoritesShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                SectionHeading(eyebrow: "LƯU TRÊN THIẾT BỊ", title: "Yêu thích")
                Spacer()
                Button("Xóa tất cả") { showClearFavoritesAlert = true }
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(Color.cinemaAccent)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(store.localFavorites) { record in
                        localMovieCard(movie: record.movie, subtitle: nil, progress: nil, progressLabel: nil) {
                            store.removeFavorite(record)
                        }
                    }
                }
            }
        }
    }

    private func localMovieCard(movie: Movie, subtitle: String?, progress: Double?, progressLabel: String?, delete: @escaping () -> Void) -> some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(value: movie) {
                VStack(alignment: .leading, spacing: 7) {
                    PosterArt(url: movie.posterURL)
                        .frame(width: 142, height: 205)
                        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(.white.opacity(0.14), lineWidth: 0.7))
                    Text(movie.name).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(2)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    }
                    if let progress, progress > 0 {
                        ProgressView(value: min(1, progress)).tint(Color.cinemaAccent).frame(width: 142)
                        if let progressLabel {
                            Text(progressLabel).font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
                .frame(width: 142, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button(action: delete) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .black)).foregroundStyle(.white)
                    .frame(width: 28, height: 28).background(.black.opacity(0.72), in: Circle())
            }
            .buttonStyle(.plain).padding(7).accessibilityLabel("Xóa khỏi danh sách")
        }
    }

    private func formatTime(_ value: Double) -> String {
        let total = max(0, Int(value)), minutes = total / 60, seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
