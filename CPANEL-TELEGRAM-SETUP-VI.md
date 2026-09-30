# Cấu hình cPanel cho Cinemora và Telegram

## 1. Startup file của ứng dụng Node.js

Trong cPanel Node.js Selector, dùng:

```text
Application mode: Production
Node.js version: 22.18.0
Application root: cinemora2
Application URL: https://cungcapicloud.id.vn
Application startup file: dist/index.js
```

Không dùng `server/_core/index.ts` làm startup file vì cPanel cần file JavaScript đã build.

## 2. Cài đặt và build trên Terminal cPanel

Bản source mới đã bỏ plugin debug không tương thích với Vite 7, vì vậy dùng `npm install` bình thường:

```bash
source /home/vfviehep/nodevenv/cinemora2/22/bin/activate
cd /home/vfviehep/cinemora2
rm -rf node_modules package-lock.json
npm install
npm run build
```

Sau khi build xong, quay lại cPanel Node.js Selector và bấm **Restart** ứng dụng.

Nếu hosting không có lệnh `npm run build` vì thiếu dependency, chạy:

```bash
npm install --include=dev
npm run build
```

Nếu cPanel vẫn đang dùng source ZIP cũ hoặc npm hiển thị lại lỗi peer dependency, hãy dùng đúng ZIP mới. Phương án tạm thời cho source cũ là:

```bash
npm install --legacy-peer-deps
npm run build
```

Không upload hoặc commit thư mục `node_modules`; cPanel tự cài dependency từ `package.json`.

## 3. Environment variables bắt buộc cho yêu cầu phim

Thêm hai biến này trong mục **Environment variables** của cPanel:

```text
TELEGRAM_BOT_TOKEN=token_do_BotFather_cap
TELEGRAM_CHAT_ID=id_chat_nhan_thong_bao
```

`TELEGRAM_BOT_TOKEN` lấy từ BotFather. Để lấy `TELEGRAM_CHAT_ID` cho chat cá nhân:

1. Mở bot và nhấn `/start`.
2. Truy cập tạm thời:
   `https://api.telegram.org/botTOKEN_CUA_BAN/getUpdates`
3. Lấy giá trị `message.chat.id`.
4. Xóa URL/token khỏi lịch sử trình duyệt hoặc đổi token nếu lỡ công khai.

Nếu gửi vào group, thêm bot vào group, gửi một tin nhắn rồi lấy `chat.id` thường có dạng số âm, ví dụ `-100xxxxxxxxxx`.

## 4. Environment variables nên có cho production

```text
NODE_ENV=production
JWT_SECRET=chuoi_bi_mat_dai_va_ngau_nhien
DATABASE_URL=mysql://user:password@127.0.0.1:3306/database_name
```

`DATABASE_URL` cần nếu bật các chức năng tài khoản, lịch sử và yêu thích đồng bộ server. Bản SwiftUI hiện vẫn có lịch sử/yêu thích cục bộ trên thiết bị, nhưng nên cấu hình database nếu muốn dùng backend account sau này.

Các biến sau chỉ cần nếu project của bạn đang dùng các tích hợp tương ứng:

```text
VITE_APP_ID=
OWNER_OPEN_ID=
BUILT_IN_FORGE_API_URL=
BUILT_IN_FORGE_API_KEY=
MOBILE_APP_ORIGINS=capacitor://localhost,http://localhost,https://localhost
```

Không đưa `TELEGRAM_BOT_TOKEN`, `DATABASE_URL` hoặc `JWT_SECRET` vào source code, ZIP public hay GitHub.

## 5. Cách tính năng hoạt động

Ứng dụng SwiftUI gửi form tới procedure:

```text
cinema.submitRequest
```

Backend kiểm tra dữ liệu, sau đó gọi Telegram Bot API ở phía server. Token Telegram không bao giờ được gửi xuống app iOS. Nếu có ảnh, backend gửi bằng `sendPhoto`; nếu không có ảnh, backend gửi bằng `sendMessage`.

Có giới hạn chống gửi liên tục: cùng một địa chỉ IP chỉ được gửi một yêu cầu trong mỗi 30 giây.

## 6. Kiểm tra sau khi restart

Kiểm tra API phim:

```bash
curl -I https://cungcapicloud.id.vn
```

