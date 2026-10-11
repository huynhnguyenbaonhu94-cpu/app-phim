import SwiftUI
import UniformTypeIdentifiers

/// Khối cài đặt thư mục lưu phim tải về, dùng chung trong màn Đã tải xuống.
struct DownloadFolderSection: View {
    @Environment(DownloadManager.self) private var downloads
    @State private var showFolderPicker = false
    @State private var showBrowser = false
    @State private var showResetConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            currentFolderCard
            storageRow

            if let message = downloads.folderMessage {
                Text(message)
                    .font(.auroraBody(11))
                    .foregroundStyle(Color.auroraAmber)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }

            VStack(spacing: 10) {
                primaryButton("Xem tệp đã tải", icon: "folder") { showBrowser = true }
                secondaryRow("Chọn thư mục khác", icon: "folder.badge.plus") { showFolderPicker = true }
                secondaryRow("Sao chép đường dẫn", icon: "doc.on.doc") { downloads.copyFolderPath() }
                secondaryRow("Dùng thư mục mặc định", icon: "arrow.uturn.backward", enabled: !downloads.isUsingDefaultFolder) {
                    showResetConfirm = true
                }
            }
        }
        .sheet(isPresented: $showBrowser) {
            DownloadedFilesBrowser()
        }
        .sheet(isPresented: $showFolderPicker) {
            FolderPicker { url in
                if let url { downloads.chooseFolder(url) }
            }
            .ignoresSafeArea()
        }
        .alert("Dùng lại thư mục mặc định?", isPresented: $showResetConfirm) {
            Button("Dùng mặc định") { downloads.useDefaultFolder() }
            Button("Huỷ", role: .cancel) { }
        } message: {
            Text("Các tập đã tải sẽ được chuyển về thư mục mặc định của Cinemora. Tệp không chuyển được vẫn nằm ở thư mục cũ.")
        }
    }

    private var currentFolderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.auroraSky.opacity(0.16))
                        .frame(width: 42, height: 42)
                    Image(systemName: downloads.isUsingDefaultFolder ? "folder.fill" : "folder.badge.gearshape")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.auroraSky)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(downloads.folderName)
                        .font(.auroraLabel(13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(downloads.isUsingDefaultFolder ? "Thư mục mặc định của Cinemora" : "Thư mục bạn đã chọn")
                        .font(.auroraBody(11))
                        .foregroundStyle(Color.auroraTextSecondary)
                }
                Spacer(minLength: 0)
                if downloads.isUsingDefaultFolder {
                    Text("MẶC ĐỊNH")
                        .font(.auroraLabel(9, weight: .black))
                        .foregroundStyle(Color.auroraMint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.auroraMint.opacity(0.14), in: Capsule())
                }
            }
            Text(downloads.folderPath)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.auroraTextSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .auroraCard(cornerRadius: 22, tint: .auroraSky)
    }

    private var storageRow: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Đã tải: \(downloads.totalSizeText)")
                    .font(.auroraLabel(12, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(downloads.finishedCount) tập trong máy")
                    .font(.auroraBody(11))
                    .foregroundStyle(Color.auroraTextSecondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                Text("Còn trống")
                    .font(.auroraBody(10))
                    .foregroundStyle(Color.auroraTextSecondary)
                Text(downloads.freeSpaceText)
                    .font(.auroraLabel(12, weight: .bold))
                    .foregroundStyle(Color.auroraMint)
            }
        }
        .padding(16)
        .auroraCard(cornerRadius: 20, tint: .auroraMint)
    }

    private func primaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 13, weight: .bold))
                Text(title).font(.auroraLabel(13, weight: .bold))
            }
            .foregroundStyle(Color.auroraVoid)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(LinearGradient(colors: [.auroraViolet, .auroraPink], startPoint: .leading, endPoint: .trailing), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func secondaryRow(_ title: String, icon: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 13, weight: .bold))
                Text(title).font(.auroraLabel(13, weight: .bold))
            }
            .foregroundStyle(enabled ? Color.auroraViolet : Color.auroraTextSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background((enabled ? Color.auroraViolet : Color.white).opacity(enabled ? 0.14 : 0.06), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.6)
    }
}

