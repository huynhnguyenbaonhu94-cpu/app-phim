import SwiftUI
import UIKit

struct AccountManagementScreen: View {
    @EnvironmentObject private var store: CinemaStore
    @State private var mode: AuthMode = .login
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var showLogoutChoice = false
    @State private var showLogoutAllConfirm = false
    @State private var showLogoutSuccess = false

    private enum AuthMode: String, CaseIterable, Hashable { case login = "Đăng nhập", register = "Đăng ký" }

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    CinemaHeader(eyebrow: "CINEMORA ACCOUNT", title: "TÀI KHOẢN")
                    if let user = store.accountUser {
                        profileCard(user)
                        NavigationLink { AccountDevicesScreen() } label: {
                            AccountActionRow(icon: "iphone.and.arrow.forward", title: "Thiết bị đã đăng nhập", detail: "Xem online, IP và đăng xuất thiết bị")
                        }.buttonStyle(.plain)
                        passwordCard
                        Button(role: .destructive) { Task { await store.logoutAccount() } } label: {
                            Label("Đăng xuất tài khoản này", systemImage: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(.red.opacity(0.9))
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain)
                    } else {
                        signInCard
                    }
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 42)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Đổi mật khẩu thành công", isPresented: $showLogoutChoice) {
            Button("Có, đăng xuất tất cả", role: .destructive) {
                Task { do { try await store.logoutAllAccountDevices() } catch { errorMessage = error.localizedDescription } }
            }
            Button("Không, giữ các thiết bị", role: .cancel) { showLogoutSuccess = true }
        } message: {
            Text("Bạn có muốn đăng xuất tất cả thiết bị đã đăng nhập, bao gồm thiết bị hiện tại không?")
        }
        .alert("Đã đổi mật khẩu", isPresented: $showLogoutSuccess) {
            Button("Đóng", role: .cancel) { }
        } message: {
            Text("Các thiết bị hiện tại vẫn được giữ đăng nhập như bạn đã chọn.")
        }
    }

    private func profileCard(_ user: AccountUser) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 38)).foregroundStyle(Color.cinemaAccent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.name ?? "Tài khoản Cinemora").font(.system(size: 17, weight: .black, design: .rounded)).foregroundStyle(.white)
                    Text(user.email ?? "").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.58))
                }
                Spacer()
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.cinemaAccent)
            }
            if let status = store.accountSyncMessage {
                Label(status, systemImage: status.hasPrefix("Đã đồng bộ") ? "checkmark.icloud.fill" : "icloud")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16).background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.1), lineWidth: 0.8))
    }

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Đồng bộ thư viện của bạn").font(.system(size: 19, weight: .black, design: .rounded)).foregroundStyle(.white)
            Text("Dùng địa chỉ Gmail hoặc email của bạn cùng mật khẩu Cinemora. Lịch sử, yêu thích và cài đặt phụ đề sẽ được đồng bộ khi đăng nhập.")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.62)).fixedSize(horizontal: false, vertical: true)
            Picker("", selection: $mode) { ForEach(AuthMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).tint(Color.cinemaAccent)
            if mode == .register { accountField("Họ và tên", text: $name, icon: "person", contentType: .name) }
            accountField("Email / Gmail", text: $email, icon: "envelope", contentType: .emailAddress, keyboard: .emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("Mật khẩu (ít nhất 8 ký tự)", text: $password)
                .textContentType(mode == .login ? .password : .newPassword)
                .font(.system(size: 13)).padding(14).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            if let errorMessage { Text(errorMessage).font(.system(size: 11, weight: .medium)).foregroundStyle(.red.opacity(0.9)).fixedSize(horizontal: false, vertical: true) }
            Button {
                Task {
                    errorMessage = nil
                    do {
                        if mode == .login { try await store.loginAccount(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password) }
                        else { try await store.registerAccount(name: name, email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password) }
                    } catch { errorMessage = error.localizedDescription }
                }
            } label: {
                HStack { if store.accountIsBusy { ProgressView().tint(.black) }; Text(store.accountIsBusy ? "Đang xử lý…" : mode.rawValue).font(.system(size: 13, weight: .black)) }
                    .foregroundStyle(Color.cinemaInk).frame(maxWidth: .infinity).padding(.vertical, 14).background(Color.cinemaAccent, in: RoundedRectangle(cornerRadius: 13))
            }
            .disabled(store.accountIsBusy || email.isEmpty || password.isEmpty || (mode == .register && name.trimmingCharacters(in: .whitespaces).count < 2))
            .buttonStyle(.plain)
            Text("Tối đa 5 thiết bị đăng nhập cho mỗi tài khoản. Mật khẩu được băm ở máy chủ; app lưu token trong iOS Keychain.")
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.42)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(17).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.1), lineWidth: 0.8))
    }

    private var passwordCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Đổi mật khẩu").font(.system(size: 16, weight: .black, design: .rounded)).foregroundStyle(.white)
            SecureField("Mật khẩu cũ", text: $currentPassword).textContentType(.password).font(.system(size: 12)).padding(12).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
            SecureField("Mật khẩu mới (ít nhất 8 ký tự)", text: $newPassword).textContentType(.newPassword).font(.system(size: 12)).padding(12).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
            SecureField("Nhập lại mật khẩu mới", text: $confirmPassword).textContentType(.newPassword).font(.system(size: 12)).padding(12).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
            if let errorMessage { Text(errorMessage).font(.system(size: 10)).foregroundStyle(.red.opacity(0.9)) }
            Button {
                Task {
                    errorMessage = nil
                    do {
                        try await store.changeAccountPassword(current: currentPassword, new: newPassword, confirm: confirmPassword)
                        currentPassword = ""; newPassword = ""; confirmPassword = ""
                        showLogoutChoice = true
                    } catch { errorMessage = error.localizedDescription }
                }
            } label: {
                Label("Cập nhật mật khẩu", systemImage: "key.horizontal.fill")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Color.cinemaAccent)
                    .frame(maxWidth: .infinity).padding(.vertical, 12).background(Color.cinemaAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain).disabled(currentPassword.isEmpty || newPassword.count < 8 || confirmPassword.isEmpty)
        }
        .padding(16).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.1), lineWidth: 0.8))
    }

    private func accountField(_ title: String, text: Binding<String>, icon: String, contentType: UITextContentType? = nil, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(Color.cinemaAccent).frame(width: 17)
            TextField(title, text: text).font(.system(size: 13)).keyboardType(keyboard).textContentType(contentType).foregroundStyle(.white)
        }
        .padding(13).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct AccountActionRow: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundStyle(Color.cinemaAccent).frame(width: 40, height: 40).background(Color.cinemaAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                Text(detail).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.52))
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.4))
        }
        .padding(14).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.1), lineWidth: 0.7))
    }
}

