import SwiftUI
import Foundation

private enum SearchSortField: String, CaseIterable, Identifiable {
    case updated = "Cập nhật"
    case created = "Đăng"
    case year = "Năm SX"

    var id: String { rawValue }
}

struct SearchScreen: View {
    @Environment(CinemaStore.self) private var store
    @State private var submitted = ""
    @State private var language = ""
    @State private var category = ""
    @State private var country = ""
    @State private var year = ""
    @State private var sortField: SearchSortField = .updated
    @State private var newestFirst = true
    @State private var filtersExpanded = false
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private var filterCategories: [String] {
        Array(Set(store.searchResults.flatMap { $0.categories ?? [] }.map(\.name))).sorted()
    }

    private var filterCountries: [String] {
        Array(Set(store.searchResults.flatMap { $0.countries ?? [] }.map(\.name))).sorted()
    }

    private var filterYears: [String] {
        Array(Set(store.searchResults.compactMap { $0.year }.map(String.init))).sorted(by: >)
    }

    private var filteredResults: [Movie] {
        let filtered = store.searchResults.filter { movie in
            let languageMatch = language.isEmpty || movie.lang?.localizedCaseInsensitiveContains(language) == true
            let categoryMatch = category.isEmpty || movie.categories?.contains { $0.name == category } == true
            let countryMatch = country.isEmpty || movie.countries?.contains { $0.name == country } == true
            let yearMatch = year.isEmpty || movie.year.map(String.init) == year
            return languageMatch && categoryMatch && countryMatch && yearMatch
        }

        return filtered.sorted { lhs, rhs in
            let comparison: ComparisonResult
            switch sortField {
            case .updated:
                comparison = dateValue(lhs.updatedAt).compare(dateValue(rhs.updatedAt))
            case .created:
                comparison = dateValue(lhs.createdAt).compare(dateValue(rhs.createdAt))
            case .year:
                comparison = (lhs.year ?? 0) == (rhs.year ?? 0) ? .orderedSame : ((lhs.year ?? 0) < (rhs.year ?? 0) ? .orderedAscending : .orderedDescending)
            }
            return newestFirst ? comparison == .orderedDescending : comparison == .orderedAscending
        }
    }

    private var hasActiveFilters: Bool {
        !language.isEmpty || !category.isEmpty || !country.isEmpty || !year.isEmpty || sortField != .updated || !newestFirst
    }

    private var activeFilterCount: Int {
        [language, category, country, year].filter { !$0.isEmpty }.count + (sortField == .updated ? 0 : 1) + (newestFirst ? 0 : 1)
    }

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    CinemaHeader(eyebrow: "TÌM THEO TÊN VIỆT HOẶC TÊN GỐC", title: "TÌM KIẾM")
                        .id("search-header")
                        .auroraReveal(0)

                    SearchField(
                        onQuery: { query in
                            submitted = query
                            Task { await store.search(query) }
                        },
                        onClear: {
                            submitted = ""
                            store.clearSearch()
                        }
                    )
                    .id("search-box")
                        .auroraReveal(1)