Sau đó mở app, vào:

```text
Lưu → Yêu cầu phim
```

Gửi thử một yêu cầu. Bot Telegram phải nhận được tên phim, link, mức ưu tiên, ghi chú và ảnh nếu đã chọn.

## 7. Quản lý Truyền hình và cập nhật realtime

### Tạo bảng dữ liệu mới

Bản cập nhật thêm bảng `tv_streams`. Sau khi upload source mới vào `/home/vfviehep/cinemora2`, chạy:

```bash
source /home/vfviehep/nodevenv/cinemora2/22/bin/activate
cd /home/vfviehep/cinemora2
npm install --include=dev
npm run db:push
npm run build
```

Nếu cPanel đã quản lý migration bằng Drizzle, file migration mới trong thư mục `drizzle/` (hiện là `drizzle/0003_chemical_dormammu.sql`) cũng có thể được chạy một lần trong đúng database của Cinemora. Không chạy lặp lại nếu bảng đã tồn tại. Khi dùng `npm run db:push`, hãy để Drizzle quản lý migration từ journal; không chạy thêm các file migration thủ công bên ngoài journal.

### Thêm stream bằng web

1. Đăng nhập tài khoản có `role=admin` trên website.
2. Mở `https://cungcapicloud.id.vn/admin/tv`.
3. Nhập tên kênh và URL HLS (`.m3u8`) hoặc URL stream trực tiếp, sau đó bấm **Thêm kênh**.
4. Có thể thêm logo, mô tả, thứ tự hiển thị; bỏ chọn **Hiển thị trên app** để ẩn kênh mà không cần xóa.

API admin là các procedure `tv.adminList`, `tv.create`, `tv.update`, `tv.remove`. Tất cả thao tác này yêu cầu session của user có role `admin`. URL stream được kiểm tra ở server; không đưa token Telegram hay thông tin database xuống app.

### Realtime

- App SwiftUI tải danh sách kênh qua `tv.list`.
- App mở kết nối Server-Sent Events tại `/api/tv/events`.
- Sau khi admin thêm/sửa/xóa/ẩn kênh, backend phát snapshot mới ngay trên kết nối SSE; app cập nhật danh sách mà không cần tắt/mở lại.
- Nếu mạng hoặc tiến trình Node bị ngắt, app tự kết nối lại sau 3 giây và lấy snapshot mới.

SSE cần được proxy qua HTTPS và không được bật cache. Nếu dùng Cloudflare hoặc proxy cPanel, giữ nguyên `Connection: keep-alive`, `Cache-Control: no-cache, no-transform` và tắt buffering cho `/api/tv/events`.

### Tạo admin local nếu cần

Tài khoản đăng ký mới mặc định là `user`. Nếu cần cấp quyền quản trị cho tài khoản local, chạy một lần trong MySQL (thay email bằng email thật):

```sql
UPDATE users SET role = 'admin' WHERE email = 'admin@example.com';
```

Sau đó đăng xuất/đăng nhập lại để session nhận role mới.

## 8. Poster, kiểm tra nguồn và trình phát TV

Khi thêm hoặc sửa kênh, backend sẽ tự kiểm tra URL bằng request GET có timeout 8 giây và lưu:

- `online`: nguồn trả về HTTP thành công.
- `offline`: lỗi HTTP, không kết nối được hoặc timeout.
- `unknown`: chưa kiểm tra hoặc đang chuẩn bị kiểm tra.

Kết quả hiển thị ngay trong trang `/admin/tv`. Các URL `.m3u8`, MP4 hoặc định dạng stream HTTP/HTTPS khác đều được chấp nhận nếu thiết bị phát hỗ trợ định dạng đó.

Mỗi kênh có thể nhập **Poster truyền hình**. Nếu bỏ trống poster, app dùng poster mặc định Cinemora TV có sẵn trong asset app. Trường `logoUrl` chỉ là logo nhỏ tùy chọn và được dùng làm fallback poster cho dữ liệu cũ.

Trong app SwiftUI, màn hình phát TV có:

- Play/Pause.
- Tắt/mở tiếng và thanh tăng/giảm âm lượng.
- Mở toàn màn hình.
- Picture-in-Picture nếu thiết bị/iOS hỗ trợ.
- Hiển thị trạng thái online/offline của nguồn.