/// Duyệt các tệp đã tải **ngay trong app**: cùng kiểu danh sách tệp của bộ chọn
/// thư mục, nhưng có thêm dung lượng, nút chia sẻ và xoá cho từng tệp.
struct DownloadedFilesBrowser: View {
    @Environment(DownloadManager.self) private var downloads
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [FileEntry] = []
    @State private var pendingRemoval: FileEntry?
    @State private var errorText: String?

    struct FileEntry: Identifiable {
        var id: String { url.lastPathComponent }
        let url: URL
        let size: Int64
        let date: Date
        var sizeText: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CinemaBackground()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(downloads.folderName)
                                .font(.auroraLabel(13, weight: .bold))
                                .foregroundStyle(.white)
                            Text(downloads.folderPath)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.auroraTextSecondary)
                                .lineLimit(2)
                            Text("\(entries.count) tệp · \(ByteCountFormatter.string(fromByteCount: entries.reduce(0) { $0 + $1.size }, countStyle: .file))")
                                .font(.auroraBody(11))
                                .foregroundStyle(Color.auroraTextSecondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .auroraCard(cornerRadius: 20, tint: .auroraSky)

                        if let errorText {
                            Text(errorText)
                                .font(.auroraBody(11))
                                .foregroundStyle(Color.auroraPink)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .auroraCard(cornerRadius: 14, tint: .auroraPink)
                        }

                        if entries.isEmpty {
                            Text("Thư mục đang trống. Hãy tải một tập phim về máy trước.")
                                .font(.auroraBody(12))
                                .foregroundStyle(Color.auroraTextSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 30)
                                .auroraCard(cornerRadius: 20, tint: .auroraViolet)
                        } else {
                            ForEach(entries) { entry in
                                entryRow(entry)
                            }
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Tệp đã tải")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") { dismiss() }
                        .font(.auroraLabel(12, weight: .bold))
                        .foregroundStyle(Color.auroraViolet)
                }
            }
            .alert("Xoá tệp này?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
                Button("Xoá tệp", role: .destructive) {
                    if let entry = pendingRemoval { remove(entry) }
                    pendingRemoval = nil
                }
                Button("Giữ lại", role: .cancel) { pendingRemoval = nil }
            } message: {
                Text(pendingRemoval.map { "\($0.url.lastPathComponent) sẽ bị xoá khỏi máy." } ?? "")
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: reload)
    }

    private func entryRow(_ entry: FileEntry) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.auroraViolet.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: "film")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.auroraViolet)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.url.lastPathComponent)
                    .font(.auroraLabel(11, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text("\(entry.sizeText) · \(entry.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.auroraBody(10))
                    .foregroundStyle(Color.auroraTextSecondary)
            }
            Spacer(minLength: 0)
            ShareLink(item: entry.url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.auroraSky)
            }
            Button {
                pendingRemoval = entry
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.auroraPink)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .auroraCard(cornerRadius: 16, tint: .auroraSky)
    }

    private func reload() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: downloads.root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []
        entries = urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return FileEntry(
                url: url,
                size: Int64(values?.fileSize ?? 0),
                date: values?.contentModificationDate ?? Date()
            )
        }
        .sorted { $0.date > $1.date }
    }

    /// Xoá tệp trong thư mục và bỏ luôn mục tương ứng trong danh sách tải xuống.
    private func remove(_ entry: FileEntry) {
        guard downloads.deleteFile(at: entry.url) else {
            errorText = "Không xoá được tệp này. Hãy kiểm tra quyền truy cập thư mục rồi thử lại."
            return
        }
        errorText = nil
        reload()
    }
}

/// Bộ chọn thư mục của hệ thống. Trả về `nil` khi người dùng huỷ.
struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // `asCopy: false` để nhận đúng thư mục (không sao chép nội dung ra ngoài).
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        controller.allowsMultipleSelection = false
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) { }

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL?) -> Void

        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}
