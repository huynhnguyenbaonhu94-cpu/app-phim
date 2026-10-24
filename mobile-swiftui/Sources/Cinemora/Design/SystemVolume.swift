import AVFoundation
import MediaPlayer
import SwiftUI

/// Điều khiển âm lượng của **máy** thay vì âm lượng riêng của trình phát.
///
/// `AVPlayer` có mức âm lượng riêng, nên trước đây kéo thanh âm lượng chỉ làm nhỏ
/// tiếng bên trong app còn âm lượng thiết bị vẫn nguyên. Ở đây dùng một `MPVolumeView`
/// để đặt đúng mức âm lượng của máy, đồng thời theo dõi `outputVolume` của
/// `AVAudioSession` nên thanh trượt luôn khớp với mức thật của thiết bị — kể cả khi
/// người dùng bấm nút cứng bên hông máy.
///
/// **Quan trọng:** `MPVolumeView` chỉ được gắn vào cửa sổ trong lúc thật sự cần ghi âm
/// lượng, rồi gỡ ra ngay sau đó. Để nó nằm thường trực trong cửa sổ sẽ khiến nút cứng
/// tăng/giảm âm lượng của máy không còn tác dụng trên toàn bộ app.
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

    /// Cửa sổ đang dùng, chỉ ghi nhớ chứ không thêm view vào.
    private weak var hostWindow: UIWindow?
    private var isAttached = false
    private var detachTask: DispatchWorkItem?

    private init() {
        let session = AVAudioSession.sharedInstance()
        let current = Double(session.outputVolume)
        value = current
        isMuted = current <= 0.001
        restoreValue = current > 0.001 ? current : 0.6

        volumeView.showsRouteButton = false
        volumeView.showsVolumeSlider = true
        volumeView.alpha = 0.001
        volumeView.clipsToBounds = true
        volumeView.isUserInteractionEnabled = false

        // Theo dõi mức âm lượng thật của máy. Việc theo dõi này không cần `MPVolumeView`
        // nằm trong giao diện, nên nút cứng vẫn cập nhật được thanh trượt của app.
        observation = session.observe(\.outputVolume, options: [.new, .initial]) { [weak self] session, _ in
            let level = Double(session.outputVolume)
            Task { @MainActor in self?.apply(level) }
        }
    }

    /// Ghi nhớ cửa sổ ứng dụng. Không thêm `MPVolumeView` vào ngay — xem `attachForWriting()`.
    @MainActor
    func register(window: UIWindow) {
        hostWindow = window
    }

    /// Đặt âm lượng thiết bị. Dùng thanh trượt con của `MPVolumeView` vì đây là API
    /// công khai duy nhất cho việc này; giá trị được gửi kèm sự kiện `valueChanged`.
    @MainActor
    func set(_ newValue: Double) {
        let clamped = min(1, max(0, newValue))
        // Bỏ qua khi mức không đổi. Mỗi lần ghi đều phải gắn lại `MPVolumeView`, nên nếu
        // ghi đè vô ích thì thay đổi người dùng vừa bấm bằng nút cứng sẽ bị nuốt mất.
        if abs(clamped - value) < 0.004 { return }
        apply(clamped)
        attachForWriting()
        // Đặt trên hàng đợi kế tiếp để không ghi đè trong lúc thanh trượt đang bị kéo.
        DispatchQueue.main.async { [weak self] in
            guard let self, let slider = self.slider else { return }
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

    /// Gắn `MPVolumeView` vào cửa sổ đúng lúc cần ghi, và hẹn gỡ ra sau khi người dùng thôi chỉnh.
    ///
    /// Khung 1×1 kèm `clipsToBounds` nên không bao giờ lộ ra giao diện; `alpha` nhỏ nhưng
    /// khác 0 vì iOS cần view nằm trong cây giao diện mới cho phép điều khiển âm lượng.
    @MainActor
    private func attachForWriting() {
        guard let window = hostWindow else { return }
        if !isAttached {
            volumeView.removeFromSuperview()
            volumeView.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            window.addSubview(volumeView)
            window.sendSubviewToBack(volumeView)
            // Ép bố cục ngay để thanh trượt con được tạo, nhờ vậy lần chỉnh âm lượng đầu
            // tiên đã có tác dụng thay vì phải chờ một vòng bố cục.
            volumeView.setNeedsLayout()
            volumeView.layoutIfNeeded()
            isAttached = true
        }
        detachTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.detach() }
        }
        detachTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: task)
    }

    /// Gỡ `MPVolumeView` khỏi cửa sổ để nút cứng của máy hoạt động bình thường trở lại.
    @MainActor
    private func detach() {
        guard isAttached else { return }
        volumeView.removeFromSuperview()
        isAttached = false
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

/// Ghi nhớ cửa sổ ứng dụng để `SystemVolume` biết chỗ gắn `MPVolumeView` khi cần — đặt một lần ở gốc app.
///
/// View này không thêm gì vào giao diện: nó chỉ báo lại cửa sổ đang dùng.
struct SystemVolumeWindowInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = InstallerView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onWindow = { [weak view] window in
            guard view != nil else { return }
            SystemVolume.shared.register(window: window)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let window = uiView.window { SystemVolume.shared.register(window: window) }
    }

    /// Báo ngay khi view vào cửa sổ, và báo lại nếu cửa sổ đổi.
    final class InstallerView: UIView {
        var onWindow: (@MainActor (UIWindow) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { onWindow?(window) }
        }
    }
}