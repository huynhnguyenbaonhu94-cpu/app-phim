import { and, desc, eq, gt, isNotNull, isNull, lt, or, sql } from "drizzle-orm";
import { drizzle } from "drizzle-orm/mysql2";
import { migrate } from "drizzle-orm/mysql2/migrator";
import { accountSessions, accountSyncTombstones, InsertUser, movieFavorites, movieWatchHistory, users, userPlaybackPreferences } from "../drizzle/schema";
import { ENV } from "./_core/env";
import { createHash, randomUUID } from "node:crypto";
import path from "node:path";

let _db: ReturnType<typeof drizzle> | null = null;
let initialization: Promise<void> | null = null;

export async function getDb() {
  if (!_db && process.env.DATABASE_URL) {
    try {
      _db = drizzle(process.env.DATABASE_URL);
    } catch (error) {
      console.warn("[Database] Failed to connect:", error);
      _db = null;
    }
  }
  return _db;
}

async function ensureDefaultAdmin(db: ReturnType<typeof drizzle>) {
  const email = (process.env.ADMIN_EMAIL || "admin@cungcapicloud.id.vn").trim().toLowerCase();
  const name = process.env.ADMIN_NAME || "Cinemora Admin";
  if (!email) throw new Error("ADMIN_EMAIL không hợp lệ.");
  const existing = await db.select({ id: users.id }).from(users).where(eq(users.email, email)).limit(1);
  if (existing.length > 0) return;
  const password = process.env.ADMIN_PASSWORD || (process.env.NODE_ENV === "development" ? "Cinemora@2026!" : "");
  if (!password) {
    console.warn("[Database] Skipping default admin bootstrap: configure ADMIN_PASSWORD before creating a new admin account.");
    return;
  }
  if (password.length < 12) throw new Error("ADMIN_PASSWORD phải có ít nhất 12 ký tự khi bootstrap admin.");
  const { hashPassword } = await import("./localAuth");
  await db.insert(users).values({
    openId: `local_admin_${randomUUID()}`,
    name,
    email,
    passwordHash: await hashPassword(password),
    loginMethod: "email",
    role: "admin",
  });
  console.log(`[Database] Created default admin account: ${email}`);
}

export async function ensureTvStreamsCompatibility(db: ReturnType<typeof drizzle>) {
  const [rows] = await db.execute(sql`SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_TYPE, CHARACTER_SET_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'tv_streams'`);
  const columnRows = ((rows as unknown) as Array<{ COLUMN_NAME?: string; DATA_TYPE?: string; IS_NULLABLE?: string; COLUMN_TYPE?: string; CHARACTER_SET_NAME?: string }>);
  const columnInfo = new Map(columnRows.map((row) => [row.COLUMN_NAME, row]));
  const columns = new Set(columnInfo.keys());
  if (columns.size === 0) return;
  if (columnRows.some((row) => row.CHARACTER_SET_NAME === "latin1")) {
    await db.execute(sql.raw("ALTER TABLE `tv_streams` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"));
    console.log("[Database] Converted tv_streams charset from latin1 to utf8mb4.");
  }
  const missing: Record<string, string> = {
    audioUrl: "ALTER TABLE `tv_streams` ADD COLUMN `audioUrl` text NULL",
    posterUrl: "ALTER TABLE `tv_streams` ADD COLUMN `posterUrl` text NULL",
    healthStatus: "ALTER TABLE `tv_streams` ADD COLUMN `healthStatus` enum('unknown','online','offline') NOT NULL DEFAULT 'unknown'",
    healthMessage: "ALTER TABLE `tv_streams` ADD COLUMN `healthMessage` varchar(255) NULL",
    lastCheckedAt: "ALTER TABLE `tv_streams` ADD COLUMN `lastCheckedAt` timestamp NULL",
  };
  for (const [column, statement] of Object.entries(missing)) {
    if (!columns.has(column)) {
      await db.execute(sql.raw(statement));
      console.log(`[Database] Added missing tv_streams column: ${column}`);
    }
  }
  const healthStatus = columnInfo.get("healthStatus");
  if (healthStatus && String(healthStatus.COLUMN_TYPE || "").toLowerCase().startsWith("enum(")) {
    await db.execute(sql.raw("ALTER TABLE `tv_streams` MODIFY COLUMN `healthStatus` varchar(20) NOT NULL DEFAULT 'unknown'"));
    console.log("[Database] Normalized tv_streams.healthStatus to varchar.");
  }
  const lastCheckedAt = columnInfo.get("lastCheckedAt");
  if (lastCheckedAt && String(lastCheckedAt.IS_NULLABLE).toUpperCase() !== "YES") {
    await db.execute(sql.raw("ALTER TABLE `tv_streams` MODIFY COLUMN `lastCheckedAt` timestamp NULL"));
    console.log("[Database] Normalized tv_streams.lastCheckedAt to nullable timestamp.");
  }
}

