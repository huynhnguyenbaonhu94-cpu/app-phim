CREATE TABLE IF NOT EXISTS `account_sessions` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `userId` int NOT NULL,
  `tokenHash` varchar(128) NOT NULL UNIQUE,
  `deviceId` varchar(160) NOT NULL,
  `deviceName` varchar(160) NOT NULL,
  `ipAddress` varchar(80) NULL,
  `location` varchar(160) NULL,
  `userAgent` text NULL,
  `createdAt` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `lastSeenAt` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `revokedAt` timestamp NULL,
  INDEX `account_sessions_user_active_idx` (`userId`, `revokedAt`),
  INDEX `account_sessions_user_device_idx` (`userId`, `deviceId`),
  INDEX `account_sessions_last_seen_idx` (`lastSeenAt`)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
