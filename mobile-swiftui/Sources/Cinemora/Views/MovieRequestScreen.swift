import PhotosUI
import SwiftUI
import UIKit

struct MovieRequestScreen: View {
    @State private var title = ""
    @State private var link = ""
    @State private var priority = "Bình thường"
    @State private var notes = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var imagePreview: UIImage?
    @State private var isSubmitting = false
    @State private var message: String?
    @State private var showSuccess = false
    @FocusState private var focusedField: String?

    private let priorities = ["Thấp", "Bình thường", "Cao", "Khẩn cấp"]

    private var canSubmit: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 && !isSubmitting
    }

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        SectionEyebrow(text: "CINEMORA · ĐÓNG GÓP")
                        AuroraGradientText(text: "Yêu cầu phim", font: .auroraDisplay(29))
                        Text("Gửi yêu cầu phim bạn muốn xem. Chúng tôi sẽ cố gắng cập nhật sớm nhất có thể!")
                            .font(.auroraBody(12))
                            .foregroundStyle(Color.auroraTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .auroraReveal(0)

                    requestField(title: "Tên phim", placeholder: "Tên phim, tên gốc, năm sản xuất, quốc gia…", text: $title, id: "title", icon: "film")
                        .auroraReveal(1)
                    requestField(title: "Link TMDB hoặc IMDB (nếu có)", placeholder: "https://www.imdb.com/title/…", text: $link, id: "link", icon: "link")
                        .auroraReveal(2)

                    VStack(alignment: .leading, spacing: 10) {
                        SectionEyebrow(text: "MỨC ĐỘ ƯU TIÊN")
                        HStack(spacing: 8) {
                            ForEach(priorities, id: \.self) { value in
                                AuroraChip(title: value, selected: priority == value, icon: chipIcon(value)) {
                                    withAnimation(Motion.gentle) { priority = value }
                                }
                            }
                        }
                    }
                    .auroraReveal(3)

                    VStack(alignment: .leading, spacing: 10) {
                        SectionEyebrow(text: "GHI CHÚ THÊM (NẾU CÓ)")
                        TextEditor(text: $notes)
                            .font(.auroraBody(13))
                            .foregroundStyle(.white)
                            .scrollContentBackground(.hidden)
                            .focused($focusedField, equals: "notes")
                            .padding(12)
                            .frame(minHeight: 130)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Color.auroraViolet.opacity(focusedField == "notes" ? 0.55 : 0.1), lineWidth: focusedField == "notes" ? 1.2 : 0.8)
                            }
                            .animation(Motion.gentle, value: focusedField)
                    }
                    .auroraReveal(4)

                    VStack(alignment: .leading, spacing: 10) {
                        SectionEyebrow(text: "HÌNH ẢNH (NẾU CÓ)")
                        PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                            HStack(spacing: 8) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 12, weight: .bold))
                                Text(imagePreview == nil ? "Chọn hình ảnh" : "Đổi hình ảnh")
                                    .font(.auroraLabel(12, weight: .bold))
                            }
                            .foregroundStyle(Color.auroraVoid)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(LinearGradient.auroraPrimary))
                        }
                        .buttonStyle(.auroraPress(scale: 0.96))
                        .onChange(of: selectedPhoto) { _, item in
                            guard let item else { return }
                            Task {
                                guard let data = try? await item.loadTransferable(type: Data.self),
                                      let image = UIImage(data: data),
                                      let compressed = Self.prepareImageData(image) else { return }
                                await MainActor.run {
                                    withAnimation(Motion.enter) {
                                        imagePreview = image
                                        imageData = compressed
                                    }
                                }
                            }
                        }
                        if let preview = imagePreview {
                            VStack(alignment: .leading, spacing: 9) {
                                Image(uiImage: preview)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .strokeBorder(LinearGradient.auroraVeil, lineWidth: 0.9)
                                    }
                                    .shadow(color: Color.black.opacity(0.4), radius: 16, y: 10)
                                Button {
                                    withAnimation(Motion.enter) {
                                        selectedPhoto = nil
                                        imagePreview = nil
                                        imageData = nil
                                    }
                                } label: {
                                    Label("Gỡ ảnh đã chọn", systemImage: "trash")
                                        .font(.auroraLabel(11, weight: .bold))
                                        .foregroundStyle(Color.auroraPink)
                                }
                                .buttonStyle(.auroraPress(scale: 0.95))
                                .accessibilityLabel("Xóa ảnh đã chọn")
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                    .auroraReveal(5)

                    if let message {
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.auroraAmber)
                            Text(message)
                                .font(.auroraBody(11, weight: .medium))
                                .foregroundStyle(Color.auroraAmber)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.auroraAmber.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.auroraAmber.opacity(0.28), lineWidth: 0.8)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    AuroraPrimaryButton(
                        title: isSubmitting ? "Đang gửi…" : "Gửi yêu cầu phim",
                        icon: "paperplane.fill",
                        loading: isSubmitting,
                        enabled: canSubmit
                    ) {
                        submit()
                    }
                    .auroraReveal(6)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .auroraDismissKeyboardOnTap()
        }
        .animation(Motion.enter, value: message)
        .animation(Motion.enter, value: imagePreview == nil)
        .navigationTitle("Yêu cầu phim")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Đã gửi yêu cầu", isPresented: $showSuccess) {
            Button("Đóng", role: .cancel) { }
        } message: {
            Text("Cảm ơn bạn. Yêu cầu phim đã được gửi đến đội ngũ Cinemora.")
        }
    }

    private func chipIcon(_ value: String) -> String {
        switch value {
        case "Thấp": return "arrow.down"
        case "Cao": return "arrow.up"
        case "Khẩn cấp": return "exclamationmark.2"
        default: return "equal"
        }
    }

    private func requestField(title: String, placeholder: String, text: Binding<String>, id: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: title.uppercased())
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(focusedField == id ? Color.auroraViolet : Color.white.opacity(0.45))
                    .frame(width: 20)
                    .padding(.top, 2)
                TextField(placeholder, text: text, axis: .vertical)
                    .font(.auroraBody(13))
                    .foregroundStyle(.white)
                    .lineLimit(1...3)
                    .focused($focusedField, equals: id)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(Color.auroraViolet.opacity(focusedField == id ? 0.55 : 0.1), lineWidth: focusedField == id ? 1.2 : 0.8)
            }
            .animation(Motion.gentle, value: focusedField)
        }
    }

    private static func prepareImageData(_ image: UIImage) -> Data? {
        let longestSide = max(image.size.width, image.size.height)
        let scale = min(1, 1600 / max(longestSide, 1))
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        var quality: CGFloat = 0.68
        var data = renderer.jpegData(withCompressionQuality: quality) { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        while data.count > 7 * 1024 * 1024 && quality > 0.28 {
            quality -= 0.08
            data = renderer.jpegData(withCompressionQuality: quality) { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
        }
        return data.count <= 7 * 1024 * 1024 ? data : nil
    }

    private func submit() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanTitle.count >= 2, !isSubmitting else { return }
        focusedField = nil
        isSubmitting = true
        message = nil
        Task {
            do {
                try await CinemaAPI.shared.submitMovieRequest(
                    title: cleanTitle,
                    link: link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : link.trimmingCharacters(in: .whitespacesAndNewlines),
                    priority: priority,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    imageData: imageData,
                    imageMimeType: imageData == nil ? nil : "image/jpeg"
                )
                await MainActor.run {
                    isSubmitting = false
                    showSuccess = true
                    title = ""
                    link = ""
                    notes = ""
                    imageData = nil
                    imagePreview = nil
                    selectedPhoto = nil
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    message = error.localizedDescription
                }
            }
        }
    }
}
