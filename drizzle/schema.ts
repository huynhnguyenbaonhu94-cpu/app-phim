import { boolean, int, index, mysqlEnum, mysqlTable, text, timestamp, uniqueIndex, varchar } from "drizzle-orm/mysql-core";

export const users = mysqlTable("users", {
  id: int("id").autoincrement().primaryKey(),
  openId: varchar("openId", { length: 64 }).notNull().unique(),
  name: text("name"),
  email: varchar("email", { length: 320 }),
  passwordHash: text("passwordHash"),
  loginMethod: varchar("loginMethod", { length: 64 }),
  role: mysqlEnum("role", ["user", "admin"]).default("user").notNull(),
  createdAt: timestamp("createdAt").defaultNow().notNull(),
  updatedAt: timestamp("updatedAt").defaultNow().onUpdateNow().notNull(),
  lastSignedIn: timestamp("lastSignedIn").defaultNow().notNull(),
}, (table) => ({
  emailUnique: uniqueIndex("users_email_unique").on(table.email),
}));

export const movieFavorites = mysqlTable("movie_favorites", {
  id: int("id").autoincrement().primaryKey(),
  userId: int("userId").notNull(),
  movieSlug: varchar("movieSlug", { length: 140 }).notNull(),
  movieName: varchar("movieName", { length: 255 }).notNull(),
  originName: varchar("originName", { length: 255 }),
  posterUrl: text("posterUrl"),
  year: int("year"),
  addedAt: timestamp("addedAt").defaultNow().notNull(),
}, (table) => ({
  userMovieUnique: uniqueIndex("movie_favorites_user_movie_unique").on(table.userId, table.movieSlug),
  userAddedIndex: index("movie_favorites_user_added_idx").on(table.userId, table.addedAt),
}));

export const movieWatchHistory = mysqlTable("movie_watch_history", {
  id: int("id").autoincrement().primaryKey(),
  userId: int("userId").notNull(),
  movieSlug: varchar("movieSlug", { length: 140 }).notNull(),
  movieName: varchar("movieName", { length: 255 }).notNull(),
  originName: varchar("originName", { length: 255 }),
  posterUrl: text("posterUrl"),
  year: int("year"),
  episodeSlug: varchar("episodeSlug", { length: 140 }),
  episodeName: varchar("episodeName", { length: 255 }),
  watchedSeconds: int("watchedSeconds").default(0).notNull(),
  durationSeconds: int("durationSeconds").default(0).notNull(),
  lastWatchedAt: timestamp("lastWatchedAt").defaultNow().notNull(),
}, (table) => ({
  userMovieEpisodeUnique: uniqueIndex("movie_history_user_movie_episode_unique").on(table.userId, table.movieSlug, table.episodeSlug),
  userWatchedIndex: index("movie_history_user_watched_idx").on(table.userId, table.lastWatchedAt),
}));

export const accountSessions = mysqlTable("account_sessions", {
  id: int("id").autoincrement().primaryKey(),
  userId: int("userId").notNull(),
  tokenHash: varchar("tokenHash", { length: 128 }).notNull().unique(),
  deviceId: varchar("deviceId", { length: 160 }).notNull(),
  deviceName: varchar("deviceName", { length: 160 }).notNull(),
  ipAddress: varchar("ipAddress", { length: 80 }),
  location: varchar("location", { length: 160 }),
  userAgent: text("userAgent"),
  createdAt: timestamp("createdAt").defaultNow().notNull(),
  lastSeenAt: timestamp("lastSeenAt").defaultNow().notNull(),
  revokedAt: timestamp("revokedAt"),
}, (table) => ({
  userActiveIndex: index("account_sessions_user_active_idx").on(table.userId, table.revokedAt),
  userDeviceIndex: index("account_sessions_user_device_idx").on(table.userId, table.deviceId),
  lastSeenIndex: index("account_sessions_last_seen_idx").on(table.lastSeenAt),
}));

export const qrLoginChallenges = mysqlTable("qr_login_challenges", {
  id: int("id").autoincrement().primaryKey(),
  nonceHash: varchar("nonceHash", { length: 128 }).notNull().unique(),
  deviceId: varchar("deviceId", { length: 160 }).notNull(),
  deviceName: varchar("deviceName", { length: 160 }).notNull(),
  ipAddress: varchar("ipAddress", { length: 80 }),
  location: varchar("location", { length: 160 }),
  userAgent: text("userAgent"),
  status: varchar("status", { length: 20 }).default("pending").notNull(),
  approvedUserId: int("approvedUserId"),
  approvedAt: timestamp("approvedAt"),
  expiresAt: timestamp("expiresAt").notNull(),
  consumedAt: timestamp("consumedAt"),
  createdAt: timestamp("createdAt").defaultNow().notNull(),
}, (table) => ({
  statusExpiryIndex: index("qr_login_challenges_status_expiry_idx").on(table.status, table.expiresAt),
}));

