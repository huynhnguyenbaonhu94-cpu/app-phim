import SwiftUI
import UIKit

@MainActor
enum CinemoraAppIconController {
    static var selectedOption: CinemoraAppIconOption {
        CinemoraAppIconOption(alternateName: UIApplication.shared.alternateIconName) ?? .standard
    }

    static func apply(_ option: CinemoraAppIconOption) async throws {
        guard UIApplication.shared.supportsAlternateIcons else {
            throw CinemoraAppIconError.notSupported
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            UIApplication.shared.setAlternateIconName(option.alternateName) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    static func resetIfNotPrivileged(_ hasSpecialPrivileges: Bool) {
        guard !hasSpecialPrivileges,
              UIApplication.shared.supportsAlternateIcons,
              UIApplication.shared.alternateIconName != nil else { return }
        UIApplication.shared.setAlternateIconName(nil, completionHandler: nil)
    }
}

private enum CinemoraAppIconError: LocalizedError {
    case notSupported

    var errorDescription: String? {
        "Thiết bị hoặc cấu hình ứng dụng hiện không hỗ trợ đổi biểu tượng."
    }
}

enum CinemoraAppIconOption: String, CaseIterable, Identifiable {
    case standard
    case gold
    case violet
    case emerald
    case silver
    case ruby
    case sapphire
    case roseCopper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Cinemora gốc"
        case .gold: return "Aurora Gold"
        case .violet: return "Midnight Violet"
        case .emerald: return "Emerald Reel"
        case .silver: return "Platinum Reel"
        case .ruby: return "Ruby Cinema"
        case .sapphire: return "Sapphire Screen"
        case .roseCopper: return "Rose Copper"
        }
    }

    var subtitle: String {
        switch self {
        case .standard: return "Biểu tượng Cinemora ban đầu"
        case .gold: return "Sang trọng, ánh vàng điện ảnh"
        case .violet: return "Tím huyền ảo, điểm cyan"
        case .emerald: return "Xanh ngọc, cảm hứng cuộn phim"
        case .silver: return "Bạch kim tối giản, ánh kim lạnh"
        case .ruby: return "Đỏ ruby sâu, cảm hứng rạp phim"
        case .sapphire: return "Xanh sapphire trên nền midnight"
        case .roseCopper: return "Đồng hồng ấm, ánh champagne"
        }
    }

    var alternateName: String? {
        switch self {
        case .standard: return nil
        case .gold: return "CinemoraGold"
        case .violet: return "CinemoraViolet"
        case .emerald: return "CinemoraEmerald"
        case .silver: return "CinemoraSilver"
        case .ruby: return "CinemoraRuby"
        case .sapphire: return "CinemoraSapphire"
        case .roseCopper: return "CinemoraRoseCopper"
        }
    }

    var symbol: String {
        switch self {
        case .standard: return "sparkles.tv.fill"
        case .gold: return "play.rectangle.fill"
        case .violet: return "camera.aperture"
        case .emerald: return "film.stack.fill"
        case .silver: return "sparkles"
        case .ruby: return "play.rectangle.on.rectangle.fill"
        case .sapphire: return "sparkle.magnifyingglass"
        case .roseCopper: return "film.fill"
        }
    }

    var previewAssetName: String {
        switch self {
        case .standard: return "CinemoraDefaultPreview"
        case .gold: return "CinemoraGoldPreview"
        case .violet: return "CinemoraVioletPreview"
        case .emerald: return "CinemoraEmeraldPreview"
        case .silver: return "CinemoraSilverPreview"
        case .ruby: return "CinemoraRubyPreview"
        case .sapphire: return "CinemoraSapphirePreview"
        case .roseCopper: return "CinemoraRoseCopperPreview"
        }
    }

    var colors: [Color] {
        switch self {
        case .standard: return [.auroraRaised, .auroraVoid]
        case .gold: return [Color(red: 0.10, green: 0.16, blue: 0.18), Color(red: 0.66, green: 0.43, blue: 0.12)]
        case .violet: return [Color(red: 0.12, green: 0.08, blue: 0.24), Color(red: 0.34, green: 0.20, blue: 0.67)]
        case .emerald: return [Color(red: 0.04, green: 0.17, blue: 0.15), Color(red: 0.08, green: 0.49, blue: 0.38)]
        case .silver: return [Color(red: 0.10, green: 0.12, blue: 0.15), Color(red: 0.55, green: 0.61, blue: 0.70)]
        case .ruby: return [Color(red: 0.16, green: 0.04, blue: 0.06), Color(red: 0.67, green: 0.12, blue: 0.21)]
        case .sapphire: return [Color(red: 0.03, green: 0.08, blue: 0.18), Color(red: 0.08, green: 0.34, blue: 0.75)]
        case .roseCopper: return [Color(red: 0.16, green: 0.08, blue: 0.08), Color(red: 0.70, green: 0.36, blue: 0.30)]
        }
    }

