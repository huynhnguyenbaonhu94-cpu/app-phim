ALTER TABLE `users`
  ADD COLUMN `hasSpecialPrivileges` tinyint(1) NOT NULL DEFAULT 0;

CREATE TABLE `special_chat_attachments` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `userId` int NOT NULL,
  `storageKey` varchar(500) NOT NULL UNIQUE,
  `originalFilename` varchar(180) NOT NULL,
  `mimeType` varchar(80) NOT NULL,
  `byteSize` int NOT NULL,
  `createdAt` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `special_chat_attachments_user_created_idx` (`userId`, `createdAt`)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE `special_chat_messages` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `userId` int NOT NULL,
  `sender` enum('user','admin') NOT NULL,
  `text` text NULL,
  `attachmentId` int NULL,
  `createdAt` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `special_chat_messages_user_created_idx` (`userId`, `createdAt`),
  INDEX `special_chat_messages_attachment_idx` (`attachmentId`)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
