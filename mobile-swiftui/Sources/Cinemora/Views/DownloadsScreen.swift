import SwiftUI

/// Danh sách phim đã tải về: tách rõ **đang tải** và **đã tải**, thanh tiến trình
/// kèm dung lượng thực tế trên dung lượng ước tính, có dừng và xoá từng bản.
struct DownloadsScreen: View {
    @Environment(DownloadManager.self) private var downloads
    @Environment(\.dismiss) private var dismiss
    @State private var filter: DownloadFilter = .active
    @State private var pendingRemoval: DownloadManager.Item?
    @State private var showRemoveAll = false

    enum DownloadFilter: String, CaseIterable, Identifiable {
        case active, done
        var id: String { rawValue }
        var title: String { self == .active ? "Đang tải" : "Đã tải" }
    }

    private var activeItems: [DownloadManager.Item] { downloads.items.filter { $0.phase != .finished } }
    private var doneItems: [DownloadManager.Item] { downloads.items.filter { $0.phase == .finished } }
    private var shownItems: [DownloadManager.Item] { filter == .active ? activeItems : doneItems }
    private var isPaused: Bool { activeItems.allSatisfy { $0.phase == .paused || $0.phase == .failed } }

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    HStack {
                        AuroraBackButton { dismiss() }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 8)
                    header
                    summaryCard
                    filterBar
                    if !shownItems.isEmpty { bulkActions }
                    if shownItems.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(shownItems.enumerated()), id: \.element.id) { index, item in
                            row(item)
                                .auroraReveal(min(index + 1, 8))
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionEyebrow(text: "THƯ MỤC TẢI XUỐNG")
                        DownloadFolderSection()
                    }
                    .auroraReveal(6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        // Vuốt từ mép trái sang phải để trở ra, dải mỏng để không cản việc cuộn.
        .overlay(alignment: .leading) {
            Color.clear
                .frame(width: 16)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            if value.translation.width > 60, abs(value.translation.height) < 80 {
                                dismiss()
                            }
                        }
                )
        }
        .alert("Xoá bản tải xuống?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("Xoá tải", role: .destructive) {
                if let item = pendingRemoval { downloads.remove(item.id) }
                pendingRemoval = nil
            }
            Button("Giữ lại", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text(pendingRemoval.map { "\($0.movieName) — \($0.episodeName) sẽ bị xoá khỏi máy." } ?? "")
        }
        .alert("Xoá tất cả phim đã tải?", isPresented: $showRemoveAll) {
            Button("Xoá tất cả", role: .destructive) { downloads.removeFinished() }
            Button("Huỷ", role: .cancel) { }
        } message: {
            Text("Toàn bộ \(doneItems.count) tập đã tải sẽ bị xoá khỏi máy. Phim đang tải dở không bị ảnh hưởng.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow(text: "XEM KHI KHÔNG CÓ WIFI")
            AuroraGradientText(text: "Đã tải xuống", font: .auroraDisplay(28))
            Text("Phim đã tải nằm trong bộ nhớ máy, phát được khi mất mạng.")
                .font(.auroraBody(12))
                .foregroundStyle(Color.auroraTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 18)
        .auroraReveal(0)
    }

    private var summaryCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.auroraMint.opacity(0.16)).frame(width: 44, height: 44)
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.auroraMint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(doneItems.count) tập đã tải · \(activeItems.count) đang tải")
                        .font(.auroraLabel(13, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Dung lượng đã dùng: \(downloads.totalSizeText) · còn trống \(downloads.freeSpaceText)")
                        .font(.auroraBody(11))
                        .foregroundStyle(Color.auroraTextSecondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .auroraCard(cornerRadius: 20, tint: .auroraMint)
        .auroraReveal(1)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(DownloadFilter.allCases) { option in
                let count = option == .active ? activeItems.count : doneItems.count
                Button {
                    withAnimation(Motion.gentle) { filter = option }
                } label: {
                    HStack(spacing: 6) {
                        Text(option.title).font(.auroraLabel(12, weight: .bold))
                        Text("\(count)")
                            .font(.auroraLabel(10, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((filter == option ? Color.auroraVoid : Color.auroraViolet).opacity(0.18), in: Capsule())
                    }
                    .foregroundStyle(filter == option ? Color.auroraVoid : Color.auroraTextSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(filter == option ? Color.auroraViolet : Color.white.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .auroraReveal(2)
    }

    private var bulkActions: some View {
        HStack(spacing: 8) {
            if filter == .active {
                Button {
                    downloads.pauseAll()
                } label: {
                    smallAction("Dừng tất cả", icon: "pause.circle", tint: .auroraAmber)
                }
                .buttonStyle(.plain)
                .disabled(isPaused)
                .opacity(isPaused ? 0.5 : 1)
            } else {
                Button {
                    showRemoveAll = true
                } label: {
                    smallAction("Xoá tất cả", icon: "trash", tint: .auroraPink)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Text(filter == .active ? "Đang tải song song tối đa 2 tập" : "Xoá ở đây là xoá luôn tệp trong thư mục")
                .font(.auroraBody(10))
                .foregroundStyle(Color.auroraTextSecondary)
        }
        .auroraReveal(3)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: filter == .active ? "arrow.down.circle" : "tray.and.arrow.down")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.auroraTextSecondary)
            Text(filter == .active ? "Không có phim nào đang tải" : "Chưa có phim nào tải xong")
                .font(.auroraLabel(13, weight: .bold))
                .foregroundStyle(.white)
            Text("Mở một phim rồi bấm nút tải xuống ở phần chọn nguồn để lưu tập về máy.")
                .font(.auroraBody(11))
                .foregroundStyle(Color.auroraTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 20)
        .auroraCard(cornerRadius: 22, tint: .auroraSky)
        .auroraReveal(4)
    }

    private func row(_ item: DownloadManager.Item) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                PosterArt(url: URL(string: item.poster ?? "", relativeTo: CinemaAPI.baseURL)?.absoluteURL)
                    .frame(width: 54, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.movieName)
                        .font(.auroraLabel(13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text("\(item.serverName) · \(item.episodeName)")
                        .font(.auroraBody(11))
                        .foregroundStyle(Color.auroraTextSecondary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        statusChip(item)
                        if item.phase == .downloading, !item.speedText.isEmpty {
                            Text(item.speedText)
                                .font(.auroraBody(10))
                                .foregroundStyle(Color.auroraTextSecondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            if item.phase != .finished {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressBar(value: item.progress, tint: item.phase == .downloading ? .auroraViolet : .auroraAmber)
                    HStack(spacing: 8) {
                        Text(item.sizeText)
                            .font(.auroraLabel(11, weight: .bold))
                            .foregroundStyle(.white)
                        Text(item.percentText)
                            .font(.auroraBody(10))
                            .foregroundStyle(Color.auroraViolet)
                        if !item.etaText.isEmpty {
                            Text(item.etaText)
                                .font(.auroraBody(10))
                                .foregroundStyle(Color.auroraTextSecondary)
                        }
                        Spacer(minLength: 0)
                        if item.totalSegments > 0 {
                            Text("\(item.doneSegments)/\(item.totalSegments) phân đoạn")
                                .font(.auroraBody(10))
                                .foregroundStyle(Color.auroraTextSecondary)
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Text(item.sizeText)
                        .font(.auroraLabel(11, weight: .bold))
                        .foregroundStyle(Color.auroraMint)
                    Text("Đã tải xong, xem được offline")
                        .font(.auroraBody(10))
                        .foregroundStyle(Color.auroraTextSecondary)
                    Spacer(minLength: 0)
                }
            }

            if let message = item.message {
                Text(message)
                    .font(.auroraBody(11))
                    .foregroundStyle(item.phase == .unsupported ? Color.auroraAmber : Color.auroraPink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                switch item.phase {
                case .downloading, .waiting:
                    actionButton("Dừng tải", icon: "pause.fill", tint: .auroraAmber) { downloads.pause(item.id) }
                case .paused, .failed:
                    actionButton("Tiếp tục", icon: "play.fill", tint: .auroraMint) { downloads.retry(item.id) }
                case .finished, .unsupported:
                    EmptyView()
                }
                Spacer(minLength: 0)
                actionButton("Xoá tải", icon: "trash", tint: .auroraPink) { pendingRemoval = item }
            }
        }
        .padding(14)
        .auroraCard(cornerRadius: 20, tint: item.phase == .finished ? .auroraMint : .auroraViolet)
    }

    private func statusChip(_ item: DownloadManager.Item) -> some View {
        let tint: Color = switch item.phase {
        case .finished: .auroraMint
        case .failed: .auroraPink
        case .unsupported: .auroraAmber
        case .paused: .auroraAmber
        default: .auroraSky
        }
        return Text(item.phase.title)
            .font(.auroraLabel(10, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
    }

    private func smallAction(_ title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(title).font(.auroraLabel(11, weight: .bold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(tint.opacity(0.14), in: Capsule())
    }

    private func actionButton(_ title: String, icon: String, tint: Color = .auroraViolet, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
                Text(title).font(.auroraLabel(11, weight: .bold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Thanh tiến trình dùng chung cho màn tải xuống.
struct ProgressBar: View {
    let value: Double
    var tint: Color = .auroraViolet

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(LinearGradient(colors: [tint, .auroraPink], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, min(1, value)) * proxy.size.width)
                    .animation(Motion.gentle, value: value)
            }
        }
        .frame(height: 6)
    }
}

/// Bảng tải xuống của một phim: chọn nguồn, xem danh sách tập, tải từng tập.
struct DownloadSheet: View {
    let movie: Movie
    let servers: [MovieServer]
    @Environment(DownloadManager.self) private var downloads
    @Environment(\.dismiss) private var dismiss
    @State private var selectedServer: Int
    @State private var storageWarning: String?

    init(movie: Movie, servers: [MovieServer], initialServer: Int = 0) {
        self.movie = movie
        self.servers = servers
        _selectedServer = State(initialValue: min(max(initialServer, 0), max(servers.count - 1, 0)))
    }

    private var episodes: [MovieEpisode] {
        servers.indices.contains(selectedServer) ? servers[selectedServer].episodes : []
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CinemaBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(Array(servers.enumerated()), id: \.element.id) { index, server in
                                    Button {
                                        withAnimation(Motion.gentle) { selectedServer = index }
                                    } label: {
                                        Text(server.name)
                                            .font(.auroraLabel(11, weight: .bold))
                                            .foregroundStyle(selectedServer == index ? Color.auroraVoid : Color.auroraTextSecondary)
                                            .padding(.horizontal, 13)
                                            .padding(.vertical, 8)
                                            .background(selectedServer == index ? Color.auroraViolet : Color.white.opacity(0.07), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .scrollIndicators(.hidden)

                        if let server = servers.indices.contains(selectedServer) ? servers[selectedServer] : nil {
                            if let storageWarning {
                                Text(storageWarning)
                                    .font(.auroraBody(11))
                                    .foregroundStyle(Color.auroraAmber)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .auroraCard(cornerRadius: 14, tint: .auroraAmber)
                            }
                            Button {
                                Task {
                                    storageWarning = await downloads.enqueueAll(movie: movie, serverName: server.name, episodes: episodes)
                                }
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "arrow.down.circle.fill").font(.system(size: 13, weight: .bold))
                                    Text("Tải tất cả \(episodes.count) tập").font(.auroraLabel(12, weight: .bold))
                                }
                                .foregroundStyle(Color.auroraVoid)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(LinearGradient(colors: [.auroraViolet, .auroraPink], startPoint: .leading, endPoint: .trailing), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(episodes.isEmpty)
                            .opacity(episodes.isEmpty ? 0.5 : 1)

                            VStack(spacing: 8) {
                                ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                                    episodeRow(server: server, episode: episode, index: index)
                                }
                            }
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Tải xuống")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") { dismiss() }
                        .font(.auroraLabel(12, weight: .bold))
                        .foregroundStyle(Color.auroraViolet)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func episodeRow(server: MovieServer, episode: MovieEpisode, index: Int) -> some View {
        let item = downloads.item(movieSlug: movie.slug, episodeSlug: episode.slug.isEmpty ? episode.name : episode.slug)
        return HStack(spacing: 12) {
            Text(String(format: "%02d", index + 1))
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(Color.auroraViolet)
                .frame(width: 22, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(episode.name)
                    .font(.auroraLabel(12, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let item {
                    if item.phase == .downloading {
                        ProgressBar(value: item.progress).frame(width: 140)
                        Text(item.sizeText).font(.auroraBody(10)).foregroundStyle(Color.auroraTextSecondary)
                    } else {
                        Text(item.message ?? item.phase.title)
                            .font(.auroraBody(10))
                            .foregroundStyle(item.phase == .finished ? Color.auroraMint : Color.auroraTextSecondary)
                    }
                }
            }
            Spacer(minLength: 0)
            if let item, item.phase == .finished {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.auroraMint)
            } else if episode.playbackURL != nil {
                Button {
                    if let item, item.phase == .downloading || item.phase == .waiting {
                        downloads.pause(item.id)
                    } else {
                        downloads.enqueue(movie: movie, serverName: server.name, episode: episode)
                    }
                } label: {
                    Image(systemName: item?.phase == .downloading ? "pause.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.auroraViolet)
                }
                .buttonStyle(.plain)
            } else {
                Text("Không có nguồn")
                    .font(.auroraBody(10))
                    .foregroundStyle(Color.auroraTextSecondary)
            }
        }
        .padding(12)
        .auroraCard(cornerRadius: 16, tint: .auroraSky)
    }
}
