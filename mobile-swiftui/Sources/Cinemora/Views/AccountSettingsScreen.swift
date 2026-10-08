import SwiftUI

struct AccountSettingsScreen: View {
    @Environment(CinemaStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var isRegistering = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var submitting = false
    @State private var showLogoutAllAlert = false
    @State private var showChangePassword = false
    @State private var showQrLogin = false
    @State private var showQrScanner = false
    @State private var showQrApproval = false
    @State private var scannedNonce: String?
    @State private var scannedDeviceName = "thiết bị mới"
    @State private var qrActionError: String?
    @State private var lastScannedNonce: String?
    @State private var lastScannedAt = Date.distantPast
    @FocusState private var focusedField: String?
    @Namespace private var authModeNamespace

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
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.never)
        }
        .overlay(alignment: .topLeading) {
            AuroraBackButton(title: "Trở lại") { dismiss() }
                .padding(.leading, 20)
                .padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .animation(Motion.sheet, value: store.accountUser != nil)
        .animation(Motion.sheet, value: isRegistering)
        .onAppear {
            if store.accountUser == nil { store.clearAccountError() }
        }
        .onChange(of: store.accountUser) { _, user in
            if user == nil {
                submitting = false
                name = ""
                email = ""
                password = ""
                isRegistering = false
                store.clearAccountError()
            }
        }
        .task {
            await store.refreshAccountDevices()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled { await store.refreshAccountDevices() }
            }
        }
        .alert("Đăng xuất tất cả thiết bị?", isPresented: $showLogoutAllAlert) {
            Button("Đăng xuất tất cả", role: .destructive) { Task { await store.logoutAllDevices() } }
            Button("Hủy", role: .cancel) { }
        } message: {
            Text("Tất cả phiên đăng nhập, kể cả thiết bị đang xem phim, sẽ bị thu hồi ngay lập tức.")
        }
        .sheet(isPresented: $showQrLogin) {
            QRLoginSheet().environment(store)
        }
        .sheet(isPresented: $showChangePassword) {
            ChangePasswordSheet().environment(store)
        }
        .sheet(isPresented: $showQrScanner) {
            NavigationStack {
                QRCodeScannerView(onCode: { code in
                    showQrScanner = false
                    handleScannedQr(code)
                }, onFailure: { message in
                    qrActionError = message
                    showQrScanner = false
                })
                .ignoresSafeArea()
                .navigationTitle("Quét QR đăng nhập")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { showQrScanner = false } } }
            }
        }
        .confirmationDialog("Cho phép đăng nhập?", isPresented: $showQrApproval, titleVisibility: .visible) {
            Button("Chấp nhận", role: .none) { approveScannedQr(true) }
            Button("Từ chối", role: .destructive) { approveScannedQr(false) }
            Button("Hủy", role: .cancel) { scannedNonce = nil }
        } message: {
            Text("Thiết bị \(scannedDeviceName) đang yêu cầu đăng nhập vào tài khoản \(store.accountUser?.email ?? "này").")
        }
        .alert("QR login", isPresented: Binding(get: { qrActionError != nil }, set: { if !$0 { qrActionError = nil } })) {
            Button("Đóng", role: .cancel) { qrActionError = nil }
        } message: { Text(qrActionError ?? "") }
    }

    // MARK: - Signed out

    private var signInContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                SectionEyebrow(text: "CINEMORA ACCOUNT")
                AuroraGradientText(text: isRegistering ? "Tạo tài khoản" : "Đăng nhập", font: .auroraDisplay(28))
                Text("Đăng nhập để đồng bộ lịch sử xem và phim yêu thích trên mọi thiết bị. Website vẫn giữ thư viện local riêng.")
                    .font(.auroraBody(12))
                    .foregroundStyle(Color.auroraTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .auroraReveal(0)

            modeSelector
                .auroraReveal(1)

            VStack(alignment: .leading, spacing: 12) {
                if isRegistering {
                    field("Họ và tên", text: $name, icon: "person.fill", id: "name")
                }
                field("Email", text: $email, icon: "envelope.fill", id: "email")
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                secureField("Mật khẩu", text: $password, id: "password")
                if let error = store.accountError {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.auroraAmber)
                        Text(error)
                            .font(.auroraBody(11, weight: .semibold))
                            .foregroundStyle(Color.auroraAmber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.auroraAmber.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.auroraAmber.opacity(0.3), lineWidth: 0.8)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .auroraReveal(2)

            VStack(spacing: 12) {
                AuroraPrimaryButton(
                    title: submitting ? (isRegistering ? "Đang tạo tài khoản…" : "Đang đăng nhập…") : (isRegistering ? "Tạo tài khoản" : "Đăng nhập"),
                    icon: isRegistering ? "person.badge.plus" : "arrow.right.to.line",
                    loading: submitting,
                    enabled: canSubmitAuth
                ) {
                    submitAuth()
                }
                AuroraGhostButton(title: "Đăng nhập bằng QR", icon: "qrcode", tint: .auroraSky) {
                    showQrLogin = true
                }
            }
            .auroraReveal(3)
        }
        .padding(18)
        .auroraCard(cornerRadius: 26, tint: .auroraViolet, fill: 0.75)
    }

    private var canSubmitAuth: Bool {
        !submitting && !email.isEmpty && !password.isEmpty && (!isRegistering || !name.isEmpty)
    }

    private var modeSelector: some View {
        HStack(spacing: 5) {
            ForEach([false, true], id: \.self) { value in
                Button {
                    withAnimation(Motion.sheet) { isRegistering = value }
                    focusedField = nil
                } label: {
                    Text(value ? "Đăng ký" : "Đăng nhập")
                        .font(.auroraLabel(12, weight: .bold))
                        .foregroundStyle(isRegistering == value ? Color.auroraVoid : Color.white.opacity(0.65))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background {
                            if isRegistering == value {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(LinearGradient.auroraPrimary)
                                    .matchedGeometryEffect(id: "authModeIndicator", in: authModeNamespace)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.8)
        }
    }

    private func submitAuth() {
        guard canSubmitAuth else { return }
        focusedField = nil
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
    }

    // MARK: - Signed in

    private func signedInContent(_ user: RemoteAccountUser) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionEyebrow(text: "ĐÃ ĐĂNG NHẬP")
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.icloud.fill").font(.system(size: 10, weight: .bold))
                    Text("Đồng bộ")
                        .font(.auroraLabel(10, weight: .bold))
                }
                .foregroundStyle(Color.auroraMint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.auroraMint.opacity(0.14)))
                .overlay(Capsule().strokeBorder(Color.auroraMint.opacity(0.3), lineWidth: 0.7))
            }
            .auroraReveal(0)

            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient.auroraPrimary)
                        .frame(width: 56, height: 56)
                        .auroraHalo(.auroraViolet, radius: 18, opacity: 0.45)
                    Image(systemName: "person.fill")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(Color.auroraVoid)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.displayName)
                        .font(.auroraLabel(18, weight: .black))
                        .foregroundStyle(.white)
                    Text(user.email ?? "")
                        .font(.auroraBody(11))
                        .foregroundStyle(Color.auroraTextSecondary)
                }
                Spacer(minLength: 0)
            }
            .auroraReveal(1)

            infoCard(icon: "arrow.triangle.2.circlepath", title: "Đồng bộ cloud", detail: "Lịch sử và yêu thích được đồng bộ trên các thiết bị đã đăng nhập.")
                .auroraReveal(2)

            AuroraGhostButton(title: "Quét QR để đăng nhập thiết bị khác", icon: "qrcode.viewfinder", tint: .auroraSky) {
                showQrScanner = true
            }
            .auroraReveal(3)

            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    SectionEyebrow(text: "THIẾT BỊ ĐÃ ĐĂNG NHẬP")
                    Spacer()
                    Text("\(store.accountDevices.count) / 5")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.auroraViolet)
                }
                ForEach(Array(store.accountDevices.enumerated()), id: \.element.id) { index, device in
                    deviceRow(device)
                        .auroraReveal(index % 6)
                }
                if store.accountDevices.isEmpty {
                    HStack(spacing: 9) {
                        ProgressView().tint(Color.auroraViolet)
                        Text("Đang đồng bộ danh sách thiết bị…")
                            .font(.auroraBody(11))
                            .foregroundStyle(Color.auroraTextSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 7)
                }
                Button("Đăng xuất tất cả thiết bị", role: .destructive) { showLogoutAllAlert = true }
                    .font(.auroraLabel(12, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 5)
            }
            .padding(16)
            .auroraCard(cornerRadius: 24, tint: .auroraViolet, fill: 0.6)
            .auroraReveal(4)

            AuroraGhostButton(title: "Đổi mật khẩu", icon: "key.fill", tint: .auroraAmber) {
                showChangePassword = true
            }
            .auroraReveal(5)

            Button {
                Task { await store.logout() }
            } label: {
                Text("Đăng xuất tài khoản")
                    .font(.auroraLabel(12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.auroraPress(scale: 0.97))
            .auroraReveal(6)
        }
    }

    // MARK: - Field builders

    private func field(_ title: String, text: Binding<String>, icon: String, id: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(focusedField == id ? Color.auroraViolet : Color.white.opacity(0.5))
                .frame(width: 20)
            TextField(title, text: text)
                .font(.auroraBody(13))
                .foregroundStyle(.white)
                .focused($focusedField, equals: id)
        }
        .padding(14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.auroraViolet.opacity(focusedField == id ? 0.6 : 0.1), lineWidth: focusedField == id ? 1.2 : 0.8)
        }
        .animation(Motion.gentle, value: focusedField)
    }

    private func secureField(_ title: String, text: Binding<String>, id: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(focusedField == id ? Color.auroraViolet : Color.white.opacity(0.5))
                .frame(width: 20)
            SecureField(title, text: text)
                .font(.auroraBody(13))
                .foregroundStyle(.white)
                .focused($focusedField, equals: id)
        }
        .padding(14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.auroraViolet.opacity(focusedField == id ? 0.6 : 0.1), lineWidth: focusedField == id ? 1.2 : 0.8)
        }
        .animation(Motion.gentle, value: focusedField)
    }

    private func infoCard(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.auroraSky.opacity(0.16))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.auroraSky)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.auroraLabel(12, weight: .bold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.auroraBody(10))
                    .foregroundStyle(Color.auroraTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.auroraSky.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.auroraSky.opacity(0.2), lineWidth: 0.8)
        }
    }

    private func deviceRow(_ device: RemoteAccountDevice) -> some View {
        HStack(spacing: 11) {
            LivePulse(color: device.isOnline ? .auroraMint : .white.opacity(0.35), size: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.deviceName)
                    .font(.auroraLabel(12, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(device.ipAddress) · \(device.location) · \(device.isOnline ? "Đang online" : "Offline")")
                    .font(.auroraBody(9))
                    .foregroundStyle(Color.auroraTextSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Text(device.isOnline ? "ONLINE" : "OFFLINE")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(device.isOnline ? Color.auroraMint : Color.white.opacity(0.4))
            Button {
                Task { await store.logoutDevice(id: device.id, deviceId: device.deviceId) }
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.auroraPink)
                    .frame(width: 34, height: 34)
                    .background(Color.auroraPink.opacity(0.12), in: Circle())
            }
            .buttonStyle(.auroraPress(scale: 0.9))
            .accessibilityLabel("Đăng xuất thiết bị \(device.deviceName)")
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.7)
        }
    }

    // MARK: - QR helpers

    private func handleScannedQr(_ rawValue: String) {
        let prefix = "cinemora-qr-v1:"
        guard rawValue.hasPrefix(prefix) else {
            qrActionError = "Mã QR không thuộc Cinemora hoặc đã bị thay đổi."
            return
        }
        let nonce = String(rawValue.dropFirst(prefix.count))
        guard nonce.count >= 32, nonce.count <= 160,
              nonce.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else {
            qrActionError = "Mã QR không hợp lệ."
            return
        }
        guard nonce != lastScannedNonce || Date().timeIntervalSince(lastScannedAt) > 5 else {
            qrActionError = "Mã QR vừa được quét. Vui lòng chờ một chút."
            return
        }
        lastScannedNonce = nonce
        lastScannedAt = Date()
        scannedNonce = nonce
        Task {
            do {
                let status = try await store.qrLoginStatus(nonce: nonce)
                guard status.status == "pending" else { qrActionError = "Mã QR đã hết hạn hoặc đã được xử lý."; return }
                scannedDeviceName = status.deviceName ?? "thiết bị mới"
                showQrApproval = true
            } catch { qrActionError = error.localizedDescription }
        }
    }

    private func approveScannedQr(_ approved: Bool) {
        guard let nonce = scannedNonce else { return }
        scannedNonce = nil
        Task {
            do {
                _ = try await store.approveQrLogin(nonce: nonce, approved: approved)
                if approved { await store.refreshAccountDevicesAfterQrApproval() }
            }
            catch { qrActionError = error.localizedDescription }
        }
    }
}

