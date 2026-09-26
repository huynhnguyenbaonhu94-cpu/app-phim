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
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
    private let kinds = [LibraryFilterOption(title: "Mới nhất", value: "latest"), LibraryFilterOption(title: "Phim lẻ", value: "single"), LibraryFilterOption(title: "Phim bộ", value: "series")]

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CinemaHeader(eyebrow: "KHÁM PHÁ THEO GU", title: "THƯ VIỆN")
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
}
