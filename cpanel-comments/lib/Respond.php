<?php
/**
 * Trả về đúng định dạng tRPC mà app đang đọc, nên app không cần biết phần bình
 * luận được chạy ở đâu.
 */
final class Respond
{
    public static function result($json): void
    {
        self::send(200, [
            'result' => [
                'data' => [
                    'json' => $json,
                ],
            ],
        ]);
    }

    /**
     * Lỗi nghiệp vụ trả về HTTP 200 kèm envelope lỗi — giống tRPC. Như vậy app
     * hiện đúng câu thông báo (quá nhanh, nội dung trống…) thay vì "lỗi máy chủ".
     */
    public static function fail(string $message): void
    {
        self::send(200, [
            'error' => [
                'json' => [
                    'message' => $message,
                    'code' => -32000,
                    'data' => ['code' => 'BAD_REQUEST'],
                ],
            ],
        ]);
    }

    /** Chưa đăng nhập: trả 401 để app xử lý như phiên hết hạn. */
    public static function unauthorized(string $message): void
    {
        self::send(401, [
            'error' => [
                'json' => [
                    'message' => $message,
                    'code' => -32001,
                    'data' => ['code' => 'UNAUTHORIZED'],
                ],
            ],
        ]);
    }

    /** Procedure không tồn tại — app coi 404 là "máy chủ chưa làm phần bình luận". */
    public static function notFound(string $message): void
    {
        self::send(404, [
            'error' => [
                'json' => [
                    'message' => $message,
                    'code' => -32004,
                    'data' => ['code' => 'NOT_FOUND'],
                ],
            ],
        ]);
    }

    private static function send(int $status, array $payload): void
    {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        header('Cache-Control: no-store');
        echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        exit;
    }
}