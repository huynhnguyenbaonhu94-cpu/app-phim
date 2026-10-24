# Upload backend lên cPanel (cungcapicloud.id.vn)

Gói này là **phần backend** để upload lên cPanel Node.js Selector, không gồm app iOS.

## 1. Gói này có gì

```text
dist/              BẢN ĐÃ DỰNG SẴN: index.js (server) + public/ (website) — không phải build lại
client/            website (Vite + React) + trang quản trị phim /admin/movies
server/            tRPC API, gồm commentFeed.ts (bình luận real-time), movieCredits.ts
drizzle/           schema + migration
shared/            kiểu dùng chung
cpanel-comments/   dịch vụ bình luận PHP (tuỳ chọn, chỉ cần nếu không dùng Node)
package.json, tsconfig.json, vite.config.ts, drizzle.config.ts …
```

Không có `mobile-swiftui/` (app iOS không cần cho backend) và không có `node_modules`
(cPanel tự cài).

**Quan trọng:** gói đã kèm sẵn `dist/` nên trên hosting **không cần chạy `npm run build`**.
Đây cũng là cách tránh lỗi `Cannot find module @rollup/rollup-linux-x64-gnu` của `vite build`
trên máy chủ dùng chung.

## 2. Các bước

Đúng theo cấu hình bạn đang dùng: Application root `cinemora2`, URL
`https://cungcapicloud.id.vn`, startup file `dist/index.js`.

### Điền form "Setup Node.js App"

| Trường trong cPanel | Giá trị điền | Ghi chú |
| --- | --- | --- |
| **Node.js version** | `22` | Khớp môi trường ảo đang dùng: `/home/vfviehep/nodevenv/cinemora2/22`. Nếu máy chủ chỉ có 20 thì chọn 20, mã chạy được cả hai. |
| **Application mode** | `Production` | cPanel tự thêm `NODE_ENV=production` — đúng thứ server cần để phục vụ bản build. |
| **Application root** | `cinemora2` | Thư mục trong home: `/home/vfviehep/cinemora2`. Đây là nơi giải nén `Cinemora-Backend-Cpanel.zip`. |
| **Application URL** | `cungcapicloud.id.vn` | Chọn tên miền trong danh sách. Nếu dùng cả `www.cungcapicloud.id.vn` thì tạo thêm một mục nữa cùng Application root. |
| **Application startup file** | `dist/index.js` | Là tệp server đã build sẵn trong gói. Chỉ dùng `app.cjs` khi Passenger báo lỗi nạp ESM (xem dưới). |

Thứ tự làm: giải nén gói → `npm install --omit=dev --legacy-peer-deps` → **Restart**. Tệp khởi động
`dist/index.js` chỉ chạy được khi `node_modules` đã có; nếu thiếu, Passenger báo không tìm thấy tệp
hoặc lỗi thiếu module.

#### Nếu Passenger báo lỗi liên quan ESM

`package.json` của dự án khai báo `"type": "module"` và `dist/index.js` là mã ESM. Trên Node 22 việc nạp
này chạy bình thường; nếu máy chủ báo `Cannot use import statement outside a module`, tạo tệp `app.cjs`
ngay trong Application root:

```js
// Tệp khởi động cho Passenger trên cPanel: nạp máy chủ đã build.
import("./dist/index.js").catch((error) => {
  console.error(error);
  process.exit(1);
});
```

rồi đổi **Application startup file** thành `app.cjs` và Restart.

```bash
# 1. Giải nén đè vào thư mục ứng dụng
cd /home/vfviehep/cinemora2
unzip -o /duong/dan/Cinemora-Backend-Cpanel.zip

# 2. Chỉ cài dependency chạy thật (không cần dev, không cần build)
source /home/vfviehep/nodevenv/cinemora2/22/bin/activate
npm install --omit=dev --legacy-peer-deps
```

Sau đó vào cPanel Node.js Selector bấm **Restart**.

Nếu lần trước bạn đã xoá `dist` hoặc `node_modules` thì làm đúng ba bước trên là app chạy lại:
`dist/` nằm trong gói, chỉ còn thiếu dependency nên `npm install` là đủ.

### Nếu vẫn muốn build trên hosting

Chỉ khi bạn sửa mã nguồn ngay trên hosting mới cần build. Khi đó:

