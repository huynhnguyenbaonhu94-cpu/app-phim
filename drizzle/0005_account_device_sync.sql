CREATE TABLE IF NOT EXISTS `auth_sessions` (
  `id` varchar(36) NOT NULL,
  `userId` int NOT NULL,
  `deviceName` varchar(120) NOT NULL,
  `deviceModel` varchar(120) NULL,
  `platform` varchar(40) NOT NULL,
  `ipAddress` varchar(64) NULL,
  `userAgent` varchar(500) NULL,
  `createdAt` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `lastSeenAt` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `revokedAt` timestamp NULL,
  `revokeReason` varchar(40) NULL,
  PRIMARY KEY (`id`),
  KEY `auth_sessions_user_active_idx` (`userId`, `revokedAt`),
  KEY `auth_sessions_last_seen_idx` (`lastSeenAt`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `account_preferences` (
  `userId` int NOT NULL,
  `preferences` json NOT NULL,
  `updatedAt` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`userId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
