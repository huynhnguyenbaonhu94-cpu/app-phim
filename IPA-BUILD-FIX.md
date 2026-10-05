# Cinemora — Sửa lỗi build signed IPA

## Nguyên nhân trong log được gửi

Log Codemagic chỉ rõ hai chỗ dùng API AVFoundation đã deprecated từ iOS 16:

- `CinemaPlayerScreen.swift`: `AVAsset.mediaSelectionGroup(forMediaCharacteristic:)`
- `TVScreen.swift`: cùng API trong live-TV playback

Đây là các diagnostic xuất hiện trong bước `SwiftCompile` của archive. Trích đoạn đính kèm bị rút gọn nên không thể xác nhận có còn lỗi compiler khác ngoài hai diagnostic đã hiển thị.

## Thay đổi

- Cả hai nơi nay dùng `try await asset.loadMediaSelectionGroup(for: .legible)`, API async chính thức có từ iOS 15 và tương thích deployment target iOS 17 của project.
- Subtitle metadata được tải riêng sau khi player item sẵn sàng, nên không làm UI chờ metadata trước khi báo phát video/TV.
- Sau khi `await`, chỉ thay selection nếu `AVPlayerItem` vẫn là item đang phát. Lỗi tải subtitle không chặn video/live stream.
- `codemagic.yaml` có preflight chặn API deprecated cũ tái xuất hiện.

## Kiểm tra đã chạy

- Parse cú pháp bằng tree-sitter: 22 Swift files, không có lỗi cú pháp.
- Codemagic source preflight chạy cục bộ: đạt.
- Tìm kiếm toàn bộ Swift source: không còn `mediaSelectionGroup(forMediaCharacteristic:)`; cả hai call site dùng API async mới.
- Đã đối chiếu chữ ký và availability với tài liệu chính thức của Apple: `loadMediaSelectionGroup(for:)` là `async throws`, khả dụng từ iOS 15.

## Giới hạn

Sandbox này chạy Linux, không có `xcodebuild`, Xcode/iOS SDK hay signing profiles. Vì vậy không thể thực hiện archive iOS hoặc tạo IPA tại đây, và chưa thể khẳng định Codemagic sẽ hoàn tất ký gói cho tới khi workflow chạy lại trên macOS. Không thay đổi provisioning profile, bundle ID hay thông tin signing.

Hãy upload gói source cập nhật và chạy lại workflow `cinemora-ios`. Nếu Codemagic vẫn fail, cần lấy toàn bộ các dòng `error:` đầu tiên và phần compiler diagnostics (không dùng đoạn log đã rút gọn) để sửa lỗi tiếp theo nếu có.
