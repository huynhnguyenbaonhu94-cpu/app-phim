# Biến môi trường Cinemora (backend trên cPanel)

Tài liệu này liệt kê **toàn bộ** biến môi trường mà mã nguồn đang đọc, phân rõ cái nào bắt buộc,
cái nào nên có, và cái nào là mã nền tảng cũ để trống cũng được.

## Cách thêm

1. **cPanel → Setup Node.js App → chọn ứng dụng Cinemora → Environment Variables → Add Variable**, thêm từng dòng rồi bấm **Restart**.
2. Hoặc tạo tệp **`.env`** ngay cạnh `package.json` (server tự đọc qua `dotenv/config`), nội dung như mục "Bản copy nhanh" bên dưới, rồi Restart.
3. Chỉ cần dùng **một** trong hai cách; nếu nhập ở UI cPanel thì không cần tệp `.env`.
4. Sau khi thêm hoặc sửa biến, **luôn Restart** ứng dụng Node để mã đọc lại giá trị.

---

## 1. Bắt buộc

| Biến | Ví dụ | Vì sao cần |
| --- | --- | --- |
| `DATABASE_URL` | `mysql://user:pass@localhost:3306/dbname` | Toàn bộ phim thủ công, nguồn/tập, bình luận, tài khoản, badge, lượt xem đều nằm trong MySQL. Thiếu biến này server không kết nối được cơ sở dữ liệu. Dùng đúng thông tin MySQL trong cPanel (host thường là `localhost`). |
| `NODE_ENV` | `production` | Quyết định server phục vụ bản build tĩnh (`dist/`) hay chạy chế độ dev. Trên hosting **phải** đặt `production`, nếu thiếu thì web sẽ lỗi vì server cố chạy Vite ở chế độ phát triển. |
| `JWT_SECRET` | chuỗi ngẫu nhiên ≥ 32 ký tự | Khoá ký cookie đăng nhập. Nếu bỏ trống, mã dùng khoá mặc định trong nguồn nên kém an toàn và mọi người có thể bị đăng xuất khi đổi. Tạo nhanh: `openssl rand -hex 32`. |
| `ADMIN_EMAIL` | `admin@tenmien.com` | Email tài khoản quản trị được tạo tự động khi cơ sở dữ liệu còn trống. |
| `ADMIN_PASSWORD` | mật khẩu riêng, ≥ 8 ký tự | Mật khẩu của tài khoản quản trị nói trên. Nếu không đặt, hệ thống dùng mật khẩu mặc định trong nguồn — nên đổi thành mật khẩu riêng. |
| `ADMIN_NAME` | `Cinemora Admin` | Tên hiển thị của tài khoản quản trị đó. |
| `ADMIN_FORCE_PASSWORD` | `true` (chỉ khi cần) | Đặt lại mật khẩu tài khoản quản trị về đúng giá trị `ADMIN_PASSWORD` ngay lần Restart kế tiếp. Dùng khi quên mật khẩu admin; xong thì xoá biến này đi để mật khẩu không bị ghi đè mỗi lần Restart. |
| `ALLOW_REGISTRATION` | `false` (tuỳ chọn) | Đặt `false` để khoá hoàn toàn việc tạo tài khoản mới qua API. Web đã bỏ phần đăng ký; biến này chỉ cần khi bạn muốn chặn cả ứng dụng tạo người dùng mới. |

> Lưu ý: ba biến `ADMIN_*` chỉ có tác dụng **tạo mới** khi tài khoản chưa tồn tại. Nếu tài khoản đã có
> trong cơ sở dữ liệu thì đổi biến không đổi được mật khẩu; hãy đổi trong web admin (mục tài khoản) hoặc
> xoá tài khoản đó rồi Restart.

---

## 2. Nên có