```bash
source /home/vfviehep/nodevenv/cinemora2/22/bin/activate
npm install --include=dev --legacy-peer-deps
npm run build
```

Gói này đã khai báo sẵn `@rollup/rollup-linux-x64-gnu` trong `optionalDependencies` nên npm
luôn cài đúng gói nhị phân cho Linux. Nếu vẫn gặp lỗi rollup, xoá hẳn rồi cài lại:

```bash
rm -rf node_modules package-lock.json
npm install --include=dev
npm run build
```

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

## 4. Sự cố thường gặp

### Truy cập tên miền chỉ thấy `Index of /`

Trang trắng có dòng `Proudly Served by LiteSpeed Web Server at <tên miền>` và bảng `Index of /` nghĩa là
tên miền vẫn đang phục vụ **thư mục web trống**, chưa được nối vào ứng dụng Node — không phải lỗi mã
nguồn. Nguyên nhân thường gặp là lúc tạo app trong *Setup Node.js App* chưa chọn **Application URL**,
hoặc chọn tên miền khác.

Cách sửa:

1. cPanel → **Setup Node.js App** → mở ứng dụng → sửa **Application URL** thành đúng tên miền
   (`cungcapicloud.id.vn`, thêm `www.cungcapicloud.id.vn` nếu dùng) → **Save**.
2. cPanel sẽ tự ghi khối Passenger vào `.htaccess` của tên miền. Kiểm tra:

   ```bash
   ls -la /home/USER/public_html
   grep -i passenger /home/USER/public_html/.htaccess
   ```

   Phải thấy khối có `PassengerAppRoot`, `PassengerBaseURI`, `PassengerNodejs`.
3. Bấm **Restart** ứng dụng, rồi mở lại tên miền.

Nếu `.htaccess` không có khối đó (một số máy chủ không tự ghi), dán tay vào `.htaccess` của thư mục web
tên miền, thay `USER` cho đúng:

```apache
# DO NOT REMOVE. CLOUDLINUX PASSENGER CONFIGURATION BEGIN
PassengerAppRoot "/home/USER/cinemora2"
PassengerBaseURI "/"
PassengerNodejs "/home/USER/nodevenv/cinemora2/22/bin/node"
PassengerAppLogFile "/home/USER/cinemora2/passenger.log"
# DO NOT REMOVE. CLOUDLINUX PASSENGER CONFIGURATION END
```

Lưu ý: tên miền phải thuộc **cùng tài khoản cPanel** đang chạy ứng dụng Node. Nếu tên miền nằm ở tài
khoản khác thì app phải được tạo trên tài khoản đó, hoặc phải trỏ lại DNS/thư mục web cho đúng.

### `npm error enoent ... nodevenv/cinemora2/22/lib/package.json`

```text
npm error code ENOENT
npm error path /home/USER/nodevenv/cinemora2/22/lib/package.json
```

npm đang chạy ở chế độ **global** của môi trường ảo (đường dẫn nằm trong `nodevenv/...`), nghĩa là
nó **không tìm thấy `package.json` trong thư mục ứng dụng**. Trên cPanel, `source .../bin/activate`
xuất biến `npm_config_prefix` trỏ vào môi trường ảo; khi thư mục ứng dụng chưa có `package.json`,
npm lấy luôn `prefix` đó làm gốc dự án và đi đọc `<venv>/lib/package.json` — tệp không tồn tại.

Kiểm tra trước:

```bash
cd /home/USER/cinemora2
ls -la
```

Phải thấy `package.json`, `dist/`, `client/`, `server/`, `drizzle/`. Nếu thư mục còn trống thì gói
backend chưa được giải nén vào đó — lúc này mọi cách chạy npm đều lỗi, kể cả `--prefix`, vì thật sự
không có `package.json` để đọc (`npm run build --prefix <thư mục>` sẽ báo thiếu `<thư mục>/package.json`).
Cách sửa là đưa mã nguồn vào trước:

```bash
cd /home/USER/cinemora2
unzip -o /duong/dan/Cinemora-Backend-Cpanel.zip
source /home/USER/nodevenv/cinemora2/22/bin/activate
npm install --omit=dev --legacy-peer-deps
```

