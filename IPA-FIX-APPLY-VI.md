# Fix IPA build lần 2

Log `pasted_content_2.txt` vẫn là lỗi cũ, chứng tỏ Codemagic đang build revision chưa nhận source mới.

## Dấu hiệu source bị stale

Log vẫn chứa:

- `CinemaStore` không có `accountBusy`, `accountSyncing`, `accountSyncPending`.
- `AccountDevice` không có `name`.
- Vẫn gọi `mediaSelectionGroup(forMediaCharacteristic:)`.

Trong bản sửa mới, các lỗi này đã được xử lý.

## Cách đưa đúng bản sửa vào Codemagic

1. Giải nén `Cinemora-ipa-build-fix.zip` vào đúng repository/branch mà workflow `cinemora-ios` đang build.
2. Đảm bảo các file sau nằm trong commit mới:
   - `mobile-swiftui/Sources/Cinemora/State/CinemaStore.swift`
   - `mobile-swiftui/Sources/Cinemora/Models/AccountModels.swift`
   - `mobile-swiftui/Sources/Cinemora/Player/CinemaPlayerScreen.swift`
   - `mobile-swiftui/Sources/Cinemora/Views/TVScreen.swift`
   - `codemagic.yaml`
3. Commit và push lên đúng branch đang chọn trong Codemagic.
4. Tạo build mới, không chỉ bấm retry build cũ nếu revision chưa thay đổi.
5. Trong log phải thấy bước `Verify latest SwiftUI build fixes` pass. Nếu source cũ, preflight mới sẽ dừng với thông báo `stale ... detected` thay vì chờ archive rồi báo lỗi dài.

Sandbox không có Xcode/macOS nên không thể archive IPA trực tiếp; source đã được kiểm tra symbol bằng grep và backend `pnpm check` pass.
