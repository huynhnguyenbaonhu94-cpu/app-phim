import SwiftUI

struct AccountScreen: View {
    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    CinemaHeader(eyebrow: "CINEMORA · CÁ NHÂN HÓA", title: "TÀI KHOẢN")
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 34, weight: .light)).foregroundStyle(Color.cinemaAccent)
                            .frame(width: 64, height: 64).background(Color.cinemaAccent.opacity(0.11), in: RoundedRectangle(cornerRadius: 23))
                        Text("Không gian của bạn").font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(.white)
                        Text("Đăng nhập và đồng bộ trải nghiệm cá nhân sẽ sớm có mặt trên Cinemora.")
                            .font(.system(size: 13)).lineSpacing(5).foregroundStyle(.white.opacity(0.62))
                        HStack(spacing: 7) {
                            Circle().fill(Color.cinemaAccent).frame(width: 6, height: 6)
                            Text("ĐANG HOÀN THIỆN").font(.system(size: 9, weight: .black)).tracking(1.2).foregroundStyle(Color.cinemaAccent)
                        }
                        .padding(.horizontal, 11).padding(.vertical, 9).background(Color.cinemaAccent.opacity(0.1), in: Capsule())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(22)
                    .cinemaGlass(in: RoundedRectangle(cornerRadius: 28), tint: .white.opacity(0.06))

                    SectionHeading(eyebrow: "SẮP CÓ TRÊN CINEMORA", title: "Xem theo cách của bạn")
                    VStack(spacing: 0) {
                        feature("heart", title: "Danh sách yêu thích", detail: "Lưu lại bộ phim muốn xem.")
                        Divider().overlay(.white.opacity(0.08)).padding(.leading, 58)
                        feature("clock.arrow.circlepath", title: "Lịch sử xem", detail: "Tiếp tục đúng nơi bạn đã dừng.")
                        Divider().overlay(.white.opacity(0.08)).padding(.leading, 58)
                        feature("iphone.and.arrow.forward", title: "Đồng bộ thiết bị", detail: "Trải nghiệm liền mạch mọi lúc.")
                    }
                    .padding(.horizontal, 14).cinemaGlass(in: RoundedRectangle(cornerRadius: 24), tint: .white.opacity(0.045))
                    Text("Chức năng tài khoản cần backend đăng nhập riêng; giao diện này chưa giả lập đăng nhập hoặc lưu dữ liệu.")
                        .font(.system(size: 10)).lineSpacing(4).foregroundStyle(.white.opacity(0.42))
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 38)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func feature(_ icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.cinemaAccent)
                .frame(width: 42, height: 42).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.54))
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.28))
        }
        .padding(.vertical, 13).padding(.horizontal, 4)
    }
}