Nếu `package.json` **đã có** mà vẫn báo lỗi, chỉ cần chỉ rõ thư mục cho npm (hoặc bỏ biến của môi
trường ảo trước khi chạy):

```bash
# Cách 1: chỉ định thư mục đích
npm install --prefix /home/USER/cinemora2 --include=dev --legacy-peer-deps
npm run build --prefix /home/USER/cinemora2

# Cách 2: bỏ biến prefix của môi trường ảo rồi chạy như thường
unset npm_config_prefix npm_config_global
npm install --include=dev --legacy-peer-deps && npm run build
```

Cách chắc ăn nhất là dùng nút **Run NPM Install** trong *Setup Node.js App*: cPanel tự chạy npm
đúng thư mục ứng dụng, không phụ thuộc biến của phiên terminal.

**Đừng xoá thư mục `dist/`** nếu không build lại: gói backend đã kèm bản dựng sẵn và đó chính là
tệp khởi động `dist/index.js`. Lệnh `rm -rf node_modules dist` chỉ nên dùng khi bạn thật sự muốn
build lại từ đầu; nếu đã xoá thì giải nén lại gói để lấy `dist/`.


### `export: '=43e64c…': not a valid identifier`

Dòng này xuất hiện mỗi lần chạy `npm` hoặc `node`, nghĩa là biến môi trường `TMDB_API_KEY` bị
khai báo sai trong cPanel (thiếu tên biến, chỉ có giá trị). Cách sửa:

1. cPanel → **Setup Node.js App** → ứng dụng `cinemora2` → **Environment Variables**.
2. Xoá biến đang bị lỗi, rồi thêm lại đúng hai ô: **Name** = `TMDB_API_KEY`,
   **Value** = khoá TMDB (chỉ dán khoá, không thêm `export`, không thêm dấu `=` hay dấu ngoặc).
3. Bấm **Save** rồi **Restart** ứng dụng.

Hoặc gọn hơn: tạo tệp `.env` trong thư mục ứng dụng với đúng một dòng:

```text
TMDB_API_KEY=43e64c7e89ca344b6e5b540fca083afb
```

Server đã nạp `.env` sẵn (`import "dotenv/config"`) nên không cần khai báo trong cPanel nữa.
Khi biến này thiếu, trang quản trị vẫn lấy được diễn viên vì nút *Lấy từ TMDB/IMDB* tự chuyển
sang gọi từ trình duyệt, nhưng nên sửa để máy chủ gọi được và nhanh hơn.

## 5. Đăng nhập quản trị

- Web chỉ còn **một** lối vào: hộp thoại đăng nhập (đã bỏ tab Đăng ký). Tài khoản người xem mới
  được tạo trong ứng dụng Cinemora.
- Tài khoản quản trị mặc định khi cơ sở dữ liệu còn trống: **`admin@gmail.cm`** / **`adminkkk11111@`**
  (đổi được bằng `ADMIN_EMAIL` / `ADMIN_PASSWORD`).
- **Biến môi trường được ưu tiên hơn giá trị mặc định.** Nếu trên hosting đã có `ADMIN_EMAIL` hoặc
  `ADMIN_PASSWORD` với giá trị cũ, tài khoản mặc định mới sẽ **không** được tạo — hãy sửa hoặc xoá
  hai biến đó rồi Restart.
- Quên mật khẩu quản trị: đặt `ADMIN_FORCE_PASSWORD=true` rồi Restart, máy chủ ghi lại mật khẩu admin
  đúng bằng `ADMIN_PASSWORD`; sau đó **xoá biến này** để không ghi đè mỗi lần Restart.
- Bảo mật đang bật sẵn: mật khẩu băm một chiều, cookie phiên `httpOnly` + `secure`, giới hạn 8 lần
  đăng nhập sai mỗi IP và 5 lần mỗi email trong 10 phút, thông báo lỗi không tiết lộ email có tồn tại
  hay không. Muốn tắt hẳn việc tạo tài khoản mới qua API thì đặt `ALLOW_REGISTRATION=false`.

## 5. Environment variables

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

## 6. Kiểm tra sau khi Restart

1. `https://cungcapicloud.id.vn/admin/movies` — chọn một phim, xem bình luận.
2. Mở app, gửi một bình luận ở cùng phim đó → trang quản trị phải nhảy bình luận lên
   **ngay** (không phải bấm làm mới).