export async function ensureTvVideosCompatibility(db: ReturnType<typeof drizzle>) {
  await db.execute(sql.raw(`CREATE TABLE IF NOT EXISTS tv_videos (id int NOT NULL AUTO_INCREMENT PRIMARY KEY, name varchar(180) NOT NULL, logoUrl text NULL, description varchar(1000) NULL, sortOrder int NOT NULL DEFAULT 0, isActive tinyint(1) NOT NULL DEFAULT 1, allowPip tinyint(1) NOT NULL DEFAULT 1, isFeatured tinyint(1) NOT NULL DEFAULT 0, featuredEffect varchar(30) NOT NULL DEFAULT 'glow', createdAt timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP, updatedAt timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, INDEX tv_videos_active_order_idx (isActive, sortOrder)) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`));
  await db.execute(sql.raw(`CREATE TABLE IF NOT EXISTS tv_video_episodes (id int NOT NULL AUTO_INCREMENT PRIMARY KEY, videoId int NOT NULL, episodeNumber int NOT NULL, name varchar(180) NOT NULL, subtitleUrl text NULL, bilingualSubtitleUrl text NULL, createdAt timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP, INDEX tv_video_episodes_video_order_idx (videoId, episodeNumber)) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`));
  await db.execute(sql.raw(`CREATE TABLE IF NOT EXISTS tv_video_qualities (id int NOT NULL AUTO_INCREMENT PRIMARY KEY, episodeId int NOT NULL, label varchar(40) NOT NULL, streamUrl text NOT NULL, subtitleUrl text NULL, bilingualSubtitleUrl text NULL, subtitleTracks text NULL, healthStatus varchar(20) NOT NULL DEFAULT 'unknown', healthMessage varchar(255) NULL, createdAt timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP, INDEX tv_video_qualities_episode_idx (episodeId)) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`));
  await db.execute(sql.raw(`CREATE TABLE IF NOT EXISTS tv_video_subtitles (id int NOT NULL AUTO_INCREMENT PRIMARY KEY, episodeId int NOT NULL, language varchar(40) NOT NULL, subtitleUrl text NOT NULL, isDefault tinyint(1) NOT NULL DEFAULT 0, createdAt timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP, INDEX tv_video_subtitles_episode_idx (episodeId)) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`));
  for (const statement of [
    "ALTER TABLE `tv_videos` ADD COLUMN `allowPip` tinyint(1) NOT NULL DEFAULT 1",
    "ALTER TABLE `tv_videos` ADD COLUMN `isFeatured` tinyint(1) NOT NULL DEFAULT 0",
    "ALTER TABLE `tv_videos` ADD COLUMN `featuredEffect` varchar(30) NOT NULL DEFAULT 'glow'",
    "ALTER TABLE `tv_video_episodes` ADD COLUMN `subtitleUrl` text NULL",
    "ALTER TABLE `tv_video_episodes` ADD COLUMN `bilingualSubtitleUrl` text NULL",
    "ALTER TABLE `tv_video_qualities` ADD COLUMN `subtitleUrl` text NULL",
    "ALTER TABLE `tv_video_qualities` ADD COLUMN `bilingualSubtitleUrl` text NULL",
    "ALTER TABLE `tv_video_qualities` ADD COLUMN `subtitleTracks` text NULL",
  ]) { try { await db.execute(sql.raw(statement)); } catch { /* column already exists */ } }
}

