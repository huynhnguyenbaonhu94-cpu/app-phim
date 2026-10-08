# Cinemora — dịch vụ bình luận cho cPanel

Đây là backend bình luận chạy bằng **PHP thuần**, upload lên hosting cPanel là chạy:
không cần Node, không cần composer, không cần tạo database (mặc định dùng SQLite).

Dịch vụ trả về **đúng định dạng tRPC** mà app đang đọc, nên app không phải sửa gì
ngoài việc trỏ tới tên miền của dịch vụ này.

---

## 1. Tạo chỗ chạy (khuyến nghị: tên miền phụ)

Trong cPanel:

1. **Domains → Create A New Domain** (hoặc **Subdomains**), tạo:
   `comments.cungcapicloud.id.vn`
2. Document Root: `public_html/comments` (cPanel tự tạo thư mục này).
3. Upload **toàn bộ nội dung thư mục `cpanel-comments`** vào document root đó, giữ
   nguyên cấu trúc:

```
public_html/comments/
├── .htaccess
├── index.php
├── config.php
├── lib/
│   ├── Auth.php
│   ├── Respond.php
│   └── Store.php
└── data/            ← phải ghi được (quyền 755, hoặc 775 nếu 755 không đủ)
```

> Nếu dùng File Manager để upload zip: nhớ bật **Show Hidden Files** để thấy `.htaccess`,
> và giải nén ngay trong document root.

4. Cấp quyền cho thư mục `data`: chuột phải → **Change Permissions** → `755`
   (một số hosting cần `775`).

## 2. Kiểm tra dịch vụ đã chạy

Mở trên trình duyệt:

```
https://comments.cungcapicloud.id.vn/api/health
```

Kết quả đúng:

```json
{"result":{"data":{"json":{"ok":true,"driver":"sqlite","serverTime":"…","sessionCookieSeen":false,"phpVersion":"8.x"}}}}
```

- `ok: true` → dịch vụ chạy và đã tạo xong bảng dữ liệu.
- Trang trắng, HTML lỗi, hoặc 404 → xem mục **Xử lý sự cố** ở cuối.

## 3. Cấu hình

Mở `config.php`, sửa những dòng cần thiết:

| Khoá | Ý nghĩa |
| --- | --- |
| `driver` | `sqlite` (mặc định) hoặc `mysql` |
| `auth_base_url` | Máy chủ chính của app, dùng để kiểm tra phiên đăng nhập — **giữ đúng như `API_BASE_URL`** trong app |
| `admin_roles` | Vai trò được coi là quản trị, mặc định `admin`, `quantri`, `moderator` |
| `admin_emails` | Email quản trị dự phòng, dùng khi máy chủ chính chưa trả về vai trò |
| `min_seconds_between`, `max_per_day`, `max_length` | Chống spam |
| `debug` | Đặt `true` khi cần xem lỗi chi tiết, **trả về `false` sau khi kiểm tra** |

Không cần cấu hình tài khoản người dùng ở đây: dịch vụ hỏi chính máy chủ của app
(`auth.me`) bằng cookie phiên do app chuyển tiếp, nên biết đúng người gửi và đúng
vai trò quản trị.

## 4. Nối app với dịch vụ

Trong project SwiftUI, sửa `project.yml`:

```yaml
    COMMENTS_API_BASE_URL: "https://comments.cungcapicloud.id.vn"
```

rồi build lại IPA. (Để trống khoá này thì app dùng chung máy chủ chính — lúc đó app
chuyển sang lưu bình luận trên thiết bị vì máy chủ chính chưa có procedure bình luận.)

Kiểm tra trong app: mở một phim → khối **Bình luận** không còn dòng
*"Máy chủ chưa bật bình luận…"*, và huy hiệu đỏ/tên thiết bị biến mất.

## 5. Tuỳ chọn: dùng MySQL

1. cPanel → **MySQL® Databases** → tạo database + user, cấp toàn quyền.
2. Trong `config.php`:

```php
'driver' => 'mysql',
'mysql' => [
    'host' => 'localhost',
    'name' => 'ten_database',
    'user' => 'ten_user',
    'pass' => 'mat_khau',
],
```

Bảng `comments` sẽ tự được tạo ở lần gọi đầu tiên.

## 6. Tuỳ chọn: đặt trong thư mục con của tên miền chính

Nếu bạn muốn `https://cungcapicloud.id.vn/comments`, hãy upload vào
`public_html/comments` và đặt `COMMENTS_API_BASE_URL` thành
`https://cungcapicloud.id.vn/comments`.

Lưu ý: nếu ứng dụng chính của bạn đang chiếm toàn bộ tên miền (Node/Next.js trên
Passenger), nó thường chặn luôn thư mục con. Khi đó hãy dùng tên miền phụ ở mục 1.

## 7. Xử lý sự cố

| Hiện tượng | Cách xử lý |
| --- | --- |
| `/api/health` trả 404 | Thiếu `.htaccess`, hoặc hosting tắt `mod_rewrite`. Bật **Show Hidden Files** và upload lại `.htaccess` |
| Trang trắng hoặc HTML lỗi | Đặt `'debug' => true` trong `config.php` rồi gọi lại để xem thông báo; đồng thời xem **Errors** trong cPanel |
| Báo "Thư mục data chưa ghi được" | Đổi quyền thư mục `data` sang `755` hoặc `775` |
| App vẫn hiện "lưu trên thiết bị" | `COMMENTS_API_BASE_URL` chưa đúng, hoặc chưa build lại app sau khi sửa `project.yml` |
| Gửi bình luận báo cần đăng nhập | `auth_base_url` trong `config.php` sai, hoặc phiên đăng nhập trên app đã hết hạn |
| Bình luận gửi được nhưng không thấy huy hiệu ADMIN | Tài khoản chưa có `role` là `admin` trên máy chủ chính — thêm email vào `admin_emails` trong `config.php` |

## 8. Bảo mật và sao lưu

- Thư mục `data` và `lib` đã bị chặn truy cập trực tiếp qua `.htaccess`; `config.php`
  và file `.sqlite` cũng bị chặn theo tên.
- Nên bật HTTPS (cPanel → SSL/TLS Status → Run AutoSSL) để cookie phiên không bị lộ.
- Giới hạn tần suất đã bật sẵn trong `config.php`; có thể siết thêm `min_seconds_between`.
- Sao lưu định kỳ: `data/comments.sqlite` (hoặc database MySQL).