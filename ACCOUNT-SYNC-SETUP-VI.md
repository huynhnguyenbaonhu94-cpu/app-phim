# Cinemora — Tài khoản, đồng bộ và quản lý thiết bị

## Tóm tắt thay đổi

Bản source này bổ sung các tính năng dùng chung giữa website và ứng dụng SwiftUI:

- Đăng ký/đăng nhập bằng **địa chỉ Gmail hoặc email + mật khẩu Cinemora**. Đây là tài khoản email/mật khẩu của Cinemora, **không phải nút “Sign in with Google”/OAuth Google** và hiện chưa có bước xác minh email.
- Backend lưu lịch sử xem, tập đang xem, thời lượng đã xem, yêu thích và cài đặt phát/phụ đề theo `userId` trong MySQL. Website cũng đồng bộ tùy chọn tự chuyển tập; cập nhật từng trường không ghi đè cài đặt phụ đề trên iOS.
- App iOS gửi token qua HTTPS Bearer; token được lưu trong **iOS Keychain**, không lưu mật khẩu. Website tiếp tục dùng cookie `HttpOnly`.
- Quản lý phiên/thiết bị: tên thiết bị, dòng thiết bị nếu client cung cấp, IP nếu hosting cung cấp, lần hoạt động gần nhất, trạng thái Online và nút đăng xuất từng thiết bị.
- Tối đa **5 phiên chưa đăng xuất** trên một tài khoản. Thời gian Online được tính khi thiết bị có hoạt động trong 90 giây vừa qua.
- Thu hồi thiết bị sẽ làm phiên đó bị từ chối ở API kế tiếp. App iOS kiểm tra phiên mỗi 25 giây; website gọi heartbeat mỗi 30 giây. Vì vậy việc đá thiết bị đang xem phim thường có độ trễ tối đa khoảng 25–30 giây, không thể ngắt kết nối internet tức thời.
- Đổi mật khẩu cần mật khẩu cũ và hai trường mật khẩu mới trùng nhau. Sau khi đổi thành công, app/website hỏi có đăng xuất tất cả thiết bị (kể cả thiết bị hiện tại) hay không.
- Lịch sử và yêu thích cục bộ hiện có được gộp lên tài khoản khi đăng nhập. Khi đăng xuất, bản cache thư viện cục bộ được xóa để tránh lộ dữ liệu giữa các tài khoản trên cùng máy.

> Lưu ý: các JWT/cookie phiên của bản cũ không có `sessionId` phía database sẽ không còn hợp lệ sau khi nâng cấp. Người dùng cần đăng nhập lại một lần.

## 1. Sao lưu trước khi cập nhật

1. Sao lưu database `vfviehep_appphim` từ phpMyAdmin/cPanel.
2. Sao lưu thư mục ứng dụng hiện tại `/home/vfviehep/cinemora2`.
3. Không ghi đè các biến bí mật của Node.js Selector bằng nội dung source.

## 2. Triển khai backend/website qua cPanel Terminal

Upload và giải nén source mới vào Application root đã dùng cho Cinemora, sau đó chạy:

```bash
source /home/vfviehep/nodevenv/cinemora2/22/bin/activate
cd /home/vfviehep/cinemora2
npm install --include=dev
npm run build
```

Giữ các cấu hình hiện tại:

```text
Node.js version: 22.18.0
Application mode: Production
Application root: Cinemora2
Application URL: https://cungcapicloud.id.vn
Application startup file: dist/index.js
```

Vào **cPanel → Setup Node.js App → Restart** sau khi build xong.

### Biến môi trường cần có

```text
DATABASE_URL=mysql://.../vfviehep_appphim
JWT_SECRET=<chuỗi bí mật ngẫu nhiên tối thiểu 32 ký tự>
NODE_ENV=production
```

Giữ các biến Telegram đang có nếu website đang dùng tính năng gửi yêu cầu phim. Không đưa giá trị thật của `DATABASE_URL`, `JWT_SECRET`, `TELEGRAM_BOT_TOKEN` vào source, ZIP public hoặc ảnh chụp màn hình.

Nếu database **chưa có admin** và cần tạo tài khoản quản trị mới, hãy đặt thêm `ADMIN_EMAIL`, `ADMIN_PASSWORD` (tối thiểu 12 ký tự) và tùy chọn `ADMIN_NAME`. Backend không còn tạo mật khẩu admin mặc định dễ đoán. Nếu database đã có tài khoản admin dùng thông tin mặc định từ source cũ, hãy đăng nhập và đổi ngay ở trang Tài khoản; thay biến môi trường không tự ghi đè mật khẩu của tài khoản đã tồn tại.