function isAlreadyCreatedMigrationTable(error: unknown) {
  let current: unknown = error;
  for (let depth = 0; depth < 4 && current; depth++) {
    const value = current as { code?: string; errno?: number; message?: string; cause?: unknown };
    if (value.code === "ER_TABLE_EXISTS_ERROR" || value.errno === 1050 || /table .* already exists/i.test(value.message || "")) return true;
    current = value.cause;
  }
  return false;
}

export async function initializeDatabase() {
  if (initialization) return initialization;
  initialization = (async () => {
    const db = await getDb();
    if (!db) throw new Error("DATABASE_URL chưa được cấu hình.");
    try {
      await migrate(db, { migrationsFolder: path.resolve(process.cwd(), "drizzle") });
    } catch (error) {
      // Manual SQL import may have created an additive account table before the
      // Drizzle journal advances. Continue only for that recognized collision;
      // repair/assertion below must still verify every required schema contract.
      if (!isAlreadyCreatedMigrationTable(error)) throw error;
      console.warn("[Database] Found an already-created migration table; verifying the full compatible schema before startup.");
    }
    await ensureTvStreamsCompatibility(db);
    await ensureTvVideosCompatibility(db);
    await ensureAccountSchemaCompatibility(db);
    await ensureDefaultAdmin(db);
  })();
  try {
    await initialization;
  } catch (error) {
    initialization = null;
    throw error;
  }
}

export async function upsertUser(user: InsertUser): Promise<void> {
  if (!user.openId) throw new Error("User openId is required for upsert");
  const db = await getDb();
  if (!db) { console.warn("[Database] Cannot upsert user: database not available"); return; }
  const values: InsertUser = { openId: user.openId };
  const updateSet: Record<string, unknown> = {};
  const textFields = ["name", "email", "loginMethod"] as const;
  for (const field of textFields) {
    if (user[field] !== undefined) { values[field] = user[field] ?? null; updateSet[field] = user[field] ?? null; }
  }
  if (user.lastSignedIn !== undefined) { values.lastSignedIn = user.lastSignedIn; updateSet.lastSignedIn = user.lastSignedIn; }
  if (user.role !== undefined) { values.role = user.role; updateSet.role = user.role; }
  else if (user.openId === ENV.ownerOpenId) { values.role = "admin"; updateSet.role = "admin"; }
  values.lastSignedIn ??= new Date();
  if (Object.keys(updateSet).length === 0) updateSet.lastSignedIn = new Date();
  await db.insert(users).values(values).onDuplicateKeyUpdate({ set: updateSet });
}

export async function getUserByOpenId(openId: string) {
  const db = await getDb();
  if (!db) return undefined;
  const result = await db.select().from(users).where(eq(users.openId, openId)).limit(1);
  return result[0];
}

export async function getUserByEmail(email: string) {
  const db = await getDb();
  if (!db) return undefined;
  const result = await db.select().from(users).where(eq(users.email, email)).limit(1);
  return result[0];
}

export async function createLocalUser(input: { name: string; email: string; passwordHash: string }) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  const openId = `local_${randomUUID()}`;
  await db.insert(users).values({ openId, name: input.name, email: input.email, passwordHash: input.passwordHash, loginMethod: "email" });
  return getUserByOpenId(openId);
}

export async function listFavorites(userId: number) {
  const db = await getDb();
  if (!db) return [];
  return db.select().from(movieFavorites).where(eq(movieFavorites.userId, userId)).orderBy(desc(movieFavorites.addedAt)).limit(100);
}

export async function isFavorite(userId: number, movieSlug: string) {
  const db = await getDb();
  if (!db) return false;
  const rows = await db.select({ id: movieFavorites.id }).from(movieFavorites).where(and(eq(movieFavorites.userId, userId), eq(movieFavorites.movieSlug, movieSlug))).limit(1);
  return rows.length > 0;
}

function syncRecordKeyHash(value: string) {
  return createHash("sha256").update(value).digest("hex");
}

