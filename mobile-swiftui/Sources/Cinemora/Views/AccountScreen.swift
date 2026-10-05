import SwiftUI

struct AccountScreen: View {
    @EnvironmentObject private var store: CinemaStore
    @Environment(\.dismiss) private var dismiss
    let forceLogin: Bool
    @State private var isRegistering = false
    @State private var showLogoutAllConfirmation = false
    @State private var showPasswordSheet = false

    init(forceLogin: Bool = false) { self.forceLogin = forceLogin }

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if let user = store.accountUser {
                        accountSummary(user)
                        deviceSection
                        syncSection
                        accountActions
                    } else {
                        loginForm
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, forceLogin ? 40 : 18)
                .padding(.bottom, 42)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if store.accountUser != nil { await store.refreshAccountDevices() }
        }
        .sheet(isPresented: $showPasswordSheet) { ChangePasswordSheet() .environmentObject(store) }
        .confirmationDialog("Đăng xuất tất cả thiết bị?", isPresented: $showLogoutAllConfirmation, titleVisibility: .visible) {
            Button("Đăng xuất tất cả thiết bị", role: .destructive) { Task { _ = await store.logoutAllDevices() } }
            Button("Hủy", role: .cancel) { }
        } message: {
            Text("Tất cả phiên, kể cả thiết bị hiện tại, sẽ bị kết thúc.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                if !forceLogin {
                    Button { dismiss() } label: {
                        Label("Trở lại", systemImage: "chevron.left")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 13).padding(.vertical, 9)
                            .background(.white.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if store.accountSyncing {
                    ProgressView().tint(Color.cinemaAccent).scaleEffect(0.85)
                }
            }
            SectionEyebrow(text: "CINEMORA ACCOUNT")
            Text(store.accountUser == nil ? "Tài khoản" : "Tài khoản của bạn")
                .font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(.white)
            if let message = store.requiresLoginMessage, forceLogin {
                Label(message, systemImage: "exclamationmark.shield.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            } else {
                Text("Đồng bộ lịch sử xem, yêu thích và tùy chọn giữa các thiết bị.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private func accountSummary(_ user: AccountUser) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 35)).foregroundStyle(Color.cinemaAccent)
            VStack(alignment: .leading, spacing: 4) {
                Text(user.name ?? "Cinemora member").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text(user.email ?? "").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.62))
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.cinemaAccent)
        }
        .padding(16)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.1), lineWidth: 0.7))
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("THIẾT BỊ ĐANG ĐĂNG NHẬP").font(.system(size: 10, weight: .black, design: .rounded)).tracking(1).foregroundStyle(Color.cinemaAccent)
                Spacer()
                Text("\(store.accountDevices.count) / 5").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.65))
                Button { Task { await store.refreshAccountDevices() } } label: { Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) }
                    .buttonStyle(.plain).disabled(store.accountBusy)
            }
            if store.accountDevices.isEmpty && !store.accountBusy {
                StateMessage(icon: "iphone.slash", title: "Chưa tải được thiết bị", detail: "Kiểm tra kết nối rồi thử làm mới.")
            }
            ForEach(store.accountDevices) { device in
                AccountDeviceRow(device: device) {
                    Task { await store.kickDevice(device) }
                }
            }
        }
        .padding(15)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.09), lineWidth: 0.7))
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: store.accountSyncPending ? "arrow.triangle.2.circlepath" : "checkmark.icloud.fill")
                    .foregroundStyle(store.accountSyncPending ? .orange : Color.cinemaAccent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.accountSyncPending ? "Có thay đổi đang chờ đồng bộ" : "Dữ liệu đã đồng bộ")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    Text("\(store.localHistory.count) mục lịch sử · \(store.localFavorites.count) phim yêu thích")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.56))
                }
                Spacer()
                Button { Task { await store.syncAccountData() } } label: {
                    if store.accountSyncing { ProgressView().tint(Color.cinemaAccent) }
                    else { Text("Đồng bộ").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.cinemaAccent) }
                }
                .disabled(store.accountSyncing)
            }
            if let error = store.accountError {
                Text(error).font(.system(size: 11, weight: .medium)).foregroundStyle(.red.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Thay đổi vẫn được lưu trên thiết bị khi offline; app sẽ tự thử đồng bộ lại.")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.48))
        }
        .padding(15)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var accountActions: some View {
        VStack(spacing: 10) {
            actionButton("Đổi mật khẩu", icon: "key.horizontal") { showPasswordSheet = true }
            actionButton("Đăng xuất tất cả thiết bị", icon: "rectangle.portrait.and.arrow.right", destructive: true) { showLogoutAllConfirmation = true }
            actionButton("Đăng xuất thiết bị này", icon: "rectangle.portrait.and.arrow.right") { Task { await store.signOut() } }
        }
    }

    private var loginForm: some View {
        VStack(alignment: .leading, spacing: 13) {
            if isRegistering {
                accountField("Tên hiển thị", text: $name, icon: "person")
            }
            accountField("Email", text: $email, icon: "envelope", email: true)
            SecureField("Mật khẩu", text: $password)
                .textContentType(isRegistering ? .newPassword : .password)
                .textInputAutocapitalization(.never)
                .padding(14).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
            if isRegistering {
                SecureField("Nhập lại mật khẩu", text: $confirmPassword)
                    .textContentType(.newPassword).textInputAutocapitalization(.never)
                    .padding(14).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            if let error = store.accountError {
                Text(error).font(.system(size: 11, weight: .medium)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Button {
                guard !store.accountBusy else { return }
                if isRegistering {
                    guard password == confirmPassword else { store.setAccountError("Hai mật khẩu không khớp."); return }
                    Task { await store.createAccount(name: name, email: email, password: password) }
                } else { Task { await store.signIn(email: email, password: password) } }
            } label: {
                HStack {
                    if store.accountBusy { ProgressView().tint(.black) }
                    Text(isRegistering ? "TẠO TÀI KHOẢN" : "ĐĂNG NHẬP")
                        .font(.system(size: 12, weight: .black, design: .rounded)).tracking(0.8)
                }
                .foregroundStyle(.black).frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(Color.cinemaAccent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain).disabled(store.accountBusy)
            Button(isRegistering ? "Đã có tài khoản? Đăng nhập" : "Chưa có tài khoản? Đăng ký") {
                isRegistering.toggle(); store.setAccountError(nil); password = ""; confirmPassword = ""
            }
            .font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.72)).frame(maxWidth: .infinity).padding(.top, 3)
            if !forceLogin {
                Button("Tiếp tục xem khi chưa đăng nhập") { dismiss() }
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.48)).frame(maxWidth: .infinity).padding(.top, 8)
            }
            Text("Mật khẩu được băm và xác thực ở máy chủ; ứng dụng chỉ lưu token phiên trong Keychain.")
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.38)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    private func accountField(_ title: String, text: Binding<String>, icon: String, email: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Color.cinemaAccent).frame(width: 18)
            TextField(title, text: text)
                .textInputAutocapitalization(email ? .never : .words)
                .autocorrectionDisabled(email)
                .keyboardType(email ? .emailAddress : .default)
                .textContentType(email ? .emailAddress : .name)
                .foregroundStyle(.white)
        }
        .padding(14).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    private func actionButton(_ title: String, icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .bold)).foregroundStyle(destructive ? .red : .white)
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

