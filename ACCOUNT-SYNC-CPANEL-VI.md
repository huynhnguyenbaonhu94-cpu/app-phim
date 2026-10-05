# Đồng bộ tài khoản và quản lý thiết bị Cinemora

## Phạm vi đã triển khai

- Đăng ký/đăng nhập bằng **email Gmail + mật khẩu**. Email được chuẩn hóa chữ thường; mật khẩu băm bằng `scrypt`, không lưu plaintext.
- Website vẫn xem phim bình thường không cần tài khoản; lịch sử xem và phim yêu thích trên website tiếp tục lưu local như source gốc.
- App SwiftUI là nơi dùng đăng nhập và đồng bộ cloud theo `userId`; các API cloud cũng có thể được website dùng tùy chọn sau này nhưng không bắt buộc.
- Phiên đăng nhập được lưu trong `account_sessions`, không còn là JWT stateless nên có thể kick/revoke từng thiết bị.
- Giới hạn tối đa **5 thiết bị đang đăng nhập** cho một account. Đăng nhập lại cùng thiết bị sẽ thay phiên cũ, không chiếm thêm slot.
- Giao diện Account website có danh sách thiết bị, online gần real-time (heartbeat 25 giây, online nếu heartbeat trong 90 giây), IP nếu server nhận được, kick, logout tất cả, logout hiện tại và đổi mật khẩu.
- Khi phiên bị kick, request kế tiếp nhận thông báo tiếng Việt và website tự xóa trạng thái đăng nhập; app SwiftUI có API tương ứng để đưa người dùng về màn hình login.
- Preferences playback/subtitle có bảng `account_preferences` và API `account.preferences` / `account.savePreferences` để tiếp tục nối UI SwiftUI.

## SQL chạy thủ công trên cPanel

Có thể chạy file [`drizzle/0005_account_sessions.sql`](./drizzle/0005_account_sessions.sql) trong phpMyAdmin hoặc terminal MySQL trên database `vfviehep_appphim`.

```bash
mysql -u USER -p vfviehep_appphim < drizzle/0005_account_sessions.sql
```

Backend cũng có compatibility repair khi startup: nếu hai bảng chưa tồn tại, nó sẽ tự tạo bằng `CREATE TABLE IF NOT EXISTS`. Vì vậy không bắt buộc chạy tay, nhưng nên chạy SQL trước khi restart để dễ kiểm tra quyền database.

## Environment cPanel

Giữ các biến đang có:

- `DATABASE_URL`
- `JWT_SECRET` (giữ lại để tương thích cấu hình cũ; session mới lưu token hash trong database)
- `NODE_ENV=production`
- `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`

Không hard-code mật khẩu admin. Nếu đang dùng `ADMIN_PASSWORD`, thay bằng mật khẩu riêng trong cPanel rồi restart Node app.

## Checklist deploy

1. Upload source đã build hoặc pull source lên application root `Cinemora2`.
2. Chạy `source /home/vfviehep/nodevenv/cinemora2/22/bin/activate && cd /home/vfviehep/cinemora2`.
3. Chạy `pnpm install --frozen-lockfile` và `pnpm build`.
4. Kiểm tra `DATABASE_URL` trỏ đúng `vfviehep_appphim`.
5. Restart Passenger/Node.js app trong cPanel.
6. Đăng nhập trên browser, mở `/account`, kiểm tra thiết bị hiện tại.
7. Mở thiết bị thứ hai; kiểm tra cả hai cùng xuất hiện. Kick thiết bị thứ hai và xác nhận request kế tiếp nhận cảnh báo.

## Giả định quan trọng

Trong source hiện tại chưa có Google OAuth Client ID/Secret và callback Google. Cụm “đăng ký bằng Gmail” vì vậy được triển khai là **dùng địa chỉ Gmail làm email tài khoản + mật khẩu riêng**, chưa phải nút “Sign in with Google”. Muốn OAuth Google thực sự cần bổ sung Google Cloud OAuth credentials, redirect URI và quy trình xác minh email; không nên tự điền giá trị giả vào production.

## Lỗi thường gặp đã xử lý

- Không dùng email làm định danh thiết bị; thiết bị có `deviceId` riêng.
- Không chỉ xóa cookie khi kick: session database được đánh dấu `revokedAt`, request sau đó bị từ chối.
- Không đếm phiên đã revoke vào giới hạn 5 thiết bị.
- Đổi mật khẩu kiểm tra mật khẩu cũ và bắt buộc hai mật khẩu mới trùng nhau.
- `logoutAll` revoke cả phiên hiện tại; user phải đăng nhập lại bằng mật khẩu mới.
- Có heartbeat/polling để tránh trạng thái online giả; IP có thể là IP proxy nếu cPanel không truyền đúng `X-Forwarded-For`.
- Cookie cần bật HTTPS trên domain thật; không tắt `httpOnly`/`sameSite` trong production.
- Website không bị chặn bởi account và không tự upload dữ liệu local. App sau khi login tải dữ liệu cloud về để dùng trên thiết bị mới.

## Kiểm thử đã chạy

- `pnpm check` — pass.
- `pnpm test` — pass, 14/14 test.
- `pnpm build` — pass; Vite có cảnh báo bundle lớn hiện hữu nhưng không làm build fail.
- SwiftUI chưa thể compile trong Ubuntu sandbox; cần chạy Xcode/Codemagic trên macOS để kiểm tra native UI và signing.