export async function addFavorite(input: { userId: number; movieSlug: string; movieName: string; originName?: string; posterUrl?: string | null; year?: number | null; addedAt?: Date }) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  const addedAt = input.addedAt ?? new Date();
  const keyHash = syncRecordKeyHash(input.movieSlug);
  return db.transaction(async (tx) => {
    await tx.execute(sql`SELECT id FROM users WHERE id = ${input.userId} FOR UPDATE`);
    const tombstones = await tx.select({ deletedAt: accountSyncTombstones.deletedAt }).from(accountSyncTombstones).where(and(
      eq(accountSyncTombstones.userId, input.userId), eq(accountSyncTombstones.recordType, "favorite"), eq(accountSyncTombstones.keyHash, keyHash),
    )).limit(1);
    if (tombstones[0] && tombstones[0].deletedAt >= addedAt) return true;
    if (tombstones[0]) await tx.delete(accountSyncTombstones).where(and(eq(accountSyncTombstones.userId, input.userId), eq(accountSyncTombstones.recordType, "favorite"), eq(accountSyncTombstones.keyHash, keyHash)));
    const updates = { movieName: input.movieName, originName: input.originName || null, posterUrl: input.posterUrl || null, year: input.year || null,
      addedAt: sql`GREATEST(addedAt, VALUES(addedAt))` };
    await tx.insert(movieFavorites).values({ ...input, addedAt, originName: input.originName || null, posterUrl: input.posterUrl || null, year: input.year || null }).onDuplicateKeyUpdate({ set: updates });
    return true;
  });
}

export async function removeFavorite(userId: number, movieSlug: string) {
  return removeFavoriteIfOlder(userId, movieSlug, new Date());
}

export async function removeFavoriteIfOlder(userId: number, movieSlug: string, deletedAt: Date) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  const keyHash = syncRecordKeyHash(movieSlug);
  return db.transaction(async (tx) => {
    await tx.execute(sql`SELECT id FROM users WHERE id = ${userId} FOR UPDATE`);
    const current = await tx.select({ addedAt: movieFavorites.addedAt }).from(movieFavorites).where(and(eq(movieFavorites.userId, userId), eq(movieFavorites.movieSlug, movieSlug))).limit(1);
    if (current[0] && current[0].addedAt >= deletedAt) {
      await tx.delete(accountSyncTombstones).where(and(eq(accountSyncTombstones.userId, userId), eq(accountSyncTombstones.recordType, "favorite"), eq(accountSyncTombstones.keyHash, keyHash)));
      return true;
    }
    await tx.insert(accountSyncTombstones).values({ userId, recordType: "favorite", keyHash, deletedAt }).onDuplicateKeyUpdate({ set: { deletedAt: sql`GREATEST(deletedAt, VALUES(deletedAt))` } });
    await tx.delete(movieFavorites).where(and(eq(movieFavorites.userId, userId), eq(movieFavorites.movieSlug, movieSlug), lt(movieFavorites.addedAt, deletedAt)));
    return true;
  });
}

