import AVFoundation
import SwiftUI

private struct VLCShareItem: Identifiable {
    let id = UUID()
    let fileURLs: [URL]
}

/// Danh sách phim đã tải về: tách rõ **đang tải** và **đã tải**, kèm ước tính
/// dung lượng/ETA khi đang tải và kích thước package chính xác khi hoàn tất.
struct DownloadsScreen: View {
    @Environment(DownloadManager.self) private var downloads
    @Environment(ConnectivityMonitor.self) private var connectivity
    @Environment(\.dismiss) private var dismiss
    @State private var filter: DownloadFilter = .active
    @State private var pendingRemoval: DownloadManager.Item?
    @State private var showRemoveAll = false
    @State private var vlcShareItem: VLCShareItem?
    @State private var vlcNotice: String?
    @State private var exportNotice: String?
    @State private var exportingItemIDs: Set<String> = []
    @State private var exportProgress: [String: Double] = [:]
    @State private var exportStatus: [String: String] = [:]

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
                    if let notice = downloads.networkNotice { networkBanner(notice) }
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
                        SectionEyebrow(text: "THƯ MỤC BẢN XUẤT")
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
        // Vuốt từ mép trái sang phải để trở ra.
        .modifier(EdgeBackDrag { dismiss() })
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
        .alert("Không thể mở bằng VLC", isPresented: Binding(get: { vlcNotice != nil }, set: { if !$0 { vlcNotice = nil } })) {
            Button("Đã hiểu", role: .cancel) { vlcNotice = nil }
        } message: {
            Text(vlcNotice ?? "Tệp tải xuống không khả dụng.")
        }
        .alert("Không thể xuất video", isPresented: Binding(get: { exportNotice != nil }, set: { if !$0 { exportNotice = nil } })) {
            Button("Đã hiểu", role: .cancel) { exportNotice = nil }
        } message: {
            Text(exportNotice ?? "Không thể tạo bản video tương thích.")
        }
        .sheet(item: $vlcShareItem) { item in
            OfflineFileActivityView(fileURLs: item.fileURLs)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func openWithVLC(_ item: DownloadManager.Item) {
        if let exportedURL = downloads.vlcExportURL(for: item) {
            shareWithVLC(item, videoURL: exportedURL)
            return
        }
        guard let packageURL = downloads.localURL(for: item) else {
            vlcNotice = "Không tìm thấy bản tải trên thiết bị. Hãy xoá mục này rồi tải lại khi có mạng."
            return
        }
        guard packageURL.pathExtension.lowercased() == "movpkg" else {
            switch OfflinePlaybackSupport.vlcAvailability(for: packageURL) {
            case .available:
                shareWithVLC(item, videoURL: packageURL)
            case .notInstalled:
                vlcNotice = "Chưa phát hiện VLC. Hãy cài VLC, sau đó thử lại để chuyển tệp qua bảng chia sẻ của iOS."
            case .unsupportedFile(let ext):
                vlcNotice = "Không thể mở trực tiếp định dạng .\(ext) bằng VLC. Hãy tải lại để Cinemora tạo bản HLS có thể xuất MP4/MOV."
            }
            return
        }
        exportForVLC(item, sourceURL: packageURL)
    }

    private func shareWithVLC(_ item: DownloadManager.Item, videoURL: URL) {
        var fileURLs = [videoURL]
        for track in downloads.subtitleTracks(for: item) {
            guard let subtitleURL = track.localFileURL,
                  !fileURLs.contains(subtitleURL) else { continue }
            fileURLs.append(subtitleURL)
        }
        vlcShareItem = VLCShareItem(fileURLs: fileURLs)
    }

    private func exportForVLC(_ item: DownloadManager.Item, sourceURL: URL) {
        guard !exportingItemIDs.contains(item.id) else { return }
        let requiredBytes = max(item.receivedBytes, 1)
        if downloads.freeBytes > 0, downloads.freeBytes < requiredBytes {
            exportNotice = "Không đủ dung lượng trống để tạo bản MP4/MOV. Hãy giải phóng ít nhất khoảng \(auroraByteText(requiredBytes)) rồi thử lại."
            return
        }

        let id = item.id
        exportingItemIDs.insert(id)
        exportProgress[id] = 0
        exportStatus[id] = "Đang kiểm tra định dạng và dung lượng…"
        Task { @MainActor in
            var outputURL: URL?
            var progressTask: Task<Void, Never>?
            defer {
                progressTask?.cancel()
                exportingItemIDs.remove(id)
                exportProgress[id] = nil
                exportStatus[id] = nil
            }

            do {
                let asset = AVURLAsset(url: sourceURL)
                guard try await asset.load(.isPlayable) else { throw VLCExportError.assetUnavailable }

                let candidates: [(preset: String, type: AVFileType)] = [
                    (AVAssetExportPresetPassthrough, .mp4),
                    (AVAssetExportPresetPassthrough, .mov),
                    (AVAssetExportPresetHighestQuality, .mp4),
                    (AVAssetExportPresetHighestQuality, .mov),
                    (AVAssetExportPreset1280x720, .mp4),
                    (AVAssetExportPreset1280x720, .mov)
                ]
                var selected: (session: AVAssetExportSession, type: AVFileType)?
                for candidate in candidates {
                    let compatible = await Self.isExportCompatible(asset: asset, preset: candidate.preset, type: candidate.type)
                    guard compatible,
                          let session = AVAssetExportSession(asset: asset, presetName: candidate.preset),
                          session.supportedFileTypes.contains(candidate.type) else { continue }
                    selected = (session, candidate.type)
                    break
                }
                guard let selected else { throw VLCExportError.noCompatibleFormat }

                let fileExtension = selected.type == .mov ? "mov" : "mp4"
                let destination = downloads.exportDestination(for: item, fileExtension: fileExtension)
                outputURL = destination
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                selected.session.outputURL = destination
                selected.session.outputFileType = selected.type
                selected.session.shouldOptimizeForNetworkUse = true
                exportStatus[id] = "Đang tạo bản .\(fileExtension)…"

                let exportSession = selected.session
                progressTask = Task { @MainActor in
                    while !Task.isCancelled {
                        let progress = Double(exportSession.progress)
                        if progress.isFinite { exportProgress[id] = max(exportProgress[id] ?? 0, min(1, max(0, progress))) }
                        if exportSession.status == .completed || exportSession.status == .failed || exportSession.status == .cancelled { break }
                        try? await Task.sleep(for: .milliseconds(300))
                    }
                }
                try await Self.performExport(exportSession)
                progressTask?.cancel()
                exportProgress[id] = 1

                guard let values = try? destination.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      values.isRegularFile == true, (values.fileSize ?? 0) > 0 else {
                    throw VLCExportError.emptyOutput
                }
                shareWithVLC(item, videoURL: destination)
            } catch {
                progressTask?.cancel()
                if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
                exportNotice = error.localizedDescription
            }
        }
    }

    private static func isExportCompatible(asset: AVAsset, preset: String, type: AVFileType) async -> Bool {
        await withCheckedContinuation { continuation in
            AVAssetExportSession.determineCompatibility(ofExportPreset: preset, with: asset, outputFileType: type) { compatible in
                continuation.resume(returning: compatible)
            }
        }
    }

    private static func performExport(_ session: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume(returning: ())
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                default:
                    continuation.resume(throwing: session.error ?? VLCExportError.exportFailed)
                }
            }
        }
    }

    private enum VLCExportError: LocalizedError {
        case assetUnavailable
        case noCompatibleFormat
        case emptyOutput
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .assetUnavailable: "Không đọc được package HLS đã tải để tạo tệp tương thích VLC."
            case .noCompatibleFormat: "iOS không hỗ trợ xuất package HLS này thành MP4 hoặc MOV. Bản tải vẫn còn trong Cinemora, nhưng chưa thể chuyển sang VLC."
            case .emptyOutput: "Quá trình chuyển đổi không tạo được tệp video hợp lệ."
            case .exportFailed: "Xuất video thất bại. Hãy kiểm tra dung lượng trống rồi thử lại."
            }
        }
    }

    /// Offline notice or a warning that cellular data may be consumed.
    private func networkBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: downloads.isCellular ? "antenna.radiowaves.left.and.right" : "wifi.exclamationmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.auroraAmber)
            Text(text)
                .font(.auroraBody(11))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.auroraAmber.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.auroraAmber.opacity(0.32), lineWidth: 0.8)
                }
        }
        .transition(.opacity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow(text: "TẢI VỀ · MỞ BẰNG VLC")
            AuroraGradientText(text: "Đã tải xuống", font: .auroraDisplay(28))
            Text("Bản tải được lưu trên máy. Bấm Mở bằng VLC để chia sẻ tệp MP4/MOV tương thích; package HLS sẽ được xuất trước nếu cần. Phụ đề rời đã lưu được gửi kèm thành tệp riêng để chọn trong VLC.")
                .font(.auroraBody(12))
                .foregroundStyle(Color.auroraTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Khi đang tải, dung lượng và thời gian hoàn tất là ước tính; dung lượng bản tải chính xác sẽ hiện khi hoàn tất.")
                .font(.auroraBody(10))
                .foregroundStyle(Color.auroraTextSecondary.opacity(0.9))
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
                    Text("\(doneItems.count) tập đã tải · \(downloads.activeCount) đang tải")
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
                    smallAction("Huỷ tất cả", icon: "xmark.circle", tint: .auroraAmber)
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
            Text(filter == .active ? "Đang tải song song tối đa 2 tập" : "Xoá mục sẽ xoá bản tải và tệp MP4/MOV đã xuất")
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
        let localFile = downloads.localURL(for: item)
        let vlcFile = downloads.vlcExportURL(for: item)
        let canOpenWithVLC = localFile != nil || vlcFile != nil
        let isExporting = exportingItemIDs.contains(item.id)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                PosterArt(url: downloads.posterURL(for: item), fallbackURL: connectivity.isConnected ? URL(string: item.poster ?? "", relativeTo: CinemaAPI.baseURL)?.absoluteURL : nil)
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
                    }
                }
                Spacer(minLength: 0)
            }

            if item.phase == .downloading {
                VStack(alignment: .leading, spacing: 6) {
                    if item.progress <= 0.001 {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.auroraViolet)
                            Text("Đang kết nối và chuẩn bị luồng HLS…")
                                .font(.auroraBody(10))
                                .foregroundStyle(Color.auroraTextSecondary)
                        }
                    } else {
                        ProgressBar(value: item.progress, tint: .auroraViolet)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Text(item.sizeText)
                            .font(.auroraLabel(10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Text(item.percentText)
                            .font(.auroraLabel(10, weight: .bold))
                            .foregroundStyle(Color.auroraViolet)
                    }
                    Text("Tốc độ ước tính: \(item.speedText.isEmpty ? "Đang đo…" : item.speedText)")
                        .font(.auroraBody(9))
                        .foregroundStyle(Color.auroraTextSecondary)
                    if !item.etaText.isEmpty {
                        Text("Thời gian còn lại: \(item.etaText)")
                            .font(.auroraBody(9))
                            .foregroundStyle(Color.auroraTextSecondary)
                    }
                }
            } else if item.phase == .waiting, item.message == nil {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.auroraAmber)
                    Text("Đang chờ đến lượt tải…")
                        .font(.auroraBody(10))
                        .foregroundStyle(Color.auroraTextSecondary)
                }
            } else if item.phase == .finished {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Dung lượng bản tải: \(item.sizeText)", systemImage: "internaldrive")
                        .font(.auroraBody(10))
                        .foregroundStyle(Color.auroraMint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if vlcFile != nil {
                        Label("Bản MP4/MOV sẵn sàng chia sẻ với VLC", systemImage: "checkmark.circle.fill")
                            .font(.auroraBody(10))
                            .foregroundStyle(Color.auroraMint)
                    } else if localFile != nil {
                        Label("Bản HLS sẽ được xuất sang MP4/MOV khi mở bằng VLC", systemImage: "arrow.triangle.2.circlepath")
                            .font(.auroraBody(10))
                            .foregroundStyle(Color.auroraTextSecondary)
                    } else {
                        Label("Không tìm thấy bản tải hoặc tệp VLC đã xuất", systemImage: "exclamationmark.triangle.fill")
                            .font(.auroraBody(10))
                            .foregroundStyle(Color.auroraAmber)
                    }
                }
            }

            if item.phase == .finished, let subtitleStatus = downloads.subtitleCacheStatus(for: item) {
                Label(subtitleStatus, systemImage: "captions.bubble.fill")
                    .font(.auroraBody(10))
                    .foregroundStyle(subtitleStatus.contains("đã lưu: ") ? Color.auroraMint : Color.auroraAmber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isExporting {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressBar(value: exportProgress[item.id] ?? 0, tint: .auroraSky)
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(Color.auroraSky)
                        Text(exportStatus[item.id] ?? "Đang chuẩn bị bản video cho VLC…")
                            .font(.auroraBody(10))
                            .foregroundStyle(Color.auroraTextSecondary)
                        Spacer(minLength: 0)
                        if let progress = exportProgress[item.id], progress > 0 {
                            Text("\(Int((progress * 100).rounded()))%")
                                .font(.auroraLabel(10, weight: .bold))
                                .foregroundStyle(Color.auroraSky)
                        }
                    }
                }
            }

            if let message = item.message {
                Text(message)
                    .font(.auroraBody(11))
                    .foregroundStyle(item.phase == .unsupported || message.localizedCaseInsensitiveContains("mạng") || message.localizedCaseInsensitiveContains("tiến trình") || message.localizedCaseInsensitiveContains("nguồn") ? Color.auroraAmber : Color.auroraPink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                switch item.phase {
                case .downloading, .waiting:
                    actionButton("Huỷ · tải lại từ đầu", icon: "xmark", tint: .auroraAmber) { downloads.pause(item.id) }
                case .paused, .failed:
                    actionButton("Tải lại từ đầu", icon: "arrow.clockwise", tint: .auroraMint) { downloads.retry(item.id) }
                case .finished:
                    if canOpenWithVLC {
                        actionButton(isExporting ? "Đang chuẩn bị VLC…" : "Mở bằng VLC", icon: "play.rectangle.fill", tint: .auroraMint) {
                            openWithVLC(item)
                        }
                        .disabled(isExporting)
                        .opacity(isExporting ? 0.55 : 1)
                    } else {
                        actionButton("Tải lại", icon: "arrow.clockwise", tint: .auroraMint) { downloads.retry(item.id) }
                    }
                case .unsupported:
                    actionButton("Tải lại", icon: "arrow.clockwise", tint: .auroraMint) { downloads.retry(item.id) }
                }
                Spacer(minLength: 0)
                actionButton("Xoá tải", icon: "trash", tint: .auroraPink) { pendingRemoval = item }
                    .disabled(isExporting)
                    .opacity(isExporting ? 0.45 : 1)
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

                            // Phim 1000+ tập: dựng lười từng hàng, nếu không thì mở
                            // sheet là khựng vì tạo hết mọi hàng cùng lúc.
                            LazyVStack(spacing: 8) {
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
        .modifier(EdgeBackDrag { dismiss() })
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
                        if item.progress <= 0.001 {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.auroraViolet)
                        } else {
                            ProgressBar(value: item.progress).frame(width: 140)
                        }
                        Text(item.sizeText)
                            .font(.auroraBody(9))
                            .foregroundStyle(Color.auroraTextSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Tiến trình \(item.percentText) · \(item.etaText)")
                            .font(.auroraBody(9))
                            .foregroundStyle(Color.auroraTextSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Tốc độ ước tính: \(item.speedText.isEmpty ? "Đang đo…" : item.speedText)")
                            .font(.auroraBody(9))
                            .foregroundStyle(Color.auroraTextSecondary)
                            .lineLimit(1)
                    } else {
                        Text(item.phase == .finished ? "Đã tải xong · \(item.sizeText)" : (item.message ?? item.phase.title))
                            .font(.auroraBody(10))
                            .foregroundStyle(item.phase == .finished ? Color.auroraMint : Color.auroraTextSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
            if let item, item.phase == .finished {
                if !episode.availableSubtitleTracks.isEmpty {
                    Button {
                        _ = downloads.enqueue(movie: movie, serverName: server.name, episode: episode)
                    } label: {
                        Label("Sub", systemImage: "captions.bubble")
                            .font(.auroraLabel(10, weight: .bold))
                            .foregroundStyle(Color.auroraSky)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(Color.auroraSky.opacity(0.13), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Tải và lưu riêng phụ đề rời để dùng trong VLC")
                }
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.auroraMint)
            } else if episode.playbackURL != nil {
                Button {
                    if let item, item.phase == .downloading || item.phase == .waiting {
                        downloads.pause(item.id)
                    } else if let item {
                        downloads.retry(item.id)
                    } else {
                        downloads.enqueue(movie: movie, serverName: server.name, episode: episode)
                    }
                } label: {
                    Image(systemName: item?.phase == .downloading || item?.phase == .waiting ? "xmark.circle.fill" : "arrow.clockwise.circle")
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
