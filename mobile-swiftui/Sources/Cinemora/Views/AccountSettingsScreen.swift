import SwiftUI

struct AccountSettingsScreen: View {
    @EnvironmentObject private var store: CinemaStore
    @Environment(\.dismiss) private var dismiss
    @State private var isRegistering = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var submitting = false
    @State private var showLogoutAllAlert = false

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let user = store.accountUser {
                        signedInContent(user)
                    } else {
                        signInContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 58)
                .padding(.bottom, 45)
            }
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Label("Trở lại", systemImage: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.black.opacity(0.5), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.leading, 20).padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await store.refreshAccountDevices()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if !Task.isCancelled { await store.refreshAccountDevices() }
            }
        }
        .alert("Đăng xuất tất cả thiết bị?", isPresented: $showLogoutAllAlert) {
            Button("Đăng xuất tất cả", role: .destructive) { Task { await store.logoutAllDevices() } }
            Button("Hủy", role: .cancel) { }
        } message: {
            Text("Tất cả phiên đăng nhập, kể cả thiết bị đang xem phim, sẽ bị thu hồi ngay lập tức.")
        }
    }

    private var signInContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionEyebrow(text: "CINEMORA ACCOUNT")
            Text(isRegistering ? "Tạo tài khoản" : "Đăng nhập")
                .font(.system(size: 29, weight: .black, design: .rounded)).foregroundStyle(.white)
            Text("Đăng nhập để đồng bộ lịch sử xem và phim yêu thích trên mọi thiết bị. Website vẫn giữ thư viện local riêng.")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.62))
            Picker("Chế độ", selection: $isRegistering) {
                Text("Đăng nhập").tag(false)
                Text("Đăng ký").tag(true)
            }
            .pickerStyle(.segmented)
            .tint(Color.cinemaAccent)
            .padding(.vertical, 4)
            if isRegistering { field("Họ và tên", text: $name, icon: "person.fill") }
            field("Email", text: $email, icon: "envelope.fill")
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
            SecureField("Mật khẩu", text: $password)
                .textFieldStyle(.plain)
                .padding(14)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            if let error = store.accountError { Text(error).font(.system(size: 11, weight: .semibold)).foregroundStyle(.red.opacity(0.9)) }
            Button {
                submitting = true
                Task {
                    do {
                        if isRegistering { try await store.register(name: name, email: email, password: password) }
                        else { try await store.login(email: email, password: password) }
                    } catch {
                        // CinemaStore publishes the server message; keep the
                        // failure visible instead of silently swallowing it.
                    }
                    await MainActor.run { submitting = false }
                }
            } label: {
                HStack { Spacer(); if submitting { ProgressView().tint(Color.cinemaInk) }; Text(submitting ? (isRegistering ? "Đang tạo tài khoản…" : "Đang đăng nhập…") : (isRegistering ? "Tạo tài khoản" : "Đăng nhập")); Spacer() }
                    .font(.system(size: 13, weight: .black)).foregroundStyle(Color.cinemaInk)
                    .padding(.vertical, 14).background(Color.cinemaAccent, in: Capsule())
            }
            .buttonStyle(.plain).disabled(submitting || email.isEmpty || password.isEmpty || (isRegistering && name.isEmpty))
        }
        .padding(18)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))
    }

    private func signedInContent(_ user: RemoteAccountUser) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionEyebrow(text: "ĐÃ ĐĂNG NHẬP")
            HStack(spacing: 13) {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 42)).foregroundStyle(Color.cinemaAccent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.displayName).font(.system(size: 18, weight: .black, design: .rounded)).foregroundStyle(.white)
                    Text(user.email ?? "").font(.system(size: 11)).foregroundStyle(.white.opacity(0.58))
                }
            }
            infoCard(icon: "arrow.triangle.2.circlepath", title: "Đồng bộ cloud", detail: "Lịch sử và yêu thích được đồng bộ trên các thiết bị đã đăng nhập.")
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionEyebrow(text: "THIẾT BỊ ĐÃ ĐĂNG NHẬP")
                    Spacer()
                    Text("\(store.accountDevices.count)/5").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Color.cinemaAccent)
                }
                ForEach(store.accountDevices) { device in deviceRow(device) }
                if store.accountDevices.isEmpty { Text("Chưa tải được danh sách thiết bị.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)) }
                Button("Đăng xuất tất cả thiết bị", role: .destructive) { showLogoutAllAlert = true }
                    .font(.system(size: 12, weight: .bold)).frame(maxWidth: .infinity).padding(.top, 5)
            }
            .padding(16).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
            Button("Đăng xuất tài khoản") { Task { await store.logout() } }
                .font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.68)).frame(maxWidth: .infinity)
        }
    }

    private func field(_ title: String, text: Binding<String>, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Color.cinemaAccent)
            TextField(title, text: text).foregroundStyle(.white)
        }
        .padding(14).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    private func infoCard(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Color.cinemaAccent).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(.white); Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.58)) }
        }
        .padding(14).background(Color.cinemaAccent.opacity(0.09), in: RoundedRectangle(cornerRadius: 17))
    }

    private func deviceRow(_ device: RemoteAccountDevice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: device.isOnline ? "circle.fill" : "circle").font(.system(size: 9)).foregroundStyle(device.isOnline ? .green : .gray)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.deviceName).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                Text("\(device.ipAddress) · \(device.location) · \(device.isOnline ? "Đang online" : "Offline")").font(.system(size: 9)).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
            }
            Spacer()
            Button { Task { await store.logoutDevice(id: device.id) } } label: { Image(systemName: "rectangle.portrait.and.arrow.right").foregroundStyle(.red.opacity(0.85)) }
                .buttonStyle(.plain).accessibilityLabel("Đăng xuất thiết bị \(device.deviceName)")
        }
        .padding(11).background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 13))
    }
}
