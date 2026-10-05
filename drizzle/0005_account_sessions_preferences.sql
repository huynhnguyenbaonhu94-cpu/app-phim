CREATE TABLE IF NOT EXISTS `account_sessions` (
	`id` int AUTO_INCREMENT NOT NULL,
	`userId` int NOT NULL,
	`sessionId` varchar(64) NOT NULL,
	`deviceId` varchar(128) NOT NULL,
	`deviceName` varchar(160) NOT NULL,
	`deviceModel` varchar(120),
	`osVersion` varchar(80),
	`appVersion` varchar(80),
	`ipAddress` varchar(45),
	`createdAt` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
	`lastSeenAt` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
	`expiresAt` timestamp NOT NULL,
	`revokedAt` timestamp,
	`revokeReason` varchar(40),
	CONSTRAINT `account_sessions_id` PRIMARY KEY(`id`),
	CONSTRAINT `account_sessions_session_unique` UNIQUE(`sessionId`),
	KEY `account_sessions_user_active_idx` (`userId`,`revokedAt`,`expiresAt`),
	KEY `account_sessions_user_device_idx` (`userId`,`deviceId`),
	KEY `account_sessions_user_seen_idx` (`userId`,`lastSeenAt`),
	CONSTRAINT `account_sessions_user_fk` FOREIGN KEY (`userId`) REFERENCES `users`(`id`) ON DELETE CASCADE
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS `user_playback_preferences` (
	`userId` int NOT NULL,
	`preferences` text NOT NULL,
	`updatedAt` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
	CONSTRAINT `user_playback_preferences_userId` PRIMARY KEY(`userId`),
	KEY `user_playback_preferences_updated_idx` (`updatedAt`),
	CONSTRAINT `user_playback_preferences_user_fk` FOREIGN KEY (`userId`) REFERENCES `users`(`id`) ON DELETE CASCADE
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS `account_sync_tombstones` (
	`id` int AUTO_INCREMENT NOT NULL,
	`userId` int NOT NULL,
	`recordType` enum('favorite','history') NOT NULL,
	`keyHash` varchar(64) NOT NULL,
	`deletedAt` timestamp NOT NULL,
	`createdAt` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
	CONSTRAINT `account_sync_tombstones_id` PRIMARY KEY(`id`),
	CONSTRAINT `account_sync_tombstones_record_unique` UNIQUE(`userId`,`recordType`,`keyHash`),
	KEY `account_sync_tombstones_user_deleted_idx` (`userId`,`deletedAt`),
	CONSTRAINT `account_sync_tombstones_user_fk` FOREIGN KEY (`userId`) REFERENCES `users`(`id`) ON DELETE CASCADE
);