### Tạo bảng mới

Backend sẽ chạy migration `drizzle/0005_account_device_sync.sql` khi khởi động và có bước tự tạo bảng tương thích. Thông thường không cần thao tác SQL thủ công.

Nếu bạn muốn tạo bảng trước trong phpMyAdmin, hãy chạy một lần file [account_device_sync.sql](./account_device_sync.sql) trên đúng database `vfviehep_appphim`. Sau đó deploy/restart backend như trên. Các lệnh `CREATE TABLE IF NOT EXISTS` an toàn nếu bảng đã tồn tại.

Bảng mới:

- `auth_sessions`: thông tin phiên, heartbeat và trạng thái thu hồi của từng thiết bị.
- `account_preferences`: cài đặt phát/phụ đề đồng bộ của mỗi tài khoản.

Lịch sử và yêu thích dùng các bảng hiện có `movie_watch_history` và `movie_favorites`; không xóa các bảng này.

## 3. Build và phát hành app iOS

Backend tương thích với API hiện có nhưng các chức năng mới trên iOS chỉ hoạt động sau khi build lại app từ thư mục `mobile-swiftui` và phát hành bản mới cho người dùng. App cũ chưa có giao diện/quy trình gửi Bearer token và không thể hiện danh sách thiết bị mới.

## 4. Kiểm tra theo thứ tự

1. Sau khi restart, xem cPanel Node.js application log. Cần có thông báo migration/khởi tạo database hoàn tất; nếu thấy `JWT_SECRET phải có ít nhất 32 ký tự`, cập nhật secret trong cPanel rồi restart.
2. Mở website `https://cungcapicloud.id.vn`, đăng ký bằng email/Gmail và mật khẩu tối thiểu 8 ký tự.
3. Mở **Tài khoản**: kiểm tra thiết bị website xuất hiện; trạng thái Online cập nhật khi website còn mở.
4. Đăng nhập tài khoản đó trên app iOS mới: kiểm tra tối đa 5 thiết bị, tên model/IP (IP có thể không hiện nếu reverse proxy của hosting không chuyển tiếp địa chỉ client), yêu thích và lịch sử được đồng bộ.
5. Mở phim, xem một tập một lúc, sau đó vào máy thứ hai: kiểm tra tên phim, tập và tiến độ gần nhất. Bản app lưu gần nhất cho mỗi phim trong giao diện lịch sử; database có thể giữ nhiều bản ghi tập.
6. Sửa cài đặt phụ đề/ phát trên iOS, đăng nhập tài khoản trên iOS khác và kiểm tra cài đặt được áp dụng.
7. Trong trang thiết bị, kick một thiết bị thử nghiệm; thiết bị đó phải quay về đăng nhập khi heartbeat tiếp theo đến.
8. Thử đổi mật khẩu sai/không trùng để kiểm tra lỗi; sau khi đổi đúng chọn **Không** rồi kiểm tra phiên còn nguyên; đổi lần nữa và chọn **Có** để kiểm tra tất cả phiên (kể cả phiên hiện tại) bị thu hồi, sau đó đăng nhập lại bằng mật khẩu mới.

## 5. Các lưu ý vận hành/giới hạn

- “Online” dựa trên heartbeat 90 giây, không phải trạng thái socket của trình phát; thiết bị tắt app/mất mạng sẽ chuyển ngoại tuyến sau khoảng 90 giây.
- Nếu người dùng đã đăng nhập đủ 5 thiết bị nhưng mất quyền truy cập tất cả thiết bị cũ, họ không thể tự đăng nhập máy thứ sáu để tự kick phiên. Khi đó cần khôi phục quyền truy cập một thiết bị cũ hoặc nhờ admin thu hồi phiên trong database. Không xóa hàng loạt dữ liệu tài khoản.
- Source này dùng mật khẩu Cinemora gắn với email/Gmail; không gửi email reset/xác minh vì cấu hình hiện tại chưa có dịch vụ SMTP. Nếu muốn xác minh Gmail hoặc đăng nhập Google OAuth, cần cấu hình thêm dịch vụ và luồng xác thực riêng.
- Khi chưa đăng nhập, thư viện vẫn hoạt động ở chế độ cục bộ để giữ tương thích; sau đăng nhập các thay đổi được đẩy lên tài khoản.
- Lịch sử/yêu thích và thiết lập phụ đề được đưa vào tài khoản. Một số thiết lập iOS/phần cứng (ví dụ quyền Picture-in-Picture của hệ điều hành) vẫn do hệ điều hành/thiết bị quyết định.
