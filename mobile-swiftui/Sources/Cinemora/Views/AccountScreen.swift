import SwiftUI

struct AccountScreen: View {
    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CinemaHeader(eyebrow: "CINEMORA · GIẢI TRÍ", title: "THÔNG TIN ỨNG DỤNG")
                    VStack(alignment: .leading, spacing: 15) {
                        Image(systemName: "sparkles.tv.fill")
                            .font(.system(size: 38, weight: .black))
                            .foregroundStyle(Color.cinemaAccent)
                            .frame(width: 70, height: 70)
                            .background(Color.cinemaAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
                        Text("Xem phim đơn giản hơn")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Khám phá phim mới, tìm kiếm nội dung yêu thích và thưởng thức phim với trình phát toàn màn hình.")
                            .font(.system(size: 13))
                            .lineSpacing(5)
                            .foregroundStyle(.white.opacity(0.62))
                        Divider().overlay(.white.opacity(0.12))
                        infoRow(icon: "play.rectangle.fill", title: "Trình phát toàn màn hình", detail: "Hỗ trợ xoay ngang, tua phim, tốc độ phát và tỷ lệ khung hình.")
                        infoRow(icon: "magnifyingglass", title: "Tìm kiếm phim", detail: "Tìm nhanh phim và chương trình bạn muốn xem.")
                        infoRow(icon: "wifi", title: "Luôn cập nhật", detail: "Danh sách phim được tải trực tiếp từ nguồn phim hiện tại.")
                    }
                    .padding(22)
                    .cinemaGlass(in: RoundedRectangle(cornerRadius: 28), tint: .white.opacity(0.06))
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 38)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func infoRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.cinemaAccent)
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.52)).lineSpacing(3)
            }
        }
    }
}