private struct AccountDeviceRow: View {
    let device: AccountDevice
    let kick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: device.name.lowercased().contains("ipad") ? "ipad" : "iphone")
                    .foregroundStyle(Color.cinemaAccent)
                Text(device.name).font(.system(size: 12, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 4)
                Circle().fill(device.isOnline ? .green : .gray).frame(width: 7, height: 7)
                Text(device.isOnline ? "Online" : "Offline").font(.system(size: 9, weight: .bold)).foregroundStyle(device.isOnline ? .green : .gray)
            }
            HStack {
                Text([device.model, device.osVersion.map { "iOS \($0)" }].compactMap { $0 }.joined(separator: " · "))
                Spacer()
                if device.isCurrent { Text("THIẾT BỊ HIỆN TẠI").foregroundStyle(Color.cinemaAccent) }
            }
            .font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.56))
            HStack {
                Text("IP: \(device.ipAddress ?? "Không xác định")")
                Spacer()
                Text("Hoạt động: \(relative(device.lastSeenAt))")
            }
            .font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.43))
            if !device.isCurrent {
                Button(role: .destructive, action: kick) {
                    Text("Kết thúc phiên").font(.system(size: 10, weight: .bold)).foregroundStyle(.red)
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
    }

    private func relative(_ raw: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) else { return "vừa cập nhật" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

private struct ChangePasswordSheet: View {
    @EnvironmentObject private var store: CinemaStore
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var showLogoutPrompt = false

    var body: some View {
        ZStack {
            CinemaBackground()
            VStack(alignment: .leading, spacing: 14) {
                Text("Đổi mật khẩu").font(.system(size: 25, weight: .black, design: .rounded)).foregroundStyle(.white)
                SecureField("Mật khẩu hiện tại", text: $current).passwordFieldStyle()
                SecureField("Mật khẩu mới (ít nhất 10 ký tự)", text: $newPassword).passwordFieldStyle()
                SecureField("Nhập lại mật khẩu mới", text: $confirmation).passwordFieldStyle()
                if let error = store.accountError { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
                Button {
                    guard newPassword == confirmation else { store.setAccountError("Hai mật khẩu mới không khớp."); return }
                    Task {
                        if await store.changePassword(current: current, new: newPassword) { showLogoutPrompt = true }
                    }
                } label: {
                    HStack { if store.accountBusy { ProgressView().tint(.black) }; Text("CẬP NHẬT MẬT KHẨU") }
                        .font(.system(size: 11, weight: .black)).foregroundStyle(.black).frame(maxWidth: .infinity).padding(14)
                        .background(Color.cinemaAccent, in: RoundedRectangle(cornerRadius: 14))
                }
                .disabled(store.accountBusy || current.isEmpty || newPassword.count < 10 || confirmation.isEmpty)
                Button("Đóng") { dismiss() }.font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.65)).frame(maxWidth: .infinity)
            }
            .padding(22).frame(maxWidth: 500)
        }
        .presentationDetents([.medium, .large])
        .alert("Đổi mật khẩu thành công. Bạn có muốn đăng xuất tất cả thiết bị không, kể cả thiết bị hiện tại?", isPresented: $showLogoutPrompt) {
            Button("CÓ", role: .destructive) { Task { if await store.logoutAllDevices() { dismiss() } } }
            Button("KHÔNG", role: .cancel) { dismiss() }
        }
    }
}

private extension View {
    func passwordField() -> some View {
        self.textInputAutocapitalization(.never)
            .padding(14).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
    }
}
