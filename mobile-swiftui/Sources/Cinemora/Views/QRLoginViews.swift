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
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

struct QRLoginSheet: View {
    @EnvironmentObject private var store: CinemaStore
    @Environment(\.dismiss) private var dismiss
    @State private var challenge: RemoteQrChallenge?
    @State private var statusText = "Đang tạo mã QR…"
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            CinemaBackground()
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionEyebrow(text: "CINEMORA ACCOUNT")
                        Text("Đăng nhập bằng QR").font(.system(size: 26, weight: .black, design: .rounded)).foregroundStyle(.white)
                    }
                    Spacer()
                    Button("Đóng") { dismiss() }.foregroundStyle(Color.cinemaAccent)
                }
                if let challenge {
                    QRCodeImage(payload: challenge.payload).frame(width: 260, height: 260)
                    Text(statusText).font(.system(size: 12, weight: .semibold)).foregroundStyle(statusText.contains("thành công") ? Color.cinemaAccent : .white.opacity(0.7)).multilineTextAlignment(.center)
                    Text("Mở Cinemora trên thiết bị đã đăng nhập, chọn Quét QR, rồi xác nhận thiết bị này.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.58)).multilineTextAlignment(.center)
                } else if isLoading {
                    ProgressView().tint(Color.cinemaAccent).padding(50)
                }
                if let errorMessage {
                    Text(errorMessage).font(.system(size: 11, weight: .semibold)).foregroundStyle(.red).multilineTextAlignment(.center)
                    Button("Tạo mã mới") { Task { await runLoginLoop() } }.buttonStyle(.borderedProminent).tint(Color.cinemaAccent)
                }
                Spacer()
            }
            .padding(22)
        }
        .task { await runLoginLoop() }
    }

    private func runLoginLoop() async {
        isLoading = true; errorMessage = nil
        while !Task.isCancelled {
            do {
                let created = try await store.createQrLogin()
                challenge = created; isLoading = false; statusText = "Đang chờ thiết bị đã đăng nhập xác nhận…"
                let expires = Self.parseDate(created.expiresAt) ?? Date().addingTimeInterval(120)
                while !Task.isCancelled && Date() < expires {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    let status = try await store.qrLoginStatus(nonce: created.nonce)
                    switch status.status {
                    case "approved":
                        statusText = "Đã xác nhận. Đang đăng nhập…"
                        try await store.completeQrLogin(nonce: created.nonce)
                        statusText = "Đăng nhập thành công."
                        try? await Task.sleep(for: .milliseconds(250))
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
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return formatter.date(from: value)
        }()
    }
}
