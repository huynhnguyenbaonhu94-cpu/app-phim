<?php
/**
 * Xác định người đang gọi bằng cách hỏi chính máy chủ chính của app
 * (`auth.me`) với cookie phiên được chuyển tiếp.
 *
 * Nhờ vậy dịch vụ bình luận không cần biết database người dùng, không cần đọc
 * bảng users, và vai trò quản trị luôn khớp với tài khoản thật.
 */
final class Auth
{
    public static function viewer(array $config, bool $required = false): ?array
    {
        $cookie = self::sessionCookie();
        if ($cookie === '') {
            if ($required) {
                Respond::unauthorized('Vui lòng đăng nhập để bình luận.');
            }
            return null;
        }

        $user = self::fetchUser($config, $cookie);
        if ($user === null) {
            if ($required) {
                Respond::unauthorized('Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.');
            }
            return null;
        }

        return [
            'id' => (string) $user['id'],
            'name' => self::displayName($user),
            'email' => isset($user['email']) && is_string($user['email']) ? $user['email'] : null,
            'role' => isset($user['role']) && is_string($user['role']) ? $user['role'] : null,
        ];
    }

    public static function isAdmin(array $config, ?array $viewer): bool
    {
        if ($viewer === null) {
            return false;
        }
        $role = strtolower(trim((string) ($viewer['role'] ?? '')));
        if ($role !== '' && in_array($role, array_map('strtolower', $config['admin_roles']), true)) {
            return true;
        }
        $email = strtolower(trim((string) ($viewer['email'] ?? '')));
        return $email !== '' && in_array($email, array_map('strtolower', $config['admin_emails']), true);
    }

    /** Vai trò lưu kèm bình luận, đã chuẩn hoá để app nhận ra quản trị viên. */
    public static function storedRole(array $config, ?array $viewer): ?string
    {
        if ($viewer === null) {
            return null;
        }
        if (self::isAdmin($config, $viewer)) {
            return 'admin';
        }
        $role = trim((string) ($viewer['role'] ?? ''));
        return $role === '' ? null : $role;
    }

    private static function displayName(array $user): string
    {
        foreach (['name', 'displayName', 'username'] as $key) {
            if (isset($user[$key]) && is_string($user[$key]) && trim($user[$key]) !== '') {
                return trim($user[$key]);
            }
        }
        if (isset($user['email']) && is_string($user['email']) && $user['email'] !== '') {
            return strstr($user['email'], '@', true) ?: $user['email'];
        }
        return 'Người xem';
    }

    /** Cookie phiên: app chuyển tiếp, hoặc trình duyệt tự gửi — cùng một đường. */
    private static function sessionCookie(): string
    {
        $raw = (string) ($_SERVER['HTTP_COOKIE'] ?? '');
        if ($raw === '') {
            return '';
        }
        $parts = [];
        foreach (explode(';', $raw) as $pair) {
            $pair = trim($pair);
            if ($pair !== '') {
                $parts[] = $pair;
            }
        }
        return implode('; ', $parts);
    }

    private static function fetchUser(array $config, string $cookie): ?array
    {
        $url = rtrim((string) $config['auth_base_url'], '/') . '/api/trpc/auth.me';

        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => ['Accept: application/json', 'Cookie: ' . $cookie],
            CURLOPT_TIMEOUT => 8,
            CURLOPT_FOLLOWLOCATION => false,
        ]);
        $body = curl_exec($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $error = curl_error($ch);
        curl_close($ch);

        if ($body === false || $error !== '' || $status < 200 || $status >= 300) {
            return null;
        }

        $json = json_decode((string) $body, true);
        if (!is_array($json)) {
            return null;
        }

        $payload = $json['result']['data']['json']
            ?? $json['result']['data']['data']
            ?? null;

        if (!is_array($payload)) {
            return null;
        }

        // auth.me có thể trả thẳng user, hoặc bọc trong { "value": user }.
        if (array_key_exists('value', $payload)) {
            $payload = $payload['value'];
        }

        if (!is_array($payload) || !isset($payload['id'])) {
            return null;
        }

        return $payload;
    }
}