export async function recordWatchHistory(input: { userId: number; movieSlug: string; movieName: string; originName?: string; posterUrl?: string | null; year?: number | null; episodeSlug?: string; episodeName?: string; serverName?: string | null; watchedSeconds?: number; durationSeconds?: number; isCompleted?: boolean; lastWatchedAt?: Date }) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  const safeEpisode = input.episodeSlug || "movie";
  const watchedAt = input.lastWatchedAt ?? new Date();
  const keyHash = syncRecordKeyHash(`${input.movieSlug}::${safeEpisode}`);
  return db.transaction(async (tx) => {
    await tx.execute(sql`SELECT id FROM users WHERE id = ${input.userId} FOR UPDATE`);
    const tombstones = await tx.select({ deletedAt: accountSyncTombstones.deletedAt }).from(accountSyncTombstones).where(and(
      eq(accountSyncTombstones.userId, input.userId), eq(accountSyncTombstones.recordType, "history"), eq(accountSyncTombstones.keyHash, keyHash),
    )).limit(1);
    if (tombstones[0] && tombstones[0].deletedAt >= watchedAt) return true;
    if (tombstones[0]) await tx.delete(accountSyncTombstones).where(and(eq(accountSyncTombstones.userId, input.userId), eq(accountSyncTombstones.recordType, "history"), eq(accountSyncTombstones.keyHash, keyHash)));
    await tx.insert(movieWatchHistory).values({
      ...input,
      originName: input.originName || null,
      posterUrl: input.posterUrl || null,
      year: input.year || null,
      episodeSlug: safeEpisode,
      episodeName: input.episodeName || "Phim",
      serverName: input.serverName || null,
      watchedSeconds: Math.max(0, Math.floor(input.watchedSeconds || 0)),
      durationSeconds: Math.max(0, Math.floor(input.durationSeconds || 0)),
      isCompleted: !!input.isCompleted,
      lastWatchedAt: watchedAt,
    }).onDuplicateKeyUpdate({
      set: {
        movieName: sql`IF(VALUES(lastWatchedAt) >= lastWatchedAt, VALUES(movieName), movieName)`,
        originName: sql`IF(VALUES(lastWatchedAt) >= lastWatchedAt, VALUES(originName), originName)`,
        posterUrl: sql`IF(VALUES(lastWatchedAt) >= lastWatchedAt, VALUES(posterUrl), posterUrl)`,
        year: sql`IF(VALUES(lastWatchedAt) >= lastWatchedAt, VALUES(year), year)`,
        episodeName: sql`IF(VALUES(lastWatchedAt) >= lastWatchedAt, VALUES(episodeName), episodeName)`,
        serverName: sql`IF(VALUES(lastWatchedAt) >= lastWatchedAt, VALUES(serverName), serverName)`,
        watchedSeconds: sql`IF(VALUES(lastWatchedAt) >= lastWatchedAt, VALUES(watchedSeconds), watchedSeconds)`,
        durationSeconds: sql`IF(VALUES(lastWatchedAt) >= lastWatchedAt, VALUES(durationSeconds), durationSeconds)`,
        isCompleted: sql`IF(VALUES(lastWatchedAt) >= lastWatchedAt, VALUES(isCompleted), isCompleted)`,
        lastWatchedAt: sql`GREATEST(lastWatchedAt, VALUES(lastWatchedAt))`,
      },
    });
    return true;
  });
}

export async function listWatchHistory(userId: number) {
  const db = await getDb();
  if (!db) return [];
  return db.select().from(movieWatchHistory).where(eq(movieWatchHistory.userId, userId)).orderBy(desc(movieWatchHistory.lastWatchedAt)).limit(100);
}

export async function removeWatchHistory(userId: number, movieSlug: string, episodeSlug: string) {
  return removeWatchHistoryIfOlder(userId, movieSlug, episodeSlug, new Date());
}

export async function removeWatchHistoryIfOlder(userId: number, movieSlug: string, episodeSlug: string, deletedAt: Date) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  const keyHash = syncRecordKeyHash(`${movieSlug}::${episodeSlug || "movie"}`);
  return db.transaction(async (tx) => {
    await tx.execute(sql`SELECT id FROM users WHERE id = ${userId} FOR UPDATE`);
    const current = await tx.select({ lastWatchedAt: movieWatchHistory.lastWatchedAt }).from(movieWatchHistory).where(and(
      eq(movieWatchHistory.userId, userId), eq(movieWatchHistory.movieSlug, movieSlug), eq(movieWatchHistory.episodeSlug, episodeSlug || "movie"),
    )).limit(1);
    if (current[0] && current[0].lastWatchedAt >= deletedAt) {
      await tx.delete(accountSyncTombstones).where(and(eq(accountSyncTombstones.userId, userId), eq(accountSyncTombstones.recordType, "history"), eq(accountSyncTombstones.keyHash, keyHash)));
      return true;
    }
    await tx.insert(accountSyncTombstones).values({ userId, recordType: "history", keyHash, deletedAt }).onDuplicateKeyUpdate({ set: { deletedAt: sql`GREATEST(deletedAt, VALUES(deletedAt))` } });
    await tx.delete(movieWatchHistory).where(and(
      eq(movieWatchHistory.userId, userId), eq(movieWatchHistory.movieSlug, movieSlug),
      eq(movieWatchHistory.episodeSlug, episodeSlug || "movie"), lt(movieWatchHistory.lastWatchedAt, deletedAt),
    ));
    return true;
  });
}

