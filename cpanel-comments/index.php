<?php
/**
 * Cinemora — dịch vụ bình luận cho hosting cPanel.
 *
 * Endpoint app gọi (giống hệt tRPC nên app không cần sửa gì):
 *   GET  /api/trpc/cinema.comments?input={"json":{"slug":"so-ly"}}
 *   POST /api/trpc/cinema.addComment      body: {"json":{"slug":"…","content":"…","parentId":null}}
 *   POST /api/trpc/cinema.deleteComment   body: {"json":{"slug":"…","id":"12"}}
 *   GET  /api/health                      kiểm tra dịch vụ đã chạy chưa
 */
declare(strict_types=1);

require __DIR__ . '/lib/Respond.php';
require __DIR__ . '/lib/Auth.php';
require __DIR__ . '/lib/Store.php';

$config = require __DIR__ . '/config.php';

// Biến cảnh báo thành exception để không trả về HTML lỗi giữa JSON.
set_error_handler(static function (int $severity, string $message, string $file, int $line): bool {
    throw new ErrorException($message, 0, $severity, $file, $line);
});

/**
 * App gửi tham số trong query (`input={"json":{…}}`) khi đọc, và trong body khi ghi.
 * Hỗ trợ cả hai, kể cả body dạng trần không có lớp "json".
 */
function cinemora_payload(): array
{
    $result = [];

    $raw = $_GET['input'] ?? null;
    if (is_string($raw) && $raw !== '') {
        $decoded = json_decode($raw, true);
        if (is_array($decoded)) {
            $inner = $decoded['json'] ?? $decoded;
            $result = is_array($inner) ? $inner : [];
        }
    }

    $body = file_get_contents('php://input');
    if (is_string($body) && $body !== '') {
        $decoded = json_decode($body, true);
        if (is_array($decoded)) {
            $inner = $decoded['json'] ?? $decoded;
            if (is_array($inner)) {
                $result = array_merge($result, $inner);
            }
        }
    }

    return $result;
}

$procedure = trim((string) ($_GET['procedure'] ?? ''));
$payload = cinemora_payload();

try {
    $store = new Store($config);

    switch ($procedure) {
        case 'health':
            unset($store); // chỉ cần kết nối và migrate thành công
            Respond::result([
                'ok' => true,
                'driver' => $config['driver'],
                'serverTime' => gmdate('c'),
                'sessionCookieSeen' => (($_SERVER['HTTP_COOKIE'] ?? '') !== ''),
                'phpVersion' => PHP_VERSION,
            ]);

        case 'cinema.comments':
            $slug = Store::slug((string) ($payload['slug'] ?? ''));
            $viewer = Auth::viewer($config, false);
            Respond::result(['items' => $store->list($slug, $viewer)]);

        case 'cinema.addComment':
            $viewer = Auth::viewer($config, true);
            $viewer['role'] = Auth::storedRole($config, $viewer);
            $slug = Store::slug((string) ($payload['slug'] ?? ''));
            $content = (string) ($payload['content'] ?? '');
            $parentId = isset($payload['parentId']) && $payload['parentId'] !== null
                ? (string) $payload['parentId']
                : null;
            $ip = $_SERVER['REMOTE_ADDR'] ?? null;
            Respond::result([
                'comment' => $store->add($viewer, $slug, $content, $parentId, is_string($ip) ? $ip : null),
            ]);

        case 'cinema.deleteComment':
            $viewer = Auth::viewer($config, true);
            $slug = Store::slug((string) ($payload['slug'] ?? ''));
            $store->delete($config, $viewer, $slug, (string) ($payload['id'] ?? ''));
            Respond::result(['success' => true]);

        default:
            Respond::notFound('No procedure found on path "' . $procedure . '"');
    }
} catch (Throwable $error) {
    if (!empty($config['debug'])) {
        Respond::fail('Lỗi máy chủ: ' . $error->getMessage());
    }
    Respond::fail('Máy chủ bình luận đang gặp sự cố. Vui lòng thử lại sau.');
}