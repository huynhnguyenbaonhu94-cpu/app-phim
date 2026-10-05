# Cinemora — Hệ thống tài khoản, session và đồng bộ dữ liệu

## Tóm tắt

Đã nâng cấp source hiện có (Express/tRPC + Drizzle/MySQL và ứng dụng iOS SwiftUI) theo hướng additive: giữ nguyên bảng favorites/history và luồng phim/player/admin, bổ sung session thiết bị, preferences và sync metadata. Không có thao tác `DROP` bảng hoặc xóa dữ liệu người dùng.

## Kiến trúc dữ liệu

- `users.passwordHash`: thêm an toàn nếu schema cũ thiếu; mật khẩu mới được hash bằng scrypt với salt ngẫu nhiên, không lưu plaintext.
- `movie_favorites` và `movie_watch_history`: tiếp tục dùng lại chính các bảng hiện hữu, với unique key theo user/movie(/episode); history có thêm `serverName` và `isCompleted` khi thiếu.
- `account_sessions`: session ID riêng cho từng thiết bị, device metadata, IP, last-seen, expiry và revoke reason; FK cascade và index cho user/session/device/online lookup.
- `user_playback_preferences`: lưu toàn bộ `PlaybackDefaults` và `SubtitlePreferences` dạng JSON, gồm subtitle style/mode, auto-next, PiP, stop timer và các field hiện có khác.
- `account_sync_tombstones`: lưu delete events bền vững theo user/kind/hash để thiết bị offline cũ không phục hồi favorite/history đã xóa.

`drizzle/0005_account_sessions_preferences.sql` là migration Drizzle additive. `account-system-import.sql` là SQL import thủ công idempotent cho MySQL/MariaDB cPanel, gồm cả các cột cũ có thể bị thiếu. Runtime cũng repair/kiểm tra hậu điều kiện schema; lỗi schema account quan trọng sẽ làm startup thất bại thay vì chạy với trạng thái thiếu bảng.

## API tRPC

- `auth.register`, `auth.login`, `auth.logout`, `auth.me`
- `account.current`, `account.devices`, `account.heartbeat`
- `account.kickDevice`, `account.logoutAll`, `account.changePassword`
- `account.favorites`, `account.addFavorite`, `account.removeFavorite`, `account.isFavorite`
- `account.history`, `account.recordHistory`, `account.savePreferences`, `account.sync`

Các mutation account dùng user lấy từ session server; client không được chọn `userId`. `passwordHash` bị loại khỏi user response. Session/device management, preferences và full sync yêu cầu session DB-backed.

## Session và thiết bị

- Mỗi login native tạo session UUID riêng; token được trả cho app chỉ khi request có device ID ổn định và được lưu bằng iOS Keychain. Web tiếp tục dùng HttpOnly cookie.
- JWT ký HS256 bằng `JWT_SECRET`; production thiếu secret sẽ fail closed. Các cookie/session cũ không có session ID được chuyển đổi tự động khi hoạt động trở lại, nhằm giữ đăng nhập/admin hiện tại trong khi đưa session vào cơ chế revoke mới.
- Session đã hết hạn/revoke được dọn sau 90 ngày khi user đăng nhập, giảm thời gian lưu IP và metadata lịch sử.
- Giới hạn 5 được kiểm tra trong server transaction, khóa hàng user bằng `SELECT ... FOR UPDATE`; login thứ 6 bị từ chối bằng thông báo cho người dùng. Re-login cùng device ID thay session cũ thay vì chiếm thêm slot.
- Heartbeat chạy khi app active khoảng 35 giây/lần; session không heartbeat trong 2 phút hiển thị offline. Khi bị kick, heartbeat/API trên app root phát hiện và chuyển về Login, không phụ thuộc đang ở màn player hay màn khác.
- IP thật được lưu trong DB để phục vụ audit thiết bị nhưng response cho app được che một phần.
- Logout tất cả revoke mọi session, gồm session hiện tại; các thiết bị khác phát hiện ở heartbeat tiếp theo. Khi sign-out offline, app xóa token active ngay và giữ token pending trong Keychain để gửi lệnh revoke khi mạng trở lại.

## Đổi mật khẩu

Form SwiftUI yêu cầu mật khẩu hiện tại, mật khẩu mới và xác nhận; kiểm tra khớp, tối thiểu 10 ký tự cho mật khẩu mới. Backend xác minh mật khẩu cũ, rate-limit lỗi, không ghi mật khẩu/token vào log. Sau khi đổi, app đưa ra đúng hai lựa chọn:

- **Có**: gọi revoke tất cả session, gồm thiết bị hiện tại, rồi về Login.
- **Không**: giữ nguyên toàn bộ session; app tiếp tục hoạt động.

## Đồng bộ và migration dữ liệu cũ

