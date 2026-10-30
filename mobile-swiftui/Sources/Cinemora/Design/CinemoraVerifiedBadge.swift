import SwiftUI

/// Huy hiệu xác minh riêng cho tài khoản được quản trị viên cấp đặc quyền.
/// Chỉ chạy một nhịp xuất hiện ngắn để vẫn nhẹ khi có nhiều bình luận trên màn hình.
struct CinemoraVerifiedBadge: View {
    var size: CGFloat = 15
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color(red: 0.34, green: 0.79, blue: 1.0), Color(red: 0.12, green: 0.43, blue: 0.96)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Circle()
                .strokeBorder(Color.white.opacity(0.42), lineWidth: max(size * 0.055, 0.7))
                .padding(size * 0.05)
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.52, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .offset(y: -0.2)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(red: 0.12, green: 0.48, blue: 1).opacity(0.42), radius: size * 0.36, y: 1)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.66)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .onAppear {
            guard !reduceMotion, !appeared else { appeared = true; return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.58)) { appeared = true }
        }
        .accessibilityLabel("Tài khoản đã xác minh")
    }
}
