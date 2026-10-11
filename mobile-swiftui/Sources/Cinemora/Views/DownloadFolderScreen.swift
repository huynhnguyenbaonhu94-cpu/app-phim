import SwiftUI
import UniformTypeIdentifiers

/// Cài đặt thư mục lưu phim tải về: mặc định trong app, hoặc thư mục do người
/// dùng chọn trong app Tệp (giữ quyền ghi bằng security-scoped bookmark).
struct DownloadFolderScreen: View {
    @Environment(DownloadManager.self) private var downloads
    @State private var showPicker = false
    @State private var showResetConfirm = false

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionEyebrow(text: "CÀI ĐẶT TẢI XUỐNG")
                        AuroraGradientText(text: "Thư mục tải xuống", font: .auroraDisplay(26))
                        Text("Phim tải về được lưu trong thư mục này. Chọn thư mục khác trong app Tệp để dễ sao lưu hoặc chuyển sang máy khác.")
                            .font(.auroraBody(12))
                            .foregroundStyle(Color.auroraTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 18)

                    currentFolderCard
                    storageCard

                    if let message = downloads.folderMessage {
                        Text(message)
                            .font(.auroraBody(11))
                            .foregroundStyle(Color.auroraAmber)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }

                    VStack(spacing: 10) {
                        primaryButton("Chọn thư mục khác", icon: "folder.badge.plus") {
                            showPicker = true
                        }
                        secondaryButton("Mở thư mục", icon: "folder") {
                            downloads.openCurrentFolder()
                        }
                        secondaryButton("Dùng thư mục mặc định", icon: "arrow.uturn.backward", enabled: !downloads.isUsingDefaultFolder) {
                            showResetConfirm = true
                        }
                    }

                    Text("Lưu ý: iOS cho phép app ghi vào thư mục bạn chọn thông qua quyền truy cập do hệ thống cấp. Nếu bạn xoá app Tệp hoặc thu hồi quyền, Cinemora sẽ tự quay về thư mục mặc định.")
                        .font(.auroraBody(11))
                        .foregroundStyle(Color.auroraTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showPicker) {
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

    private var storageCard: some View {
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

    private func secondaryButton(_ title: String, icon: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
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