    var accent: Color {
        switch self {
        case .standard: return .auroraAccent
        case .gold: return Color(red: 1.0, green: 0.79, blue: 0.31)
        case .violet: return Color(red: 0.78, green: 0.68, blue: 1.0)
        case .emerald: return Color(red: 0.44, green: 0.96, blue: 0.72)
        case .silver: return Color(red: 0.83, green: 0.88, blue: 0.96)
        case .ruby: return Color(red: 1.0, green: 0.38, blue: 0.48)
        case .sapphire: return Color(red: 0.42, green: 0.68, blue: 1.0)
        case .roseCopper: return Color(red: 1.0, green: 0.67, blue: 0.57)
        }
    }

    init?(alternateName: String?) {
        guard let alternateName else { self = .standard; return }
        guard let option = Self.allCases.first(where: { $0.alternateName == alternateName }) else { return nil }
        self = option
    }
}

struct SpecialAppIconPickerScreen: View {
    @Environment(ConnectivityMonitor.self) private var connectivity
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: CinemoraAppIconOption = .standard
    @State private var applying: CinemoraAppIconOption?
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private let columns = [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)]

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 9) {
                        Image(systemName: "app.dashed")
                            .foregroundStyle(Color.auroraAccent)
                        Text("BIỂU TƯỢNG CỦA BẠN")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .tracking(1.8)
                            .foregroundStyle(Color.auroraTextSecondary)
                    }
                    Text("Chọn diện mạo Cinemora")
                        .font(.auroraDisplay(25))
                        .foregroundStyle(.white)
                    Text("Biểu tượng được đổi trực tiếp trên màn hình chính của iPhone. Đặc quyền này gắn với tài khoản được admin cấp.")
                        .font(.auroraBody(12))
                        .foregroundStyle(Color.auroraTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    LazyVGrid(columns: columns, spacing: 11) {
                        ForEach(CinemoraAppIconOption.allCases) { option in
                            iconCard(option)
                        }
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.auroraBody(11))
                            .foregroundStyle(Color.auroraPink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let successMessage {
                        Label(successMessage, systemImage: "checkmark.circle.fill")
                            .font(.auroraBody(11, weight: .semibold))
                            .foregroundStyle(Color.auroraMint)
                    }
                    Text("Nếu bạn đăng xuất hoặc chuyển sang tài khoản không có đặc quyền, icon sẽ tự trở về Cinemora gốc.")
                        .font(.auroraBody(10))
                        .foregroundStyle(Color.auroraTextTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                .padding(.top, 58)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .topLeading) {
            AuroraBackButton(title: "Biểu tượng app") { dismiss() }
                .padding(.leading, 20)
                .padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .animation(reduceMotion ? nil : Motion.gentle, value: selected)
        .onAppear { selected = CinemoraAppIconController.selectedOption }
        .overlay {
            if !connectivity.isConnected {
                NetworkUnavailableOverlay()
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
    }

    private func iconCard(_ option: CinemoraAppIconOption) -> some View {
        let isSelected = selected == option
        return Button {
            guard applying == nil, !isSelected else { return }
            Task { await apply(option) }
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                ZStack(alignment: .topTrailing) {
                    Image(option.previewAssetName)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .background(Circle().fill(Color.auroraVoid.opacity(0.72)).padding(-2))
                            .padding(9)
                    } else if applying == option {
                        ProgressView().tint(.white).padding(11)
                    }
                }
                Text(option.title)
                    .font(.auroraLabel(11, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(option.subtitle)
                    .font(.auroraBody(9))
                    .foregroundStyle(Color.auroraTextSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(isSelected ? "ĐANG DÙNG" : "CHỌN BIỂU TƯỢNG")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(isSelected ? Color.auroraMint : option.accent)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(Color.auroraRaised.opacity(0.88), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .strokeBorder(isSelected ? option.accent.opacity(0.62) : Color.white.opacity(0.08), lineWidth: isSelected ? 1.2 : 0.8)
            }
        }
        .buttonStyle(.auroraPress(scale: 0.97))
        .disabled(applying != nil)
        .accessibilityLabel("\(option.title). \(isSelected ? "Đang dùng" : "Chọn biểu tượng")")
    }

    @MainActor
    private func apply(_ option: CinemoraAppIconOption) async {
        applying = option
        errorMessage = nil
        successMessage = nil
        do {
            try await CinemoraAppIconController.apply(option)
            selected = option
            successMessage = "Đã đổi biểu tượng ứng dụng."
        } catch {
            errorMessage = error.localizedDescription
        }
        applying = nil
    }
}