/** Safe additive repair for databases provisioned before account sessions were added. */
export async function ensureAccountSchemaCompatibility(db: ReturnType<typeof drizzle>) {
  const [rows] = await db.execute(sql`SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users'`);
  const columns = new Set(((rows as unknown) as Array<{ COLUMN_NAME?: string }>).map((row) => row.COLUMN_NAME));
  if (!columns.has("passwordHash")) {
    await db.execute(sql.raw("ALTER TABLE `users` ADD COLUMN `passwordHash` text NULL"));
    console.log("[Database] Added missing users.passwordHash column.");
  }
  const [historyRows] = await db.execute(sql`SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'movie_watch_history'`);
  const historyColumns = new Set(((historyRows as unknown) as Array<{ COLUMN_NAME?: string }>).map((row) => row.COLUMN_NAME));
  if (!historyColumns.size) throw new Error("Database table movie_watch_history is missing; account data cannot be migrated safely.");
  for (const [column, definition] of Object.entries({ serverName: "varchar(160) NULL", isCompleted: "tinyint(1) NOT NULL DEFAULT 0" })) {
    if (historyColumns.size && !historyColumns.has(column)) {
      await db.execute(sql.raw(`ALTER TABLE \`movie_watch_history\` ADD COLUMN \`${column}\` ${definition}`));
      console.log(`[Database] Added missing movie_watch_history.${column} column.`);
    }
  }
  await db.execute(sql.raw(`CREATE TABLE IF NOT EXISTS account_sessions (
    id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
    userId int NOT NULL,
    sessionId varchar(64) NOT NULL,
    deviceId varchar(128) NOT NULL,
    deviceName varchar(160) NOT NULL,
    deviceModel varchar(120) NULL,
    osVersion varchar(80) NULL,
    appVersion varchar(80) NULL,
    ipAddress varchar(45) NULL,
    createdAt timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    lastSeenAt timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expiresAt timestamp NOT NULL,
    revokedAt timestamp NULL,
    revokeReason varchar(40) NULL,
    UNIQUE KEY account_sessions_session_unique (sessionId),
    KEY account_sessions_user_active_idx (userId, revokedAt, expiresAt),
    KEY account_sessions_user_device_idx (userId, deviceId),
    KEY account_sessions_user_seen_idx (userId, lastSeenAt),
    CONSTRAINT account_sessions_user_fk FOREIGN KEY (userId) REFERENCES users(id) ON DELETE CASCADE
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`));
  await db.execute(sql.raw(`CREATE TABLE IF NOT EXISTS user_playback_preferences (
    userId int NOT NULL PRIMARY KEY,
    preferences text NOT NULL,
    updatedAt timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY user_playback_preferences_updated_idx (updatedAt),
    CONSTRAINT user_playback_preferences_user_fk FOREIGN KEY (userId) REFERENCES users(id) ON DELETE CASCADE
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`));
  await db.execute(sql.raw(`CREATE TABLE IF NOT EXISTS account_sync_tombstones (
    id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
    userId int NOT NULL,
    recordType enum('favorite','history') NOT NULL,
    keyHash varchar(64) NOT NULL,
    deletedAt timestamp NOT NULL,
    createdAt timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY account_sync_tombstones_record_unique (userId, recordType, keyHash),
    KEY account_sync_tombstones_user_deleted_idx (userId, deletedAt),
    CONSTRAINT account_sync_tombstones_user_fk FOREIGN KEY (userId) REFERENCES users(id) ON DELETE CASCADE
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`));

  const requirements: Record<string, { columns: string[]; indexes: string[]; foreignKeys: string[] }> = {
    users: {
      columns: ["id", "openId", "name", "email", "passwordHash", "loginMethod", "role", "createdAt", "updatedAt", "lastSignedIn"],
      indexes: ["PRIMARY", "users_openId_unique", "users_email_unique"], foreignKeys: [],
    },
    movie_favorites: {
      columns: ["id", "userId", "movieSlug", "movieName", "originName", "posterUrl", "year", "addedAt"],
      indexes: ["PRIMARY", "movie_favorites_user_movie_unique", "movie_favorites_user_added_idx"], foreignKeys: [],
    },
    movie_watch_history: {
      columns: ["id", "userId", "movieSlug", "movieName", "originName", "posterUrl", "year", "episodeSlug", "episodeName", "serverName", "watchedSeconds", "durationSeconds", "isCompleted", "lastWatchedAt"],
      indexes: ["PRIMARY", "movie_history_user_movie_episode_unique", "movie_history_user_watched_idx"], foreignKeys: [],
    },
    account_sessions: {
      columns: ["id", "userId", "sessionId", "deviceId", "deviceName", "deviceModel", "osVersion", "appVersion", "ipAddress", "createdAt", "lastSeenAt", "expiresAt", "revokedAt", "revokeReason"],
      indexes: ["PRIMARY", "account_sessions_session_unique", "account_sessions_user_active_idx", "account_sessions_user_device_idx", "account_sessions_user_seen_idx"],
      foreignKeys: ["account_sessions_user_fk"],
    },
    user_playback_preferences: {
      columns: ["userId", "preferences", "updatedAt"],
      indexes: ["PRIMARY", "user_playback_preferences_updated_idx"],
      foreignKeys: ["user_playback_preferences_user_fk"],
    },
    account_sync_tombstones: {
      columns: ["id", "userId", "recordType", "keyHash", "deletedAt", "createdAt"],
      indexes: ["PRIMARY", "account_sync_tombstones_record_unique", "account_sync_tombstones_user_deleted_idx"],
      foreignKeys: ["account_sync_tombstones_user_fk"],
    },
  };
  for (const [table, required] of Object.entries(requirements)) {
    const [columnRows] = await db.execute(sql`SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ${table}`);
    const actualColumns = new Set(((columnRows as unknown) as Array<{ COLUMN_NAME?: string }>).map((row) => row.COLUMN_NAME));
    const [indexRows] = await db.execute(sql`SELECT DISTINCT INDEX_NAME FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ${table}`);
    const actualIndexes = new Set(((indexRows as unknown) as Array<{ INDEX_NAME?: string }>).map((row) => row.INDEX_NAME));
    const [foreignKeyRows] = await db.execute(sql`SELECT CONSTRAINT_NAME FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ${table} AND REFERENCED_TABLE_NAME IS NOT NULL`);
    const actualForeignKeys = new Set(((foreignKeyRows as unknown) as Array<{ CONSTRAINT_NAME?: string }>).map((row) => row.CONSTRAINT_NAME));
    const missing = [
      ...required.columns.filter((name) => !actualColumns.has(name)).map((name) => `column ${name}`),
      ...required.indexes.filter((name) => !actualIndexes.has(name)).map((name) => `index ${name}`),
      ...required.foreignKeys.filter((name) => !actualForeignKeys.has(name)).map((name) => `foreign key ${name}`),
    ];
    if (missing.length) throw new Error(`Database table ${table} is incomplete; missing ${missing.join(", ")}. Re-apply the account migration before starting Cinemora.`);
  }
}

