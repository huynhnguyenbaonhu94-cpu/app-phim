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

```bash
source /home/vfviehep/nodevenv/cinemora2/22/bin/activate
cd /home/vfviehep/cinemora2
npm install
npm run build
```

Sau khi build xong, quay lại cPanel Node.js Selector và bấm **Restart** ứng dụng.

Nếu hosting không có lệnh `npm run build` vì thiếu dependency, chạy:

```bash
npm install --include=dev
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
