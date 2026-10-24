CREATE TABLE IF NOT EXISTS `movie_requests` (
  `id` int AUTO_INCREMENT NOT NULL,
  `userId` int NULL,
  `requesterName` varchar(160) NULL,
  `requesterEmail` varchar(320) NULL,
  `title` varchar(255) NOT NULL,
  `link` varchar(500) NULL,
  `priority` varchar(20) NOT NULL DEFAULT 'Bình thường',
  `notes` text NULL,
  `posterUrl` text NULL,
  `status` varchar(20) NOT NULL DEFAULT 'received',
  `adminMessage` text NULL,
  `createdAt` timestamp NOT NULL DEFAULT (now()),
  `updatedAt` timestamp NOT NULL DEFAULT (now()) ON UPDATE CURRENT_TIMESTAMP,
  `statusUpdatedAt` timestamp NULL,
  CONSTRAINT `movie_requests_pk` PRIMARY KEY(`id`),
  INDEX `movie_requests_user_created_idx` (`userId`,`createdAt`),
  INDEX `movie_requests_status_created_idx` (`status`,`createdAt`)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
