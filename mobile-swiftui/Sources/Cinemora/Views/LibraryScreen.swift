import SwiftUI

private struct LibraryFilterOption: Identifiable {
    let title: String
    let value: String
    var id: String { value }
}

struct LibraryScreen: View {
    @Environment(CinemaStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var kind = "latest"
    @State private var category = ""
    @State private var country = ""
    @State private var year: Int?
    @State private var filtersExpanded = false
    @State private var loadedSignature: String?
    @State private var lastLoadAt: Date?
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

    private var activeFilterCount: Int {
        [category, country].filter { !$0.isEmpty }.count + (year == nil ? 0 : 1)
    }

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    CinemaHeader(eyebrow: "KHÁM PHÁ THEO GU", title: "THƯ VIỆN")
                        .id("library-header")
                        .auroraReveal(0)

                    kindsRow
                        .id("library-kinds")
                        .auroraReveal(1)

                    filterToggle
                        .auroraReveal(2)

                    if filtersExpanded {
                        filterPanel
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    }

                    HStack(alignment: .lastTextBaseline) {
                        SectionHeading(eyebrow: "TUYỂN CHỌN CINEMORA", title: "Phim dành cho bạn")
                        Spacer()
                        if store.catalogLoading && !store.catalogMovies.isEmpty {
                            ProgressView().tint(.auroraViolet).scaleEffect(0.8)
                        } else if !store.catalogMovies.isEmpty {
                            Text("\(store.catalogMovies.count) phim")
                                .font(.auroraBody(10))
                                .foregroundStyle(Color.auroraTextTertiary)
                        }
                    }
                    .auroraReveal(3)

                    results
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 120)
            }
            .refreshable { load() }
        }
        .animation(Motion.sheet, value: filtersExpanded)
        .toolbar(.hidden, for: .navigationBar)
        .task { await store.loadMeta(); loadIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { loadIfNeeded() }
        }
    }

    // MARK: - Kind selector

    private var kindsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(kinds) { option in
                    AuroraChip(title: option.title, selected: kind == option.value) {
                        selectKind(option.value)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    // MARK: - Filter disclosure

    private var filterToggle: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(Motion.sheet) { filtersExpanded.toggle() }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 12, weight: .bold))
                    Text("Bộ lọc nâng cao")
                        .font(.auroraLabel(12, weight: .bold))
                    if activeFilterCount > 0 {
                        Text("\(activeFilterCount)")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(Color.auroraVoid)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(LinearGradient.auroraPrimary))
                            .transition(.scale.combined(with: .opacity))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .black))
                        .rotationEffect(.degrees(filtersExpanded ? 180 : 0))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 15)
                .padding(.vertical, 14)
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.auroraPress(scale: 0.98))
            .auroraCard(cornerRadius: 18, tint: .auroraSky, fill: 0.75)

            if activeFilterCount > 0 {
                Button {
                    withAnimation(Motion.gentle) { resetFilters() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(Color.auroraPink)
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.auroraPress(scale: 0.92))
                .auroraCard(in: Circle(), tint: .auroraPink, fill: 0.85)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Xóa bộ lọc")
            }
        }
        .animation(Motion.gentle, value: activeFilterCount)
    }

    @ViewBuilder
    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                HStack(spacing: 10) {
                    ProgressView().tint(.auroraViolet)
                    Text("Đang tải bộ lọc…")
                        .font(.auroraBody(11))
                        .foregroundStyle(Color.auroraTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            } else {
                Text("Chưa tải được bộ lọc từ máy chủ.")
                    .font(.auroraBody(11))
                    .foregroundStyle(Color.auroraTextSecondary)
            }
        }
        .padding(16)
        .auroraCard(cornerRadius: 24, tint: .auroraViolet, fill: 0.7)
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        if let error = store.catalogError, store.catalogMovies.isEmpty {
            StateMessage(icon: "wifi.exclamationmark", title: "Không tải được thư viện", detail: error, actionTitle: "Thử lại") { load() }
        } else if store.catalogLoading && store.catalogMovies.isEmpty {
            SkeletonPosterGrid(count: 6)
        } else if store.catalogMovies.isEmpty {
            StateMessage(icon: "film", title: "Chưa có kết quả", detail: "Hãy đổi bộ lọc để khám phá thêm phim.")
        } else {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(Array(store.catalogMovies.enumerated()), id: \.element.id) { index, movie in
                    MoviePosterCard(movie: movie, revealIndex: index % 12)
                        .id("library-movie-\(movie.id)")
                        .task {
                            if store.catalogHasMore && store.catalogMovies.suffix(4).contains(where: { $0.id == movie.id }) {
                                store.loadCatalog(kind: kind, category: category.isEmpty ? nil : category, country: country.isEmpty ? nil : country, year: year, reset: false)
                            }
                        }
                }
            }
            .id("library-results-\(kind)-\(category)-\(country)-\(year.map(String.init) ?? "all")")

            if store.catalogLoading {
                HStack(spacing: 9) {
                    ProgressView().tint(.auroraViolet).scaleEffect(0.85)
                    Text("Đang tải thêm…")
                        .font(.auroraBody(10))
                        .foregroundStyle(Color.auroraTextTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
            } else if !store.catalogHasMore {
                Text("Đã hiển thị hết kết quả.")
                    .font(.auroraBody(10))
                    .foregroundStyle(Color.auroraTextTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
            }
        }
    }

    // MARK: - Helpers

    private func selectKind(_ value: String) {
        withAnimation(Motion.gentle) { kind = value }
        load()
    }

    private func resetFilters() {
        category = ""
        country = ""
        year = nil
        load()
    }

    private func load() {
        loadedSignature = filterSignature
        lastLoadAt = Date()
        store.loadCatalog(kind: kind, category: category.isEmpty ? nil : category, country: country.isEmpty ? nil : country, year: year)
    }

    private var filterSignature: String {
        "\(kind)|\(category)|\(country)|\(year.map(String.init) ?? "-")"
    }

    /// `TabView` re-runs `.task` every time the tab becomes visible again.
    /// Reloading unconditionally cleared the grid and showed skeletons on every
    /// switch, so re-appearance now reuses what is already loaded unless the
    /// filters changed, the grid is empty, or the data went stale.
    private func loadIfNeeded() {
        if loadedSignature == filterSignature,
           !store.catalogMovies.isEmpty,
           let lastLoadAt,
           Date().timeIntervalSince(lastLoadAt) < 180 {
            return
        }
        load()
    }

    private func filterGroup(_ title: String, values: [LibraryFilterOption], selected: String, action: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionEyebrow(text: title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(values) { option in
                        AuroraChip(title: option.title, selected: selected == option.value) {
                            action(option.value)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }
}
