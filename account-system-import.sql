-- Cinemora account/session migration (additive; never drops existing data).
-- Compatible with MySQL/MariaDB used by typical cPanel hosting.
-- Run against vfviehep_appphim after taking the normal database backup.

-- Existing source expects this column but the original 0000 migration omitted it.
SET @has_password_hash := (
  SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'passwordHash'
);
SET @sql := IF(@has_password_hash = 0,
  'ALTER TABLE `users` ADD COLUMN `passwordHash` text NULL',
  'SELECT 1');
PREPARE cinemora_stmt FROM @sql;
EXECUTE cinemora_stmt;
DEALLOCATE PREPARE cinemora_stmt;

SET @has_server_name := (
  SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'movie_watch_history' AND COLUMN_NAME = 'serverName'
);
SET @sql := IF(@has_server_name = 0,
  'ALTER TABLE `movie_watch_history` ADD COLUMN `serverName` varchar(160) NULL',
  'SELECT 1');
PREPARE cinemora_stmt FROM @sql;
EXECUTE cinemora_stmt;
DEALLOCATE PREPARE cinemora_stmt;

SET @has_completed := (
  SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'movie_watch_history' AND COLUMN_NAME = 'isCompleted'
);
SET @sql := IF(@has_completed = 0,
  'ALTER TABLE `movie_watch_history` ADD COLUMN `isCompleted` tinyint(1) NOT NULL DEFAULT 0',
  'SELECT 1');
PREPARE cinemora_stmt FROM @sql;
EXECUTE cinemora_stmt;
DEALLOCATE PREPARE cinemora_stmt;

CREATE TABLE IF NOT EXISTS `account_sessions` (
  `id` int NOT NULL AUTO_INCREMENT,
  `userId` int NOT NULL,
  `sessionId` varchar(64) NOT NULL,
  `deviceId` varchar(128) NOT NULL,
  `deviceName` varchar(160) NOT NULL,
  `deviceModel` varchar(120) NULL,
  `osVersion` varchar(80) NULL,
  `appVersion` varchar(80) NULL,
  `ipAddress` varchar(45) NULL,
  `createdAt` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `lastSeenAt` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expiresAt` timestamp NOT NULL,
  `revokedAt` timestamp NULL,
  `revokeReason` varchar(40) NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `account_sessions_session_unique` (`sessionId`),
  KEY `account_sessions_user_active_idx` (`userId`, `revokedAt`, `expiresAt`),
  KEY `account_sessions_user_device_idx` (`userId`, `deviceId`),
  KEY `account_sessions_user_seen_idx` (`userId`, `lastSeenAt`),
  CONSTRAINT `account_sessions_user_fk` FOREIGN KEY (`userId`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `user_playback_preferences` (
  `userId` int NOT NULL,
  `preferences` text NOT NULL,
  `updatedAt` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`userId`),
  KEY `user_playback_preferences_updated_idx` (`updatedAt`),
  CONSTRAINT `user_playback_preferences_user_fk` FOREIGN KEY (`userId`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE IF NOT EXISTS `account_sync_tombstones` (
  `id` int NOT NULL AUTO_INCREMENT,
  `userId` int NOT NULL,
  `recordType` enum('favorite','history') NOT NULL,
  `keyHash` varchar(64) NOT NULL,
  `deletedAt` timestamp NOT NULL,
  `createdAt` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `account_sync_tombstones_record_unique` (`userId`, `recordType`, `keyHash`),
  KEY `account_sync_tombstones_user_deleted_idx` (`userId`, `deletedAt`),
  CONSTRAINT `account_sync_tombstones_user_fk` FOREIGN KEY (`userId`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
