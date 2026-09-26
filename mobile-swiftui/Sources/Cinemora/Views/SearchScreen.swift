import SwiftUI

struct SearchScreen: View {
    @EnvironmentObject private var store: CinemaStore
    @State private var keyword = ""
    @State private var submitted = ""
    @FocusState private var focused: Bool
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

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
                        if !store.searchResults.isEmpty { Text("\(store.searchResults.count) phim").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.55)) }
                    }
                    if store.searchLoading {
                        ProgressView("Đang tìm phim…").tint(.cinemaAccent).foregroundStyle(.white.opacity(0.65)).frame(maxWidth: .infinity).padding(.vertical, 60)
                    } else if let error = store.searchError {
                        StateMessage(icon: "wifi.exclamationmark", title: "Tìm kiếm chưa hoàn tất", detail: error, actionTitle: "Thử lại") { runSearch() }
                    } else if !submitted.isEmpty && store.searchResults.isEmpty {
                        StateMessage(icon: "text.magnifyingglass", title: "Chưa tìm thấy phim", detail: "Thử tên khác hoặc kiểm tra lại chính tả.")
                    } else if !store.searchResults.isEmpty {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(store.searchResults) { MoviePosterCard(movie: $0) }
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
}