| Biến | Ví dụ | Vì sao nên đặt |
| --- | --- | --- |
| `PUBLIC_BASE_URL` | `https://cungcapicloud.id.vn` | Tên miền công khai của backend (không có dấu `/` ở cuối). Dùng để tạo link tuyệt đối cho ảnh phim thủ công, poster/thumbnail và phụ đề. Bỏ trống thì hệ thống dùng link tương đối — vẫn chạy, nhưng một số chỗ (chia sẻ link, ảnh trong bình luận) sẽ kém chính xác hơn. |
| `TMDB_API_KEY` | khoá TMDB v3 của bạn | Dùng cho tính năng tìm diễn viên & đạo diễn trong **Thêm phim thủ công**. Có thể dán **API Read Access Token (v4)** vào biến `TMDB_ACCESS_TOKEN` thay thế — mã sẽ tự dùng cái nào có. Bỏ trống cả hai thì hệ thống tự chuyển sang Wikidata (vẫn ra tên và ảnh, nhưng ít dữ liệu hơn). |
| `MOBILE_APP_ORIGINS` | `https://cungcapicloud.id.vn,capacitor://localhost,http://localhost,https://localhost` | Danh sách origin được phép gọi API (CORS). Mặc định đã có ba mục `capacitor://localhost`, `http://localhost`, `https://localhost`; chỉ cần thêm tên miền web của bạn nếu web nằm khác tên miền với backend. |
| `PORT` | để trống | Passenger trên cPanel tự cấp cổng qua biến này. Chỉ đặt khi hosting yêu cầu cổng riêng. Mã mặc định 3000 và tự tìm cổng trống nếu bị chiếm. |

---

## 3. Không cần đặt (mã nền tảng cũ, để trống không ảnh hưởng chức năng)

`VITE_APP_ID`, `OAUTH_SERVER_URL`, `OWNER_OPEN_ID`, `BUILT_IN_FORGE_API_URL`, `BUILT_IN_FORGE_API_KEY`,
`TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`, `VITE_OAUTH_PORTAL_URL`, `VITE_FRONTEND_FORGE_API_URL`,
`VITE_FRONTEND_FORGE_API_KEY`.

Đăng nhập, bình luận, quản trị phim, tải phim offline đều dùng hệ thống tài khoản riêng của Cinemora
(mật khẩu + cookie phiên), không phụ thuộc các biến trên.

---

## 4. Phía web (lúc build)

| Biến | Giá trị | Ghi chú |
| --- | --- | --- |
| `VITE_API_BASE_URL` | để trống (khuyến nghị) | Web gọi API cùng tên miền. Chỉ đặt khi web tách sang tên miền khác, ví dụ `https://api.tenmien.com`. |

Các biến `VITE_*` được **nhúng vào lúc build**, nên sau khi đổi phải chạy lại `npm run build` rồi Restart.

---

## 5. Phía app iOS

App **không dùng biến môi trường**. Nó đọc khoá `API_BASE_URL` trong `Info.plist`
(`mobile-swiftui/Info.plist`), mặc định là `https://cungcapicloud.id.vn`. Nếu đổi tên miền backend,
sửa khoá đó rồi build lại IPA. Build IPA trên Codemagic chỉ cần thông tin ký (certificate, provisioning
profile) do bạn cấu hình trong tài khoản Codemagic, không liên quan biến môi trường của hosting.

---

## 6. Bản copy nhanh (dán vào `.env` hoặc nhập từng dòng ở cPanel)

```dotenv
DATABASE_URL=mysql://user:password@localhost:3306/database
NODE_ENV=production
JWT_SECRET=thay-bang-chuoi-ngau-nhien-32-ky-tu
ADMIN_EMAIL=admin@gmail.cm
ADMIN_PASSWORD=adminkkk11111@
ADMIN_NAME=Cinemora Admin
PUBLIC_BASE_URL=https://cungcapicloud.id.vn
TMDB_API_KEY=
MOBILE_APP_ORIGINS=https://cungcapicloud.id.vn,capacitor://localhost,http://localhost,https://localhost
```

## 7. Kiểm tra sau khi thêm

1. Restart ứng dụng Node trong cPanel.
2. Mở `https://cungcapicloud.id.vn/` — trang chủ web phải hiện phim.
3. Vào web admin → **Phim thủ công** → dán một tên diễn viên để kiểm tra `TMDB_API_KEY`.
4. Mở app, đăng nhập, thử bình luận và tải một tập phim về máy.
