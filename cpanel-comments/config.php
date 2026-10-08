<?php
/**
 * Cấu hình dịch vụ bình luận Cinemora.
 *
 * Sửa file này sau khi upload lên hosting. Không cần cài gì thêm: PHP thuần,
 * không dùng composer, không cần Node.
 */
return [
    // 'sqlite' là dễ nhất: không cần tạo database, dữ liệu nằm trong data/comments.sqlite.
    // Đổi sang 'mysql' nếu bạn muốn dùng database có sẵn trong cPanel.
    'driver' => 'sqlite',

    'sqlite_path' => __DIR__ . '/data/comments.sqlite',

    'mysql' => [
        'host' => 'localhost',
        'name' => 'ten_database',
        'user' => 'ten_user',
        'pass' => 'mat_khau',
    ],

    // Máy chủ chính của app — dùng để kiểm tra phiên đăng nhập qua auth.me.
    // Giữ đúng như API_BASE_URL trong app.
    'auth_base_url' => 'https://cungcapicloud.id.vn',

    // Vai trò nào được coi là quản trị (để gắn huy hiệu xanh trong app).
    'admin_roles' => ['admin', 'quantri', 'moderator'],

    // Email quản trị dự phòng, dùng khi máy chủ chính chưa trả về vai trò.
    'admin_emails' => [],

    // Chống spam.
    'min_seconds_between' => 3,   // tối thiểu 3 giây giữa hai bình luận của cùng một người
    'max_per_day' => 60,          // tối đa 60 bình luận mỗi ngày cho mỗi tài khoản
    'max_length' => 2000,         // độ dài tối đa của một bình luận
    'max_list' => 500,            // số bình luận trả về nhiều nhất cho một phim

    // Đặt true khi cần xem lỗi chi tiết (nhớ trả về false sau khi kiểm tra xong).
    'debug' => false,
];