export class DeviceLimitError extends Error {
  constructor() { super("Tài khoản đã đăng nhập đủ 5 thiết bị. Hãy kết thúc một phiên cũ rồi thử lại."); this.name = "DeviceLimitError"; }
}

export async function createDeviceSession(input: {
  userId: number; sessionId: string; deviceId: string; deviceName: string;
  deviceModel?: string | null; osVersion?: string | null; appVersion?: string | null;
  ipAddress?: string | null; expiresAt: Date; reuseExistingDeviceSession?: boolean;
}) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  return db.transaction(async (tx) => {
    // Lock the owner row so two simultaneous first-time logins cannot both claim slot #5.
    await tx.execute(sql`SELECT id FROM users WHERE id = ${input.userId} FOR UPDATE`);
    const now = new Date();
    const retentionCutoff = new Date(now.getTime() - 90 * 24 * 60 * 60_000);
    await tx.delete(accountSessions).where(and(eq(accountSessions.userId, input.userId), or(
      lt(accountSessions.expiresAt, retentionCutoff),
      and(isNotNull(accountSessions.revokedAt), lt(accountSessions.revokedAt, retentionCutoff)),
    )));
    await tx.update(accountSessions).set({ revokedAt: now, revokeReason: "expired" })
      .where(and(eq(accountSessions.userId, input.userId), isNull(accountSessions.revokedAt), lt(accountSessions.expiresAt, now)));
    if (input.reuseExistingDeviceSession) {
      const existing = await tx.select({ sessionId: accountSessions.sessionId, expiresAt: accountSessions.expiresAt }).from(accountSessions)
        .where(and(eq(accountSessions.userId, input.userId), eq(accountSessions.deviceId, input.deviceId), isNull(accountSessions.revokedAt), gt(accountSessions.expiresAt, now))).limit(1);
      if (existing[0]) {
        await tx.update(accountSessions).set({ lastSeenAt: now }).where(eq(accountSessions.sessionId, existing[0].sessionId));
        return { sessionId: existing[0].sessionId, expiresAt: existing[0].expiresAt };
      }
    }
    // Re-login from the same stable device replaces its old session rather than consuming another slot.
    await tx.update(accountSessions).set({ revokedAt: now, revokeReason: "replaced" })
      .where(and(eq(accountSessions.userId, input.userId), eq(accountSessions.deviceId, input.deviceId), isNull(accountSessions.revokedAt)));
    const active = await tx.select({ id: accountSessions.id }).from(accountSessions)
      .where(and(eq(accountSessions.userId, input.userId), isNull(accountSessions.revokedAt), gt(accountSessions.expiresAt, now)));
    if (active.length >= 5) throw new DeviceLimitError();
    const { reuseExistingDeviceSession: _reuse, ...sessionData } = input;
    await tx.insert(accountSessions).values({ ...sessionData, lastSeenAt: now });
    return { sessionId: input.sessionId, expiresAt: input.expiresAt };
  });
}

