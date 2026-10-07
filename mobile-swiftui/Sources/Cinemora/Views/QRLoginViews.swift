import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct QRCodeImage: View {
    let payload: String

    var body: some View {
        Image(uiImage: Self.makeImage(payload: payload))
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.4), radius: 20, y: 12)
            .shadow(color: Color.auroraViolet.opacity(0.3), radius: 26, y: 8)
    }

    private static func makeImage(payload: String) -> UIImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "Q"
        let context = CIContext()
        guard let output = filter.outputImage else {
            return UIImage(systemName: "xmark.octagon") ?? UIImage()
        }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return UIImage(systemName: "xmark.octagon") ?? UIImage()
        }
        return UIImage(cgImage: cgImage)
    }
}

struct QRCodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onCode = onCode
        controller.onFailure = onFailure
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) { }

    final class Coordinator {
        let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
    }
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onFailure: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didScan = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func configureCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.setupSession() }
                    else { self?.onFailure?("Cần cho phép quyền camera để quét mã QR.") }
                }
            }
        default:
            onFailure?("Camera đang bị tắt. Hãy bật quyền Camera cho Cinemora trong Cài đặt.")
        }
    }

    private func setupSession() {
        guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else {
            onFailure?("Không thể khởi tạo camera trên thiết bị này.")
            return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { onFailure?("Camera không hỗ trợ quét mã QR."); return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.session.startRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !didScan, let value = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        didScan = true
        session.stopRunning()
        onCode?(value)
    }

    deinit { if session.isRunning { session.stopRunning() } }
}

// MARK: - QR login sheet

struct QRLoginSheet: View {
    @EnvironmentObject private var store: CinemaStore
    @Environment(\.dismiss) private var dismiss
    @State private var challenge: RemoteQrChallenge?
    @State private var statusText = "Đang tạo mã QR…"
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var remainingSeconds = 0
    @State private var sessionID = UUID()
    @State private var scanOffset: CGFloat = -1

    private var isSuccess: Bool { statusText.contains("thành công") }

    var body: some View {
        ZStack {
            CinemaBackground()
            VStack(spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionEyebrow(text: "CINEMORA ACCOUNT")
                        AuroraGradientText(text: "Đăng nhập bằng QR", font: .auroraDisplay(24))
                    }
                    Spacer()
                    Button("Đóng") { dismiss() }
                        .font(.auroraLabel(13, weight: .bold))
                        .foregroundStyle(Color.auroraViolet)
                }

                Spacer(minLength: 0)

                if let challenge {
                    ZStack {
                        QRCodeImage(payload: challenge.payload)
                            .frame(width: 250, height: 250)
                            .overlay {
                                GeometryReader { proxy in
                                    LinearGradient(
                                        colors: [Color.clear, Color.auroraViolet.opacity(0.65), Color.clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    .frame(height: 46)
                                    .offset(y: (scanOffset + 1) / 2 * max(proxy.size.height - 46, 0))
                                    .blendMode(.plusLighter)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .allowsHitTesting(false)
                            }
                            .scaleEffect(isSuccess ? 1.04 : 1)
                            .animation(Motion.enter, value: isSuccess)

                        if isSuccess {
                            ZStack {
                                Circle().fill(Color.auroraMint.opacity(0.22)).frame(width: 110, height: 110).blur(radius: 18)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 44, weight: .black))
                                    .foregroundStyle(Color.auroraMint)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }

                    VStack(spacing: 9) {
                        Text(statusText)
                            .font(.auroraBody(12, weight: .semibold))
                            .foregroundStyle(isSuccess ? Color.auroraMint : .white.opacity(0.78))
                            .multilineTextAlignment(.center)
                            .contentTransition(.opacity)

                        HStack(spacing: 7) {
                            Image(systemName: "timer").font(.system(size: 10, weight: .bold))
                            Text(remainingSeconds > 0 ? "Mã QR còn hiệu lực \(remainingSeconds)s" : "Mã QR đã hết hạn")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(remainingSeconds > 15 ? Color.auroraViolet : Color.auroraAmber)

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.12))
                                Capsule()
                                    .fill(remainingSeconds > 15 ? LinearGradient.auroraPrimary : LinearGradient.auroraWarm)
                                    .frame(width: max(4, proxy.size.width * min(1, Double(remainingSeconds) / 120)))
                            }
                        }
                        .frame(height: 4)
                        .padding(.horizontal, 34)
                        .animation(.linear(duration: 1), value: remainingSeconds)
                    }
                } else if isLoading {
                    VStack(spacing: 14) {
                        ProgressView().tint(Color.auroraViolet)
                        Text("Đang tạo mã QR…")
                            .font(.auroraBody(12))
                            .foregroundStyle(Color.auroraTextSecondary)
                    }
                    .padding(50)
                }

                if let errorMessage {
                    VStack(spacing: 12) {
                        Text(errorMessage)
                            .font(.auroraBody(11, weight: .semibold))
                            .foregroundStyle(Color.auroraPink)
                            .multilineTextAlignment(.center)
                        AuroraGhostButton(title: "Tạo mã mới", icon: "arrow.clockwise", tint: .auroraPink) {
                            Task { await runLoginLoop() }
                        }
                    }
                }

                Spacer(minLength: 0)

                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.auroraSky)
                    Text("Mở Cinemora trên thiết bị đã đăng nhập, chọn Quét QR, rồi xác nhận thiết bị này.")
                        .font(.auroraBody(11))
                        .foregroundStyle(Color.auroraTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(13)
                .background(Color.auroraSky.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.auroraSky.opacity(0.2), lineWidth: 0.8)
                }
            }
            .padding(22)
        }
        .onAppear {
            // A dismissed sheet may be reused by SwiftUI. Changing the task
            // identity guarantees a fresh nonce and a fresh countdown next time.
            challenge = nil
            remainingSeconds = 0
            statusText = "Đang tạo mã QR…"
            errorMessage = nil
            sessionID = UUID()
            scanOffset = -1
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { scanOffset = 1 }
        }
        .animation(Motion.enter, value: isSuccess)
        .task(id: sessionID) { await runLoginLoop() }
    }

    private func runLoginLoop() async {
        isLoading = true; errorMessage = nil; remainingSeconds = 0
        while !Task.isCancelled {
            do {
                let created = try await store.createQrLogin()
                challenge = created; isLoading = false; statusText = "Đang chờ thiết bị đã đăng nhập xác nhận…"
                let expires = Self.parseDate(created.expiresAt) ?? Date().addingTimeInterval(120)
                remainingSeconds = max(0, Int(ceil(expires.timeIntervalSinceNow)))
                while !Task.isCancelled && Date() < expires {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    remainingSeconds = max(0, Int(ceil(expires.timeIntervalSinceNow)))
                    if Date() >= expires { break }
                    let status = try await store.qrLoginStatus(nonce: created.nonce)
                    switch status.status {
                    case "approved":
                        statusText = "Đã xác nhận. Đang đăng nhập…"
                        try await store.completeQrLogin(nonce: created.nonce)
                        statusText = "Đăng nhập thành công."
                        try? await Task.sleep(for: .milliseconds(650))
                        dismiss()
                        return
                    case "denied":
                        statusText = "Thiết bị đã từ chối. Đang tạo mã mới…"
                        try? await Task.sleep(for: .milliseconds(700))
                        break
                    case "expired", "invalid":
                        statusText = "Mã QR đã hết hạn. Đang tạo mã mới…"
                        try? await Task.sleep(for: .milliseconds(400))
                        break
                    default: continue
                    }
                    break
                }
                if Date() >= expires { statusText = "Mã QR hết hạn. Đang tạo mã mới…" }
            } catch {
                isLoading = false; errorMessage = error.localizedDescription; return
            }
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value) ?? {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: value)
        }()
    }
}
