CREATE TABLE IF NOT EXISTS `qr_login_challenges` (
  `id` int AUTO_INCREMENT NOT NULL,
  `nonceHash` varchar(128) NOT NULL,
  `deviceId` varchar(160) NOT NULL,
  `deviceName` varchar(160) NOT NULL,
  `ipAddress` varchar(80),
  `location` varchar(160),
  `userAgent` text,
  `status` varchar(20) NOT NULL DEFAULT 'pending',
  `approvedUserId` int,
  `approvedAt` timestamp,
  `expiresAt` timestamp NOT NULL,
  `consumedAt` timestamp,
  `createdAt` timestamp NOT NULL DEFAULT (now()),
  CONSTRAINT `qr_login_challenges_nonceHash_unique` UNIQUE(`nonceHash`),
  INDEX `qr_login_challenges_status_expiry_idx` (`status`,`expiresAt`)
);
