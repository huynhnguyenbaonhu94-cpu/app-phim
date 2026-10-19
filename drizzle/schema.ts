import { boolean, int, index, mediumtext, mysqlEnum, mysqlTable, text, timestamp, uniqueIndex, varchar } from "drizzle-orm/mysql-core";

export const users = mysqlTable("users", {
  id: int("id").autoincrement().primaryKey(),
  openId: varchar("openId", { length: 64 }).notNull().unique(),
  name: text("name"),
  email: varchar("email", { length: 320 }),
  passwordHash: text("passwordHash"),
  loginMethod: varchar("loginMethod", { length: 64 }),
  role: mysqlEnum("role", ["user", "admin"]).default("user").notNull(),
  /** Ảnh đại diện dạng data URL base64 do app gửi lên. */
  avatar: mediumtext("avatar"),
  /** Nhãn tuỳ chỉnh do admin đặt, hiện cạnh tên khi bình luận, ví dụ "VIP". */
  badge: varchar("badge", { length: 40 }),
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

// Bình luận của người dùng cho từng phim. Trả lời được lồng một cấp: bản ghi có
// parentId trỏ về bình luận gốc.
export const movieComments = mysqlTable("movie_comments", {
  id: int("id").autoincrement().primaryKey(),
  movieSlug: varchar("movieSlug", { length: 140 }).notNull(),
  parentId: int("parentId"),
  userId: int("userId").notNull(),
  userName: varchar("userName", { length: 160 }).notNull(),
  userRole: varchar("userRole", { length: 20 }),
  content: text("content").notNull(),
  /** Thời điểm admin ghim; null là chưa ghim. */
  pinnedAt: timestamp("pinnedAt"),
  createdAt: timestamp("createdAt").defaultNow().notNull(),
}, (table) => ({
  slugCreatedIndex: index("movie_comments_slug_created_idx").on(table.movieSlug, table.createdAt),
  userCreatedIndex: index("movie_comments_user_created_idx").on(table.userId, table.createdAt),
}));
export const movieSources = mysqlTable("movie_sources", {
  id: int("id").autoincrement().primaryKey(),
  movieSlug: varchar("movieSlug", { length: 200 }).notNull(),
  name: varchar("name", { length: 120 }).notNull(),
  sortOrder: int("sortOrder").default(0).notNull(),
  createdAt: timestamp("createdAt").defaultNow().notNull(),
}, (table) => ({ slugIndex: index("movie_sources_slug_idx").on(table.movieSlug) }));

export const movieSourceEpisodes = mysqlTable("movie_source_episodes", {
  id: int("id").autoincrement().primaryKey(),
  sourceId: int("sourceId").notNull(),
  name: varchar("name", { length: 180 }).notNull(),
  streamUrl: text("streamUrl").notNull(),
  subtitleUrl: text("subtitleUrl"),
  subtitleVtt: mediumtext("subtitleVtt"),
  /** JSON [{ label, streamUrl, subtitleUrl }] — mỗi tập có thể có nhiều chất lượng, mỗi chất lượng phụ đề riêng. */
  qualities: text("qualities"),
  sortOrder: int("sortOrder").default(0).notNull(),
  createdAt: timestamp("createdAt").defaultNow().notNull(),
}, (table) => ({ sourceIndex: index("movie_source_episodes_source_idx").on(table.sourceId) }));

export type MovieSource = typeof movieSources.$inferSelect;
export type InsertMovieSource = typeof movieSources.$inferInsert;
export type MovieSourceEpisode = typeof movieSourceEpisodes.$inferSelect;
export type InsertMovieSourceEpisode = typeof movieSourceEpisodes.$inferInsert;

export type MovieComment = typeof movieComments.$inferSelect;
export type InsertMovieComment = typeof movieComments.$inferInsert;

/** Phim do admin thêm thủ công bằng link M3U8, không lấy từ API nguồn. */
export const customMovies = mysqlTable("custom_movies", {
  id: int("id").autoincrement().primaryKey(),
  slug: varchar("slug", { length: 200 }).notNull(),
  name: varchar("name", { length: 200 }).notNull(),
  /** Tên tiếng Anh, hiển thị ngay dưới tên phim trong trang chi tiết. */
  originName: varchar("originName", { length: 200 }),
  /** JSON mảng tên khác của phim. */
  alternativeNames: text("alternativeNames"),
  episodeCurrent: varchar("episodeCurrent", { length: 80 }),
  episodeTotal: int("episodeTotal"),
  createdDate: varchar("createdDate", { length: 40 }),
  updatedDate: varchar("updatedDate", { length: 40 }),
  tmdbId: varchar("tmdbId", { length: 40 }),
  imdbId: varchar("imdbId", { length: 40 }),
  /** JSON [{ name, slug }] */
  categories: text("categories"),
  countries: text("countries"),
  rating: varchar("rating", { length: 20 }),
  /** real: chỉ lượt xem thật; mixed: lượt xem thật + số ảo bên dưới. */
  viewsMode: varchar("viewsMode", { length: 12 }).default("real").notNull(),
  viewsBase: int("viewsBase").default(0).notNull(),
  viewCount: int("viewCount").default(0).notNull(),
  posterUrl: text("posterUrl"),
  thumbUrl: text("thumbUrl"),
  description: text("description"),
  quality: varchar("quality", { length: 40 }),
  year: int("year"),
  lang: varchar("lang", { length: 60 }),
  time: varchar("time", { length: 40 }),
  status: varchar("status", { length: 60 }),
  /** series | single */
  movieType: varchar("movieType", { length: 20 }).default("series").notNull(),
  /** JSON [{ name, role, image }] */
  actors: text("actors"),
  /** JSON mảng tên đạo diễn. */
  directors: text("directors"),
  isPublished: boolean("isPublished").default(true).notNull(),
  createdAt: timestamp("createdAt").defaultNow().notNull(),
  // Không dùng onUpdateNow(): ngày cập nhật chỉ đổi khi admin lưu phim, không đổi
  // khi hệ thống tăng lượt xem. Nơi ghi dữ liệu tự gán mốc thời gian.
  updatedAt: timestamp("updatedAt").defaultNow().notNull(),
}, (table) => ({ slugIndex: uniqueIndex("custom_movies_slug_idx").on(table.slug) }));

export type CustomMovie = typeof customMovies.$inferSelect;
export type InsertCustomMovie = typeof customMovies.$inferInsert;