export const tvStreams = mysqlTable("tv_streams", {
  id: int("id").autoincrement().primaryKey(),
  name: varchar("name", { length: 120 }).notNull(),
  streamUrl: text("streamUrl").notNull(),
  audioUrl: text("audioUrl"),
  logoUrl: text("logoUrl"),
  posterUrl: text("posterUrl"),
  description: varchar("description", { length: 500 }),
  sortOrder: int("sortOrder").default(0).notNull(),
  isActive: boolean("isActive").default(true).notNull(),
  healthStatus: mysqlEnum("healthStatus", ["unknown", "online", "offline"]).default("unknown").notNull(),
  healthMessage: varchar("healthMessage", { length: 255 }),
  lastCheckedAt: timestamp("lastCheckedAt"),
  createdAt: timestamp("createdAt").defaultNow().notNull(),
  updatedAt: timestamp("updatedAt").defaultNow().onUpdateNow().notNull(),
}, (table) => ({
  activeOrderIndex: index("tv_streams_active_order_idx").on(table.isActive, table.sortOrder),
  }));

export const tvVideos = mysqlTable("tv_videos", {
  id: int("id").autoincrement().primaryKey(),
  name: varchar("name", { length: 180 }).notNull(),
  logoUrl: text("logoUrl"),
  description: varchar("description", { length: 1000 }),
  sortOrder: int("sortOrder").default(0).notNull(),
  isActive: boolean("isActive").default(true).notNull(),
  allowPip: boolean("allowPip").default(true).notNull(),
  isFeatured: boolean("isFeatured").default(false).notNull(),
  featuredEffect: varchar("featuredEffect", { length: 30 }).default("glow").notNull(),
  createdAt: timestamp("createdAt").defaultNow().notNull(),
  updatedAt: timestamp("updatedAt").defaultNow().onUpdateNow().notNull(),
}, (table) => ({ activeOrderIndex: index("tv_videos_active_order_idx").on(table.isActive, table.sortOrder) }));

export const tvVideoEpisodes = mysqlTable("tv_video_episodes", {
  id: int("id").autoincrement().primaryKey(),
  videoId: int("videoId").notNull(),
  episodeNumber: int("episodeNumber").notNull(),
  name: varchar("name", { length: 180 }).notNull(),
  subtitleUrl: text("subtitleUrl"),
  bilingualSubtitleUrl: text("bilingualSubtitleUrl"),
  createdAt: timestamp("createdAt").defaultNow().notNull(),
}, (table) => ({ videoOrderIndex: index("tv_video_episodes_video_order_idx").on(table.videoId, table.episodeNumber) }));

export const tvVideoQualities = mysqlTable("tv_video_qualities", {
  id: int("id").autoincrement().primaryKey(),
  episodeId: int("episodeId").notNull(),
  label: varchar("label", { length: 40 }).notNull(),
  streamUrl: text("streamUrl").notNull(),
  subtitleUrl: text("subtitleUrl"),
  bilingualSubtitleUrl: text("bilingualSubtitleUrl"),
  subtitleTracks: text("subtitleTracks"),
  healthStatus: varchar("healthStatus", { length: 20 }).default("unknown").notNull(),
  healthMessage: varchar("healthMessage", { length: 255 }),
  createdAt: timestamp("createdAt").defaultNow().notNull(),
}, (table) => ({ episodeIndex: index("tv_video_qualities_episode_idx").on(table.episodeId) }));

export const tvVideoSubtitles = mysqlTable("tv_video_subtitles", {
  id: int("id").autoincrement().primaryKey(),
  episodeId: int("episodeId").notNull(),
  language: varchar("language", { length: 40 }).notNull(),
  subtitleUrl: text("subtitleUrl").notNull(),
  isDefault: boolean("isDefault").default(false).notNull(),
  createdAt: timestamp("createdAt").defaultNow().notNull(),
}, (table) => ({ episodeIndex: index("tv_video_subtitles_episode_idx").on(table.episodeId) }));

export type User = typeof users.$inferSelect;
export type InsertUser = typeof users.$inferInsert;
export type MovieFavorite = typeof movieFavorites.$inferSelect;
export type MovieWatchHistory = typeof movieWatchHistory.$inferSelect;
export type AccountSession = typeof accountSessions.$inferSelect;
export type QrLoginChallenge = typeof qrLoginChallenges.$inferSelect;
export type TvStream = typeof tvStreams.$inferSelect;
export type InsertTvStream = typeof tvStreams.$inferInsert;
export type TvVideo = typeof tvVideos.$inferSelect;
export type TvVideoEpisode = typeof tvVideoEpisodes.$inferSelect;
export type TvVideoQuality = typeof tvVideoQualities.$inferSelect;
export type TvVideoSubtitle = typeof tvVideoSubtitles.$inferSelect;
