CREATE TABLE IF NOT EXISTS `account_sessions` (
  `id` varchar(64) NOT NULL,
  `userId` int NOT NULL,
  `tokenHash` varchar(128) NOT NULL,
  `deviceId` varchar(160) NOT NULL,
  `deviceName` varchar(120) NOT NULL,
  `deviceModel` varchar(160) NULL,
  `ipAddress` varchar(64) NULL,
  `userAgent` text NULL,
  `lastSeenAt` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `revokedAt` timestamp NULL,
  `revokeReason` varchar(40) NULL,
  `createdAt` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `account_sessions_token_hash_idx` (`tokenHash`),
  KEY `account_sessions_user_device_idx` (`userId`, `deviceId`),
  KEY `account_sessions_user_active_idx` (`userId`, `revokedAt`)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `account_preferences` (
  `userId` int NOT NULL,
  `playbackDefaults` text NULL,
  `updatedAt` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`userId`)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
