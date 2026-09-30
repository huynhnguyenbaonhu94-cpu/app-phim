CREATE TABLE `tv_streams` (
	`id` int AUTO_INCREMENT NOT NULL,
	`name` varchar(120) NOT NULL,
	`streamUrl` text NOT NULL,
	`logoUrl` text,
	`posterUrl` text,
	`description` varchar(500),
	`sortOrder` int NOT NULL DEFAULT 0,
	`isActive` boolean NOT NULL DEFAULT true,
	`healthStatus` enum('unknown','online','offline') NOT NULL DEFAULT 'unknown',
	`healthMessage` varchar(255),
	`lastCheckedAt` timestamp,
	`createdAt` timestamp NOT NULL DEFAULT (now()),
	`updatedAt` timestamp NOT NULL DEFAULT (now()) ON UPDATE CURRENT_TIMESTAMP,
	CONSTRAINT `tv_streams_id` PRIMARY KEY(`id`)
);
--> statement-breakpoint
CREATE INDEX `tv_streams_active_order_idx` ON `tv_streams` (`isActive`,`sortOrder`);