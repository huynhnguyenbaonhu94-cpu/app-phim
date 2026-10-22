import AVFoundation
import MediaPlayer
import SwiftUI

/// Điều khiển âm lượng của **máy** thay vì âm lượng riêng của trình phát.
///
/// `AVPlayer` có mức âm lượng riêng, nên trước đây kéo thanh âm lượng chỉ làm nhỏ
/// tiếng bên trong app còn âm lượng thiết bị vẫn nguyên. Ở đây dùng một `MPVolumeView`
/// ẩn để đặt đúng mức âm lượng của máy, đồng thời theo dõi `outputVolume` của
/// `AVAudioSession` nên thanh trượt luôn khớp với mức thật của thiết bị — kể cả khi
/// người dùng bấm nút cứng bên hông máy.
@MainActor
final class SystemVolume: ObservableObject {
    static let shared = SystemVolume()

    /// Mức âm lượng hiện tại của thiết bị (0…1).
    @Published private(set) var value: Double
    /// Thiết bị đang ở mức 0 thì coi như đang tắt tiếng.
    @Published private(set) var isMuted: Bool

    private let volumeView = MPVolumeView(frame: .zero)
    private var observation: NSKeyValueObservation?
    private var restoreValue: Double = 0.6

    private init() {
        let session = AVAudioSession.sharedInstance()
        let current = Double(session.outputVolume)
        value = current
        isMuted = current <= 0.001
        restoreValue = current > 0.001 ? current : 0.6

        volumeView.showsRouteButton = false
        volumeView.showsVolumeSlider = true
        volumeView.alpha = 0.001
        volumeView.isUserInteractionEnabled = false

        observation = session.observe(\.outputVolume, options: [.new, .initial]) { [weak self] session, _ in
            let level = Double(session.outputVolume)
            Task { @MainActor in self?.apply(level) }
        }
    }

    /// `MPVolumeView` dùng chung để gắn vào cây giao diện của trình phát đang mở.
    ///
    /// iOS chỉ cho `MPVolumeView` điều khiển âm lượng hệ thống khi nó nằm trong cây
    /// giao diện, nên mỗi trình phát đặt một neo 1×1 ẩn (xem `SystemVolumeAnchor`).
    var anchorView: MPVolumeView { volumeView }

    /// Đặt âm lượng thiết bị. Dùng thanh trượt con của `MPVolumeView` vì đây là API
    /// công khai duy nhất cho việc này; giá trị được gửi kèm sự kiện `valueChanged`.
    @MainActor
    func set(_ newValue: Double) {
        let clamped = min(1, max(0, newValue))
        apply(clamped)
        guard let slider = slider else { return }
        // Đặt trên hàng đợi kế tiếp để không ghi đè trong lúc thanh trượt đang bị kéo.
        DispatchQueue.main.async {
            slider.value = Float(clamped)
            slider.sendActions(for: .valueChanged)
        }
    }

    /// Bật/tắt tiếng theo trạng thái mong muốn, nhớ mức cũ để bật lại đúng mức đó.
    @MainActor
    func setMuted(_ muted: Bool) {
        if muted {
            if value > 0.001 { restoreValue = value }
            set(0)
        } else if value <= 0.001 {
            set(restoreValue)
        }
    }

    /// Tắt tiếng máy, nhớ mức cũ để bật lại đúng mức đó.
    @MainActor
    func toggleMute() {
        if value <= 0.001 {
            set(restoreValue)
        } else {
            restoreValue = value
            set(0)
        }
    }

    private var slider: UISlider? {
        volumeView.subviews.compactMap { $0 as? UISlider }.first
    }

    @MainActor
    private func apply(_ level: Double) {
        let clamped = min(1, max(0, level))
        if value != clamped { value = clamped }
        let muted = clamped <= 0.001
        if isMuted != muted { isMuted = muted }
        if clamped > 0.001 { restoreValue = clamped }
    }
}

/// Neo 1×1 đặt `MPVolumeView` vào cây giao diện của trình phát.
///
/// Không hiển thị gì (trong suốt, không nhận chạm) nhưng đủ để iOS cho phép điều
/// khiển âm lượng thiết bị.
struct SystemVolumeAnchor: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        SystemVolume.shared.anchorView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