- Local library tiếp tục hoạt động offline; account snapshots được tách theo user ID, giữ các dữ liệu UserDefaults cũ. Guest data cũ chỉ được migrate một lần vào tài khoản đầu tiên trên thiết bị; sau khi server xác nhận sync, bản guest gốc được dọn để không đưa dữ liệu đó sang tài khoản khác.
- Khi đăng nhập/đăng ký, app merge guest/local snapshot lên server theo unique movie/episode key; không xóa local data trước phản hồi sync thành công.
- Progress history hợp nhất theo `lastWatchedAt`; giữ watched seconds, duration, server/source, episode completion và metadata phim. Favorite giữ `addedAt` mới nhất.
- Mọi thay đổi local đánh dấu sync pending; app retry nền khi mạng trở lại, request idempotent; server áp dụng timestamp-aware upsert và persistent tombstones cho xóa offline.
- Cài đặt playback/subtitle được merge theo `updatedAt`; timestamp client vượt quá clock-skew hợp lý được clamp ở server.

## File thay đổi/thêm

### Swift/iOS

- `mobile-swiftui/Sources/Cinemora/Models/AccountModels.swift` — models API account/device/sync.
- `mobile-swiftui/Sources/Cinemora/State/AccountCredentialStore.swift` — Keychain token và pending revoke queue.
- `mobile-swiftui/Sources/Cinemora/API/CinemaAPI.swift` — Bearer auth và account tRPC client.
- `mobile-swiftui/Sources/Cinemora/State/CinemaStore.swift` — account/session lifecycle, per-user cache, merge/offline retry.
- `mobile-swiftui/Sources/Cinemora/State/LocalLibraryModels.swift` — tương thích giải mã UserDefaults cũ và completion state.
- `mobile-swiftui/Sources/Cinemora/Views/AccountScreen.swift` — UI account, thiết bị, đổi mật khẩu, sync và logout.
- `mobile-swiftui/Sources/Cinemora/Views/LocalLibraryScreens.swift` — tích hợp account vào Saved Hub hiện hữu.
- `mobile-swiftui/Sources/Cinemora/CinemoraApp.swift` — monitoring toàn app và login sau revoke.
- `mobile-swiftui/Sources/Cinemora/Player/CinemaPlayerScreen.swift` — lưu episode completion/progress.

### Backend/DB

- `server/routers.ts`, `server/db.ts`, `server/localAuth.ts`
- `server/_core/context.ts`, `server/_core/trpc.ts`, `server/_core/index.ts`
- `server/account.test.ts`
- `drizzle/schema.ts`, `drizzle/0005_account_sessions_preferences.sql`, `drizzle/meta/_journal.json`
- `account-system-import.sql`
- `CPANEL-TELEGRAM-SETUP-VI.md` — sửa hướng dẫn bỏ admin credential mặc định, yêu cầu `ADMIN_PASSWORD` riêng khi cần bootstrap.

## Cài đặt và chạy trên cPanel

Giữ nguyên `DATABASE_URL`, `JWT_SECRET`, `NODE_ENV` và các biến hiện hữu; không tạo database hoặc cấu hình DB mới. Node.js 22, application root `/home/vfviehep/cinemora2`, startup `dist/index.js`.

1. Sao lưu database theo quy trình cPanel trước khi nâng cấp.
2. Upload/cập nhật source; có thể import `account-system-import.sql` thủ công vào database đang chọn trong phpMyAdmin. Nếu không import thủ công, Drizzle/runtime migration sẽ tạo/repair các bảng additive khi app khởi động.
3. Tại application root chạy:

   ```bash
   npm ci
   npm run check
   npm test
   npm run build
   ```

4. Đặt startup file là `dist/index.js`, restart Node.js app.
5. Nếu database chưa có admin nào, cấu hình `ADMIN_PASSWORD` tối thiểu 12 ký tự trước startup để bootstrap admin; tài khoản admin hiện có không bị ghi đè. Không dùng mật khẩu mặc định ở production.

## Kết quả kiểm tra

- `npm run check`: đạt.
- `npm test`: 5 test files, **17/17 tests đạt**.
- `npm run build`: đạt; Vite phát cảnh báo bundle JavaScript hiện tại lớn hơn 500 kB (cảnh báo tối ưu, không làm build thất bại).
- Swift sources đã được parse cú pháp bằng tree-sitter; sandbox hiện tại là Linux, không có Swift/Xcode toolchain nên **chưa thể xác nhận Xcode/iOS type-check hoặc archive build**.
- Sandbox không có `DATABASE_URL`; **chưa chạy migration hoặc kiểm tra API trên database production thật**. Cần xác minh migration sau backup trong cPanel/staging trước khi phục vụ người dùng.

## Lệnh kiểm tra sau triển khai

- Tạo tài khoản trên app, xác nhận `account_sessions` có session riêng và favorites/history/settings xuất hiện trong DB.
- Đăng nhập đủ 5 thiết bị; thiết bị thứ 6 phải bị từ chối; kick một session rồi thử lại.
- Test logout all, kick khi player đang mở, đổi mật khẩu cả lựa chọn Có/Không.
- Tắt mạng, tạo favorite/history/xóa một record/đổi subtitle settings; mở mạng lại và xác nhận dữ liệu hội tụ trên thiết bị khác.
- Kiểm tra `/api/trpc/account.devices` chỉ trả IP đã che và không bao giờ trả `passwordHash`.
