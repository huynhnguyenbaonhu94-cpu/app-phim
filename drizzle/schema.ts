import { int, index, mysqlEnum, mysqlTable, text, timestamp, uniqueIndex, varchar } from "drizzle-orm/mysql-core";

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
  sourceName: varchar("sourceName", { length: 255 }),
  watchedSeconds: int("watchedSeconds").default(0).notNull(),
  durationSeconds: int("durationSeconds").default(0).notNull(),
  lastWatchedAt: timestamp("lastWatchedAt").defaultNow().notNull(),
}, (table) => ({
  userMovieEpisodeUnique: uniqueIndex("movie_history_user_movie_episode_unique").on(table.userId, table.movieSlug, table.episodeSlug),
  userWatchedIndex: index("movie_history_user_watched_idx").on(table.userId, table.lastWatchedAt),
}));

export type User = typeof users.$inferSelect;
export type InsertUser = typeof users.$inferInsert;
export type MovieFavorite = typeof movieFavorites.$inferSelect;
export type MovieWatchHistory = typeof movieWatchHistory.$inferSelect;
