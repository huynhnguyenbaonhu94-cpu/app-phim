import SwiftUI
import Foundation

private enum SearchSortField: String, CaseIterable, Identifiable {
    case updated = "Cập nhật"
    case created = "Đăng"
    case year = "Năm SX"

    var id: String { rawValue }
}

struct SearchScreen: View {
    @EnvironmentObject private var store: CinemaStore
    @State private var keyword = ""
    @State private var submitted = ""
    @State private var language = ""
    @State private var category = ""
    @State private var country = ""
    @State private var year = ""
    @State private var sortField: SearchSortField = .updated
    @State private var newestFirst = true
    @FocusState private var focused: Bool
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

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CinemaHeader(eyebrow: "TÌM THEO TÊN VIỆT HOẶC TÊN GỐC", title: "TÌM KIẾM")
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.cinemaAccent)
                        TextField("Tên phim bạn muốn xem…", text: $keyword)
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                            .focused($focused).onSubmit { runSearch() }
                        if !keyword.isEmpty {
                            Button { keyword = ""; submitted = ""; store.clearSearch() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5)) }.buttonStyle(.plain)
                        }
                        Button(action: runSearch) {
                            Image(systemName: "arrow.right").font(.system(size: 13, weight: .black)).foregroundStyle(Color.cinemaInk)
                                .frame(width: 38, height: 38).background(Color.cinemaAccent, in: Circle())
                        }
                        .buttonStyle(.plain).disabled(keyword.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                    }
                    .padding(.leading, 16).padding(.trailing, 8).frame(height: 58)
                    .cinemaGlass(in: RoundedRectangle(cornerRadius: 21), tint: .white.opacity(0.07))

                    HStack(alignment: .lastTextBaseline) {
                        SectionHeading(eyebrow: "KẾT QUẢ", title: submitted.isEmpty ? "Bạn đang tìm gì?" : "“\(submitted)”")
                        Spacer()
                        if !store.searchResults.isEmpty { Text("\(filteredResults.count)/\(store.searchResults.count) phim").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.55)) }
                    }
                    if store.searchLoading {
                        ProgressView("Đang tìm phim…").tint(.cinemaAccent).foregroundStyle(.white.opacity(0.65)).frame(maxWidth: .infinity).padding(.vertical, 60)
                    } else if let error = store.searchError {
                        StateMessage(icon: "wifi.exclamationmark", title: "Tìm kiếm chưa hoàn tất", detail: error, actionTitle: "Thử lại") { runSearch() }
                    } else if !submitted.isEmpty && store.searchResults.isEmpty {
                        StateMessage(icon: "text.magnifyingglass", title: "Chưa tìm thấy phim", detail: "Thử tên khác hoặc kiểm tra lại chính tả.")
                    } else if !store.searchResults.isEmpty {
                        quickFilters
                        if filteredResults.isEmpty {
                            StateMessage(icon: "line.3.horizontal.decrease.circle", title: "Không có phim phù hợp", detail: "Hãy nới lỏng một hoặc nhiều bộ lọc.")
                        } else {
                        LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(filteredResults) { MoviePosterCard(movie: $0) }
                            }
                        }
                    } else {
                        StateMessage(icon: "sparkles.tv", title: "Khám phá thế giới phim", detail: "Nhập ít nhất 2 ký tự rồi chạm nút tìm kiếm.")
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func runSearch() {
        let value = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 2 else { return }
        focused = false
        submitted = value
        Task { await store.search(value) }
    }

    private var quickFilters: some View {
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
            if !filterCategories.isEmpty { filterGroup("THỂ LOẠI", options: filterCategories, selected: category) { value in category = category == value ? "" : value } }
            if !filterCountries.isEmpty { filterGroup("QUỐC GIA", options: filterCountries, selected: country) { value in country = country == value ? "" : value } }
            if !filterYears.isEmpty { filterGroup("NĂM SẢN XUẤT", options: filterYears, selected: year) { value in year = year == value ? "" : value } }
            if hasActiveFilters {
                Button("Xóa bộ lọc", action: resetFilters)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.cinemaAccent)
                    .buttonStyle(.plain)
            }
        }
    }

    private var hasActiveFilters: Bool {
        !language.isEmpty || !category.isEmpty || !country.isEmpty || !year.isEmpty || sortField != .updated || !newestFirst
    }

    private func resetFilters() {
        language = ""; category = ""; country = ""; year = ""; sortField = .updated; newestFirst = true
    }

    private func filterGroup(_ title: String, options: [String], selected: String, action: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow(text: title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        Button { action(option) } label: { filterChip(option, selected: selected == option) }
                            .buttonStyle(.plain)
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
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(selected ? Color.cinemaAccent : Color.white.opacity(0.065), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(selected ? 0.42 : 0.1), lineWidth: 0.7))
    }

    private func dateValue(_ value: String?) -> Date {
        guard let value else { return .distantPast }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) ?? .distantPast
    }
}
