CREATE TABLE `movie_favorites` (
	`id` int AUTO_INCREMENT NOT NULL,
	`userId` int NOT NULL,
	`movieSlug` varchar(140) NOT NULL,
	`movieName` varchar(255) NOT NULL,
	`originName` varchar(255),
	`posterUrl` text,
	`year` int,
	`addedAt` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `movie_favorites_id` PRIMARY KEY(`id`),
	CONSTRAINT `movie_favorites_user_movie_unique` UNIQUE(`userId`,`movieSlug`)
);
--> statement-breakpoint
CREATE TABLE `movie_watch_history` (
	`id` int AUTO_INCREMENT NOT NULL,
	`userId` int NOT NULL,
	`movieSlug` varchar(140) NOT NULL,
	`movieName` varchar(255) NOT NULL,
	`originName` varchar(255),
	`posterUrl` text,
	`year` int,
	`episodeSlug` varchar(140),
	`episodeName` varchar(255),
	`watchedSeconds` int NOT NULL DEFAULT 0,
	`durationSeconds` int NOT NULL DEFAULT 0,
	`lastWatchedAt` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `movie_watch_history_id` PRIMARY KEY(`id`),
	CONSTRAINT `movie_history_user_movie_episode_unique` UNIQUE(`userId`,`movieSlug`,`episodeSlug`)
);
--> statement-breakpoint
CREATE INDEX `movie_favorites_user_added_idx` ON `movie_favorites` (`userId`,`addedAt`);--> statement-breakpoint
CREATE INDEX `movie_history_user_watched_idx` ON `movie_watch_history` (`userId`,`lastWatchedAt`);