export async function getActiveDeviceSession(sessionId: string, userId: number) {
  const db = await getDb();
  if (!db) return undefined;
  const now = new Date();
  const rows = await db.select().from(accountSessions).where(and(
    eq(accountSessions.sessionId, sessionId), eq(accountSessions.userId, userId),
    isNull(accountSessions.revokedAt), gt(accountSessions.expiresAt, now),
  )).limit(1);
  return rows[0];
}

export async function touchDeviceSession(sessionId: string, userId: number) {
  const db = await getDb();
  if (!db) return false;
  await db.update(accountSessions).set({ lastSeenAt: new Date() }).where(and(
    eq(accountSessions.sessionId, sessionId), eq(accountSessions.userId, userId),
    isNull(accountSessions.revokedAt), gt(accountSessions.expiresAt, new Date()),
  ));
  return !!(await getActiveDeviceSession(sessionId, userId));
}

export async function listDeviceSessions(userId: number) {
  const db = await getDb();
  if (!db) return [];
  return db.select().from(accountSessions).where(and(
    eq(accountSessions.userId, userId), isNull(accountSessions.revokedAt), gt(accountSessions.expiresAt, new Date()),
  )).orderBy(desc(accountSessions.lastSeenAt));
}

export async function revokeDeviceSession(userId: number, sessionId: string, reason = "user_kick") {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  const result = await db.update(accountSessions).set({ revokedAt: new Date(), revokeReason: reason })
    .where(and(eq(accountSessions.userId, userId), eq(accountSessions.sessionId, sessionId), isNull(accountSessions.revokedAt)));
  return result[0].affectedRows > 0;
}

export async function revokeAllDeviceSessions(userId: number, reason = "logout_all") {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  const result = await db.update(accountSessions).set({ revokedAt: new Date(), revokeReason: reason })
    .where(and(eq(accountSessions.userId, userId), isNull(accountSessions.revokedAt)));
  return Number(result[0].affectedRows || 0);
}

export async function updatePasswordHash(userId: number, passwordHash: string) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  await db.update(users).set({ passwordHash, updatedAt: new Date() }).where(eq(users.id, userId));
}

export async function getPlaybackPreferences(userId: number) {
  const db = await getDb();
  if (!db) return null;
  const rows = await db.select().from(userPlaybackPreferences).where(eq(userPlaybackPreferences.userId, userId)).limit(1);
  const row = rows[0];
  if (!row) return null;
  try { return { preferences: JSON.parse(row.preferences) as Record<string, unknown>, updatedAt: row.updatedAt }; }
  catch { return null; }
}

export async function savePlaybackPreferences(userId: number, preferences: Record<string, unknown>, updatedAt = new Date()) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  await db.insert(userPlaybackPreferences).values({ userId, preferences: JSON.stringify(preferences), updatedAt })
    .onDuplicateKeyUpdate({ set: { preferences: JSON.stringify(preferences), updatedAt } });
  return true;
}