                    HStack(alignment: .lastTextBaseline) {
                        SectionHeading(eyebrow: "KẾT QUẢ", title: submitted.isEmpty ? "Bạn đang tìm gì?" : "“\(submitted)”")
                        Spacer()
                        if store.searchLoading && !store.searchResults.isEmpty {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.auroraViolet)
                        } else if !store.searchResults.isEmpty {
                            Text("\(filteredResults.count)/\(store.searchResults.count) phim")
                                .font(.auroraBody(10))
                                .foregroundStyle(Color.auroraTextTertiary)
                                .contentTransition(.numericText())
                                .animation(Motion.gentle, value: filteredResults.count)
                        }
                    }
                    .id("search-results-header")
                    .auroraReveal(2)

                    results
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .auroraDismissKeyboardOnTap()
        }
        .animation(Motion.sheet, value: filtersExpanded)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        // Only take over the screen with skeletons when there is nothing to
        // show yet; while typing, the previous results stay put.
        if store.searchLoading && store.searchResults.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    ProgressView().tint(.auroraViolet)
                    Text("Đang tìm phim…")
                        .font(.auroraBody(12))
                        .foregroundStyle(Color.auroraTextSecondary)
                }
                SkeletonPosterGrid(count: 4)
            }
        } else if let error = store.searchError {
            // Retry re-runs whatever is currently in the field.
            StateMessage(icon: "wifi.exclamationmark", title: "Tìm kiếm chưa hoàn tất", detail: error, actionTitle: "Thử lại") {
                guard !submitted.isEmpty else { return }
                Task { await store.search(submitted) }
            }
        } else if !submitted.isEmpty && store.searchResults.isEmpty {
            StateMessage(icon: "text.magnifyingglass", title: "Chưa tìm thấy phim", detail: "Thử tên khác hoặc kiểm tra lại chính tả.")
        } else if !store.searchResults.isEmpty {
            quickFilters
            if filteredResults.isEmpty {
                StateMessage(icon: "line.3.horizontal.decrease.circle", title: "Không có phim phù hợp", detail: "Hãy nới lỏng một hoặc nhiều bộ lọc.")
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(Array(filteredResults.enumerated()), id: \.element.id) { index, movie in
                        MoviePosterCard(movie: movie, revealIndex: index % 12)
                            .id("search-movie-\(movie.id)")
                    }
                }
                .id("search-results-\(submitted)")
            }
        } else {
            StateMessage(icon: "sparkles.tv", title: "Khám phá thế giới phim", detail: "Nhập ít nhất 2 ký tự, kết quả sẽ hiện ngay khi bạn gõ.")
        }
    }

    private var quickFilters: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(Motion.sheet) { filtersExpanded.toggle() }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .bold))
                    Text("Bộ lọc & sắp xếp")
                        .font(.auroraLabel(12, weight: .bold))
                    if activeFilterCount > 0 {
                        Text("\(activeFilterCount)")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(Color.auroraVoid)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(LinearGradient.auroraPrimary))
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

            if filtersExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    filterGroup("SẮP XẾP", options: SearchSortField.allCases.map(\.rawValue), selected: sortField.rawValue) { value in
                        sortField = SearchSortField(rawValue: value) ?? .updated
                    }
                    filterGroup("THỨ TỰ", options: ["Mới nhất", "Cũ nhất"], selected: newestFirst ? "Mới nhất" : "Cũ nhất") { value in
                        newestFirst = value == "Mới nhất"
                    }
                    filterGroup("NGÔN NGỮ", options: ["Vietsub", "Thuyết minh", "Lồng tiếng"], selected: language) { value in
                        language = language == value ? "" : value
                    }
                    if !filterCategories.isEmpty {
                        filterGroup("THỂ LOẠI", options: filterCategories, selected: category) { value in
                            category = category == value ? "" : value
                        }
                    }
                    if !filterCountries.isEmpty {
                        filterGroup("QUỐC GIA", options: filterCountries, selected: country) { value in
                            country = country == value ? "" : value
                        }
                    }
                    if !filterYears.isEmpty {
                        filterGroup("NĂM SẢN XUẤT", options: filterYears, selected: year) { value in
                            year = year == value ? "" : value
                        }
                    }
                    if hasActiveFilters {
                        Button {
                            withAnimation(Motion.gentle) { resetFilters() }
                        } label: {
                            Label("Xóa bộ lọc", systemImage: "arrow.counterclockwise")
                                .font(.auroraLabel(11, weight: .bold))
                                .foregroundStyle(Color.auroraPink)
                        }
                        .buttonStyle(.auroraPress(scale: 0.95))
                    }
                }
                .padding(16)
                .auroraCard(cornerRadius: 22, tint: .auroraViolet, fill: 0.65)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
    }

    private func resetFilters() {
        language = ""
        category = ""
        country = ""
        year = ""
        sortField = .updated
        newestFirst = true
    }

    private func filterGroup(_ title: String, options: [String], selected: String, action: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionEyebrow(text: title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        AuroraChip(title: option, selected: selected == option) {
                            action(option)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    private func dateValue(_ value: String?) -> Date {
        guard let value else { return .distantPast }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) ?? .distantPast
    }
}

/// The query field.
///
/// It owns `keyword` itself on purpose. While the text lived on `SearchScreen`,
/// every keystroke re-evaluated that whole screen — the result grid, the filter
/// chip rows, the sorting — and the typing lagged behind the keyboard. Here only
/// this small field re-renders per keystroke, and the screen hears about the
/// query once typing pauses.
private struct SearchField: View {
    /// Called with the query after a typing pause, and at once on Enter or the
    /// arrow button.
    let onQuery: (String) -> Void
    let onClear: () -> Void

    @State private var keyword = ""
    @State private var debounce: Task<Void, Never>?
    @FocusState private var focused: Bool

    private var trimmed: String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool { trimmed.count >= 2 }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(focused ? Color.auroraViolet : Color.white.opacity(0.5))
            TextField("Tên phim bạn muốn xem…", text: $keyword)
                .font(.auroraBody(14))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
                .onSubmit { searchNow() }
                .onChange(of: keyword) { _, value in schedule(value) }
            if !keyword.isEmpty {
                Button {
                    debounce?.cancel()
                    keyword = ""
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
            Button(action: searchNow) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(canSubmit ? Color.auroraVoid : Color.white.opacity(0.4))
                    .frame(width: 40, height: 40)
                    .background {
                        if canSubmit {
                            Circle().fill(LinearGradient.auroraPrimary)
                        } else {
                            Circle().fill(Color.white.opacity(0.08))
                        }
                    }
            }
            .buttonStyle(.auroraPress(scale: 0.92))
            .disabled(!canSubmit)
            .accessibilityLabel("Tìm kiếm")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 58)
        .auroraCard(cornerRadius: 22, tint: .auroraViolet, fill: focused ? 1 : 0.7)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.auroraViolet.opacity(focused ? 0.6 : 0), lineWidth: 1.2)
        }
        .scaleEffect(focused ? 1.012 : 1)
        .animation(Motion.gentle, value: focused)
        .animation(Motion.gentle, value: keyword.isEmpty)
    }

    /// Enter or the arrow button: search immediately, skipping the debounce.
    private func searchNow() {
        debounce?.cancel()
        guard canSubmit else { return }
        focused = false
        onQuery(trimmed)
    }

    /// Live search: one request per typing pause, not per keystroke. The store
    /// already drops out-of-order responses, so a slower earlier request can
    /// never overwrite a newer result.
    private func schedule(_ value: String) {
        debounce?.cancel()
        let query = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            onClear()
            return
        }
        guard query.count >= 2 else { return }
        debounce = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            onQuery(query)
        }
    }
}