// MARK: - Change password

private struct ChangePasswordSheet: View {
    @Environment(CinemaStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didSucceed = false

    private var canSubmit: Bool {
        !currentPassword.isEmpty && newPassword.count >= 8 && newPassword == confirmPassword && !isSaving
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CinemaBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 7) {
                            SectionEyebrow(text: "BẢO MẬT TÀI KHOẢN")
                            AuroraGradientText(text: "Đổi mật khẩu", font: .auroraDisplay(28))
                            Text("Sau khi đổi, các thiết bị khác sẽ phải đăng nhập lại bằng mật khẩu mới.")
                                .font(.auroraBody(12))
                                .foregroundStyle(Color.auroraTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        passwordField("Mật khẩu hiện tại", text: $currentPassword)
                        passwordField("Mật khẩu mới", text: $newPassword)
                        passwordField("Nhập lại mật khẩu mới", text: $confirmPassword)
                        if !newPassword.isEmpty && newPassword.count < 8 {
                            notice("Mật khẩu mới cần ít nhất 8 ký tự.", tint: .auroraAmber)
                        } else if !confirmPassword.isEmpty && newPassword != confirmPassword {
                            notice("Hai mật khẩu mới chưa khớp.", tint: .auroraAmber)
                        }
                        if let errorMessage {
                            notice(errorMessage, tint: .auroraPink)
                        }
                        if didSucceed {
                            notice("Đổi mật khẩu thành công. Các phiên khác đã được đăng xuất.", tint: .auroraMint)
                        }
                        AuroraPrimaryButton(
                            title: isSaving ? "Đang cập nhật…" : "Cập nhật mật khẩu",
                            icon: "checkmark.shield.fill",
                            loading: isSaving,
                            enabled: canSubmit && !didSucceed
                        ) {
                            Task { await save() }
                        }
                    }
                    .padding(22)
                }
                .scrollIndicators(.hidden)
                }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Đóng") { dismiss() } }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private func notice(_ text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.auroraBody(11, weight: .semibold))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: 0.8)
        }
    }

    private func passwordField(_ title: String, text: Binding<String>) -> some View {
        SecureField(title, text: text)
            .textFieldStyle(.plain)
            .font(.auroraBody(13))
            .padding(14)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.8)
            }
            .foregroundStyle(.white)
    }

    private func save() async {
        guard canSubmit else { return }
        isSaving = true
        errorMessage = nil
        do {
            try await store.changePassword(currentPassword: currentPassword, newPassword: newPassword)
            didSucceed = true
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
