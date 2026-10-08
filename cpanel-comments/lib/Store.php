<?php
/**
 * Lưu trữ bình luận. Mặc định dùng SQLite (không cần tạo database), có thể đổi
 * sang MySQL trong config.php.
 */
final class Store
{
    private PDO $pdo;
    private array $config;

    public function __construct(array $config)
    {
        $this->config = $config;
        $this->pdo = $this->connect();
        $this->migrate();
    }

    public function driverName(): string
    {
        return (string) ($this->config['driver'] ?? 'sqlite');
    }

    // MARK: - Kết nối

    private function isMySQL(): bool
    {
        return ($this->config['driver'] ?? 'sqlite') === 'mysql';
    }

    private function connect(): PDO
    {
        $options = [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ];

        if ($this->isMySQL()) {
            $db = $this->config['mysql'];
            $dsn = sprintf('mysql:host=%s;dbname=%s;charset=utf8mb4', $db['host'], $db['name']);
            return new PDO($dsn, (string) $db['user'], (string) $db['pass'], $options);
        }

        $path = (string) $this->config['sqlite_path'];
        $dir = dirname($path);
        if (!is_dir($dir)) {
            @mkdir($dir, 0755, true);
        }
        if (!is_dir($dir) || !is_writable($dir)) {
            Respond::fail('Thư mục data chưa ghi được. Hãy cấp quyền 755 (hoặc 775) cho thư mục data.');
        }

        $pdo = new PDO('sqlite:' . $path, null, null, $options);
        $pdo->exec('PRAGMA journal_mode = WAL');
        $pdo->exec('PRAGMA busy_timeout = 5000');
        return $pdo;
    }

    private function migrate(): void
    {
        $idColumn = $this->isMySQL()
            ? 'INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY'
            : 'INTEGER PRIMARY KEY AUTOINCREMENT';
        $suffix = $this->isMySQL() ? ' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4' : '';

        $this->pdo->exec(
            'CREATE TABLE IF NOT EXISTS comments (' .
            "id $idColumn, " .
            'movie_slug VARCHAR(190) NOT NULL, ' .
            'parent_id INT NULL, ' .
            'user_id VARCHAR(64) NOT NULL, ' .
            'user_name VARCHAR(120) NOT NULL, ' .
            'user_role VARCHAR(32) NULL, ' .
            'user_email VARCHAR(190) NULL, ' .
            'content TEXT NOT NULL, ' .
            'created_at VARCHAR(32) NOT NULL, ' .
            'ip VARCHAR(64) NULL' .
            ")$suffix"
        );

        try {
            $this->pdo->exec('CREATE INDEX idx_comments_slug ON comments (movie_slug, created_at)');
        } catch (Throwable $ignored) {
            // MySQL không có "IF NOT EXISTS" cho index — đã tồn tại là bình thường.
        }
    }

    // MARK: - Kiểm tra dữ liệu vào

    /** Đếm ký tự, không bắt buộc hosting phải có extension mbstring. */
    private static function textLength(string $value): int
    {
        if (function_exists('mb_strlen')) {
            return (int) mb_strlen($value, 'UTF-8');
        }
        // Đếm theo codepoint để ký tự tiếng Việt không bị tính thành nhiều ký tự.
        $count = preg_match_all('/./us', $value);
        return $count === false ? strlen($value) : (int) $count;
    }

    public static function slug(string $raw): string
    {
        $slug = trim($raw);
        if ($slug === '' || self::textLength($slug) > 190) {
            Respond::fail('Thiếu thông tin phim.');
        }
        if (!preg_match('/^[A-Za-z0-9._-]+$/', $slug)) {
            Respond::fail('Mã phim không hợp lệ.');
        }
        return $slug;
    }

    private function cleanContent(string $raw): string
    {
        $max = (int) $this->config['max_length'];
        $text = str_replace(["\r\n", "\r"], "\n", $raw);
        $text = preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u', '', $text) ?? $text;
        $text = preg_replace("/\n{4,}/u", "\n\n\n", $text) ?? $text;
        $text = trim($text);

        if ($text === '') {
            Respond::fail('Nội dung bình luận không được để trống.');
        }
        if (self::textLength($text) > $max) {
            Respond::fail('Bình luận quá dài, tối đa ' . $max . ' ký tự.');
        }
        return $text;
    }