private struct AccountDevicesScreen: View {
    @EnvironmentObject private var store: CinemaStore
    @State private var devices: [AccountDevice] = []
    @State private var loadError: String?
    @State private var selectedDevice: AccountDevice?
    @State private var isKicking = false

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    CinemaHeader(eyebrow: "BẢO MẬT", title: "THIẾT BỊ")
                    Text("Tối đa 5 thiết bị. Thiết bị hiển thị Online khi gửi tín hiệu trong 90 giây gần nhất.")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.56))
                    HStack {
                        Text("\(devices.count) / 5 thiết bị")
                        Spacer()
                        Button("Đăng xuất tất cả") { selectedDevice = nil; isKicking = true }
                    }
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.cinemaAccent)
                    if let loadError { Text(loadError).font(.system(size: 11)).foregroundStyle(.red) }
                    if devices.isEmpty { StateMessage(icon: "iphone.slash", title: "Chưa có thiết bị", detail: "Kéo xuống để tải lại danh sách.") }
                    ForEach(devices) { device in deviceRow(device) }
                }
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 42)
            }
            .refreshable { await reload() }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await reload()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                await reload()
            }
        }
        .confirmationDialog(isKicking ? "Đăng xuất tất cả thiết bị?" : "Đăng xuất thiết bị này?", isPresented: Binding(get: { isKicking || selectedDevice != nil }, set: { if !$0 { isKicking = false; selectedDevice = nil } }), titleVisibility: .visible) {
            Button(isKicking ? "Đăng xuất tất cả" : "Đăng xuất thiết bị", role: .destructive) {
                Task {
                    do {
                        if isKicking { try await store.logoutAllAccountDevices() }
                        else if let selectedDevice { try await store.kickAccountDevice(selectedDevice) }
                        isKicking = false; selectedDevice = nil
                        await reload()
                    } catch { loadError = error.localizedDescription; isKicking = false; selectedDevice = nil }
                }
            }
            Button("Hủy", role: .cancel) { isKicking = false; selectedDevice = nil }
        } message: {
            Text(isKicking ? "Tất cả phiên trên tài khoản, kể cả thiết bị hiện tại, sẽ bị thu hồi. Bạn cần đăng nhập lại." : "Thiết bị bị đăng xuất sẽ được yêu cầu quay về màn hình đăng nhập.")
        }
    }

    private func reload() async {
        do { devices = try await store.listAccountDevices(); loadError = nil }
        catch { loadError = error.localizedDescription }
    }

    private func deviceRow(_ device: AccountDevice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: device.platform == "ios" ? "iphone" : "desktopcomputer")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(Color.cinemaAccent)
                    .frame(width: 38, height: 38).background(Color.cinemaAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(device.deviceName).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        if device.current { Text("THIẾT BỊ NÀY").font(.system(size: 7, weight: .black)).foregroundStyle(Color.cinemaAccent) }
                    }
                    Text(device.deviceModel ?? device.platform.uppercased()).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                    Text(device.ipAddress.map { "IP: \($0) · " } ?? "") + Text(device.online ? "Online" : "Hoạt động gần nhất")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(device.online ? Color.cinemaAccent : .white.opacity(0.48))
                    Text("Lần cuối: \(device.lastSeenAt)").font(.system(size: 8, weight: .regular, design: .monospaced)).foregroundStyle(.white.opacity(0.38)).lineLimit(1)
                }
                Spacer(minLength: 2)
                Button { selectedDevice = device } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 12, weight: .bold)).foregroundStyle(.red.opacity(0.85)).padding(9).background(.red.opacity(0.1), in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("Đăng xuất thiết bị")
            }
        }
        .padding(13).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(device.online ? Color.cinemaAccent.opacity(0.22) : .white.opacity(0.08), lineWidth: 0.8))
    }
}
