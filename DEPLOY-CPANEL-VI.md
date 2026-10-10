# Upload backend lên cPanel (cungcapicloud.id.vn)

Gói này là **phần backend** để upload lên cPanel Node.js Selector, không gồm app iOS.

## 1. Gói này có gì

```text
client/            website (Vite + React) + trang quản trị phim mới /admin/movies
server/            tRPC API, gồm commentFeed.ts (bình luận real-time)
drizzle/           schema + migration
shared/            kiểu dùng chung
cpanel-comments/   dịch vụ bình luận PHP (tuỳ chọn, chỉ cần nếu không dùng Node)
package.json, tsconfig.json, vite.config.ts, drizzle.config.ts …
```

Không có `mobile-swiftui/` (app iOS không cần cho backend) và không có `node_modules`
(cPanel tự cài).

## 2. Các bước

Đúng theo cấu hình bạn đang dùng: Application root `cinemora2`, URL
`https://cungcapicloud.id.vn`, startup file `dist/index.js`.

```bash
# 1. Giải nén đè vào thư mục ứng dụng (giữ nguyên node_modules cũ)
cd /home/vfviehep/cinemora2
unzip -o /duong/dan/Cinemora-Backend-Cpanel.zip

# 2. Cài dependency và build
source /home/vfviehep/nodevenv/cinemora2/22/bin/activate
npm install --include=dev
npm run build
```

Sau đó vào cPanel Node.js Selector bấm **Restart**.

## 3. Không cần chạy SQL tay

Backend tự xử lý khi khởi động:

- Tự chạy migration trong `drizzle/`.
- Tự thêm cột còn thiếu: `users.avatar`, `users.badge`, `movie_comments.pinnedAt`, và
  các cột `tv_streams` như trước.
- Tự tạo tài khoản admin mặc định nếu chưa có.

Log khởi động cần thấy:

```text
[Database] Added missing users column: avatar
[Database] Added missing users column: badge
Migration and default admin check completed.
```

## 4. Environment variables

Không cần thêm biến mới cho đợt này. Giữ nguyên những biến đang chạy:

```text
NODE_ENV=production
JWT_SECRET=…
DATABASE_URL=mysql://…
TELEGRAM_BOT_TOKEN=…
TELEGRAM_CHAT_ID=…
ADMIN_EMAIL=…
ADMIN_PASSWORD=…
```

## 5. Kiểm tra sau khi Restart

1. `https://cungcapicloud.id.vn/admin/movies` — chọn một phim, xem bình luận.
2. Mở app, gửi một bình luận ở cùng phim đó → trang quản trị phải nhảy bình luận lên
   **ngay** (không phải bấm làm mới).
3. Trên `/admin/accounts`, đặt nhãn cho một tài khoản (ví dụ `VIP`) rồi xem lại bình luận
   cũ của tài khoản đó trên app: tên phải đổi thành `Tên (VIP)` ngay.
4. Bấm **Ghim lên đầu** ở một bình luận → bình luận đó nằm đầu danh sách trên cả web và app.
5. Trong app: **Tài khoản & thiết bị** → chạm vào ảnh đại diện → chọn ảnh → ảnh phải hiện
   ở mọi bình luận của tài khoản đó.

## 6. Lưu ý

- Đừng xoá thư mục `uploads/` khi giải nén, poster truyền hình đang nằm trong đó.
- Không upload `node_modules`; nếu đã lỡ có thì xoá rồi `npm install` lại.
- Nếu `npm run build` báo thiếu dependency, chạy `npm install --include=dev` trước.
- `cpanel-comments/` chỉ là phương án dự phòng khi hosting không chạy được Node; dùng nó
  thì app sẽ tự lùi về làm mới bình luận mỗi 6 giây và không có ghim/nhãn quyền.
## 7. Xử lý sự cố

### Lỗi khi đặt Nhãn hiển thị (badge)

```text
Failed query: update `users` set `badge` = ? where `users`.`id` = ? params: Đẹp zai,8
```

Nhãn có dấu tiếng Việt ("Đẹp zai") mà bảng `users` của bản cũ đang là `latin1` thì MySQL
từ chối (`Incorrect string value`), vì cột mới thừa hưởng bảng mã của bảng. Trường hợp
còn lại là cột `badge`/`avatar` chưa được tạo (`Unknown column`).

Chạy khối lệnh này trong phpMyAdmin của database đang dùng — **không cần build lại**:

```sql
ALTER TABLE `users` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER TABLE `users` ADD COLUMN `badge` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL;
ALTER TABLE `users` ADD COLUMN `avatar` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL;
```

Dòng `ADD` báo `Duplicate column name` là bình thường, nghĩa là cột đã có. Nếu cột đã có
sẵn nhưng sai bảng mã, chạy thêm hai dòng này rồi thử lại:

```sql
ALTER TABLE `users` MODIFY COLUMN `badge` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL;
ALTER TABLE `users` MODIFY COLUMN `avatar` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL;
```

Sau khi chạy SQL, đặt nhãn lại — không cần khởi động lại ứng dụng.

Bản source trong gói này cũng đã tự làm việc đó: khi khởi động, backend tự chuyển bảng
`users` sang utf8mb4, tự tạo cột với bảng mã đúng, và nếu gặp lỗi lúc đang ghi nhãn hoặc
ảnh đại diện thì tự sửa rồi thử lại ngay trong cùng request. Log sẽ ghi rõ:

```text
[Database] Converted users charset from latin1 to utf8mb4.
[Database] Added missing users column: badge
```

### Xem bảng mã hiện tại của bảng users

```sql
SELECT COLUMN_NAME, CHARACTER_SET_NAME FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users';
```

Cột `badge` và `avatar` phải hiện `utf8mb4`. Nếu còn `latin1` thì chạy khối SQL ở trên.