    private function assertRateLimit(array $viewer): void
    {
        $minSeconds = (int) $this->config['min_seconds_between'];
        $statement = $this->pdo->prepare('SELECT created_at FROM comments WHERE user_id = ? ORDER BY id DESC LIMIT 1');
        $statement->execute([$viewer['id']]);
        $last = $statement->fetchColumn();
        if ($last !== false && $last !== null) {
            $lastStamp = strtotime((string) $last . ' UTC');
            if ($lastStamp !== false && time() - $lastStamp < $minSeconds) {
                Respond::fail('Bạn vừa gửi bình luận, vui lòng chờ vài giây rồi gửi tiếp.');
            }
        }

        $statement = $this->pdo->prepare('SELECT COUNT(*) FROM comments WHERE user_id = ? AND created_at >= ?');
        $statement->execute([$viewer['id'], gmdate('Y-m-d 00:00:00')]);
        if ((int) $statement->fetchColumn() >= (int) $this->config['max_per_day']) {
            Respond::fail('Hôm nay bạn đã gửi khá nhiều bình luận. Vui lòng quay lại sau.');
        }
    }

    // MARK: - Đọc

    public function list(string $slug, ?array $viewer): array
    {
        $limit = (int) $this->config['max_list'];
        $statement = $this->pdo->prepare(
            'SELECT * FROM comments WHERE movie_slug = ? ORDER BY id DESC LIMIT ' . $limit
        );
        $statement->execute([$slug]);
        $rows = $statement->fetchAll();

        // Lấy mới nhất trước để không mất bình luận khi phim quá đông, rồi đảo lại
        // cho app hiển thị theo thứ tự thời gian.
        $rows = array_reverse($rows);

        $items = [];
        foreach ($rows as $row) {
            $items[] = $this->toJson($row, $viewer);
        }
        return $items;
    }

    // MARK: - Ghi

    public function add(array $viewer, string $slug, string $rawContent, ?string $parentId, ?string $ip): array
    {
        $content = $this->cleanContent($rawContent);
        $this->assertRateLimit($viewer);

        $parent = null;
        if ($parentId !== null && trim($parentId) !== '') {
            $parent = (int) $parentId;
            if ($parent <= 0) {
                Respond::fail('Bình luận được trả lời không hợp lệ.');
            }
            $check = $this->pdo->prepare('SELECT id FROM comments WHERE id = ? AND movie_slug = ?');
            $check->execute([$parent, $slug]);
            if ($check->fetchColumn() === false) {
                Respond::fail('Bình luận gốc không còn tồn tại.');
            }
        }

        $createdAt = gmdate('Y-m-d H:i:s');
        $statement = $this->pdo->prepare(
            'INSERT INTO comments (movie_slug, parent_id, user_id, user_name, user_role, user_email, content, created_at, ip)' .
            ' VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'
        );
        $statement->execute([
            $slug,
            $parent,
            $viewer['id'],
            $viewer['name'],
            $viewer['role'],
            $viewer['email'],
            $content,
            $createdAt,
            $ip,
        ]);

        $id = (int) $this->pdo->lastInsertId();
        $row = $this->find($id);
        if ($row === null) {
            Respond::fail('Không lưu được bình luận, vui lòng thử lại.');
        }
        return $this->toJson($row, $viewer);
    }

    public function delete(array $config, array $viewer, string $slug, string $rawId): void
    {
        $id = (int) $rawId;
        if ($id <= 0) {
            Respond::fail('Bình luận không hợp lệ.');
        }

        $row = $this->find($id);
        if ($row === null || (string) $row['movie_slug'] !== $slug) {
            Respond::fail('Bình luận không còn tồn tại.');
        }

        $isOwner = (string) $row['user_id'] === (string) $viewer['id'];
        if (!$isOwner && !Auth::isAdmin($config, $viewer)) {
            Respond::fail('Bạn chỉ xoá được bình luận của mình.');
        }

        // Xoá cả các trả lời trực thuộc để không còn trả lời mồ côi.
        $statement = $this->pdo->prepare('DELETE FROM comments WHERE id = ? OR parent_id = ?');
        $statement->execute([$id, $id]);
    }

    private function find(int $id): ?array
    {
        $statement = $this->pdo->prepare('SELECT * FROM comments WHERE id = ? LIMIT 1');
        $statement->execute([$id]);
        $row = $statement->fetch();
        return is_array($row) ? $row : null;
    }

    // MARK: - Chuyển sang JSON cho app

    private function toJson(array $row, ?array $viewer): array
    {
        $stamp = strtotime((string) $row['created_at'] . ' UTC');
        return [
            'id' => (string) $row['id'],
            'parentId' => $row['parent_id'] === null ? null : (string) $row['parent_id'],
            'content' => (string) $row['content'],
            'createdAt' => $stamp === false ? gmdate('c') : gmdate('Y-m-d\TH:i:s\Z', $stamp),
            'userName' => (string) $row['user_name'],
            'userRole' => $row['user_role'] === null ? null : (string) $row['user_role'],
            'userId' => (string) $row['user_id'],
            'userEmail' => $row['user_email'] === null ? null : (string) $row['user_email'],
            'isMine' => $viewer !== null && (string) $viewer['id'] === (string) $row['user_id'],
        ];
    }
}
