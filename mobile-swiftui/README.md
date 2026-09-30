# Cinemora SwiftUI (prototype)

Native SwiftUI iOS app, kept alongside `mobile/` Expo app during the migration trial. It uses the existing public tRPC API at `https://cungcapicloud.id.vn`; it does not replace the existing website or backend.

## Stack

- SwiftUI, Swift concurrency, native `TabView` and `NavigationStack`
- iOS 26 Liquid Glass through `glassEffect` with an iOS 17+ material fallback
- AVPlayer for HLS, WKWebView for embed-only episodes
- Netflix-style player controls: vuốt dọc bắt đầu từ vùng dưới màn hình — bên trái chỉnh độ sáng, bên phải chỉnh âm lượng; HUD dạng thanh dọc chỉ hiện ở góc tương ứng và tự ẩn sau thao tác
- Cài đặt mặc định trong mục Lưu cho tự chuyển tập, hẹn giờ tắt và Picture-in-Picture (PiP)
- Trong player, vuốt dọc ở bất kỳ vị trí bên trái/phải để chỉnh sáng/âm lượng; HUD mức điều chỉnh trong suốt và vẫn nhận gesture khi control bar đang hiện
- Nút Video liên quan mở trình duyệt gợi ý toàn màn hình, chọn card để xem chi tiết phim tiếp theo
- XcodeGen project spec in `project.yml`

## Generate in Codemagic/macOS

```sh
brew install xcodegen
cd mobile-swiftui
xcodegen generate
open Cinemora.xcodeproj
```

The Ubuntu sandbox used for editing has no Xcode or Swift compiler, so the actual iOS compilation, simulator preview, signing, and IPA must be validated by Codemagic or Xcode on macOS.

## Truyền hình trực tiếp

Tab **Truyền Hình** tải các kênh admin cấu hình từ procedure `tv.list`, phát HLS bằng `AVPlayer` và lắng nghe `/api/tv/events` qua SSE. Khi admin thêm, sửa, ẩn hoặc xóa stream ở `https://cungcapicloud.id.vn/admin/tv`, danh sách trong app được thay đổi ngay khi màn hình Truyền hình đang mở; kết nối tự thử lại nếu mạng bị gián đoạn.

Poster TV được lấy từ `posterUrl`; nếu admin bỏ trống, app dùng asset `TVPosterDefault`. Trình phát TV dùng AVPlayerLayer và hỗ trợ play/pause, âm lượng, fullscreen và Picture-in-Picture trên các thiết bị/iOS tương thích.