3. Trên `/admin/accounts`, đặt nhãn cho một tài khoản (ví dụ `VIP`) rồi xem lại bình luận
   cũ của tài khoản đó trên app: tên phải đổi thành `Tên (VIP)` ngay.
4. Bấm **Ghim lên đầu** ở một bình luận → bình luận đó nằm đầu danh sách trên cả web và app.
5. Trong app: **Tài khoản & thiết bị** → chạm vào ảnh đại diện → chọn ảnh → ảnh phải hiện
   ở mọi bình luận của tài khoản đó.

## 7. Lưu ý

- Đừng xoá thư mục `uploads/` khi giải nén, poster truyền hình đang nằm trong đó.
- Không upload `node_modules`; nếu đã lỡ có thì xoá rồi `npm install` lại.
- Nếu `npm run build` báo thiếu dependency, chạy `npm install --include=dev` trước.
- `cpanel-comments/` chỉ là phương án dự phòng khi hosting không chạy được Node; dùng nó
  thì app sẽ tự lùi về làm mới bình luận mỗi 6 giây và không có ghim/nhãn quyền.
## 8. Xử lý sự cố

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

## Phim thủ công (tính năng mới)

Sau khi cập nhật mã lên hosting, bảng `custom_movies` và cột `qualities` của
`movie_source_episodes` **tự được tạo khi máy chủ khởi động** — không cần chạy SQL.

- Thêm phim: `/admin/movies` → nút **“+ Thêm phim thủ công”**.
- Tạo phim: `/admin/movies/custom/new`; sửa phim và thêm nguồn/tập/chất lượng: `/admin/movies/custom/<id>`.
- Ảnh lưu ở `uploads/movie-images/`, phụ đề ở `uploads/movie-subs/` — nhớ để hai thư mục này
  ghi được (quyền 755) và không xoá khi cập nhật.
- Nếu ảnh không hiện sau khi tải lên, kiểm tra máy chủ có phục vụ được `/uploads/...` không.

## Tìm diễn viên: khoá TMDB (không bắt buộc)

Trang **Quản lý phim → Thêm phim thủ công**, mục *Diễn viên & đạo diễn* có ô tìm diễn viên.

- **Không cần cấu hình gì** vẫn chạy: hệ thống dùng Wikidata miễn phí (tên, ảnh Wikimedia, mã IMDb).
- Muốn dùng TMDB (ảnh và dữ liệu đầy đủ hơn): lấy **API Key (v3)** hoặc **API Read Access Token (v4)**
  tại `themoviedb.org → Settings → API`, rồi khai báo trên hosting:

```
TMDB_API_KEY=<API Key v3 hoặc Access Token v4>
```

- **cPanel:** *Setup Node.js App* → **Environment Variables** → thêm biến `TMDB_API_KEY` → **Restart**.
- Hoặc tạo tệp `.env` trong thư mục ứng dụng với dòng trên rồi Restart.
- Khoá sai hoặc hết hạn mức thì hệ thống tự quay về Wikidata, không bị trắng kết quả.

## Ngày cập nhật phim thủ công bị nhảy dù không sửa gì

Bản mới đã tự sửa khi khởi động (bỏ thuộc tính `ON UPDATE CURRENT_TIMESTAMP` của cột `updatedAt`).
Sau khi upload và Restart, chỉ cần admin bấm lưu phim một lần là mốc ngày được ghi đúng.

Các phim đã bị nhảy ngày trước đó có thể chỉnh lại một lần bằng SQL (tuỳ chọn):

```sql
-- Đưa ngày cập nhật về mốc tạo phim cho những phim chưa từng được sửa lại.
-- Nếu admin đã sửa phim sau khi tạo, mốc này sẽ thấp hơn thực tế cho tới lần lưu kế tiếp.
UPDATE `custom_movies` SET `updatedAt` = `createdAt`;
```

Kiểm tra nhanh cột đã bỏ tự động cập nhật chưa:

```sql
SELECT EXTRA FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'custom_movies' AND COLUMN_NAME = 'updatedAt';
```

Kết quả không còn chữ `on update CURRENT_TIMESTAMP` là đạt.

