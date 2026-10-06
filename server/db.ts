import { and, desc, eq, sql } from "drizzle-orm";
import { drizzle } from "drizzle-orm/mysql2";
import { migrate } from "drizzle-orm/mysql2/migrator";
import { InsertUser, movieFavorites, movieWatchHistory, users } from "../drizzle/schema";
import { ENV } from "./_core/env";
import { randomUUID } from "node:crypto";
import path from "node:path";
import { ensureAccountSessionsCompatibility } from "./accountSessions";

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
  const password = process.env.ADMIN_PASSWORD || "Cinemora@2026!";
  const name = process.env.ADMIN_NAME || "Cinemora Admin";
  if (!email || password.length < 8) throw new Error("ADMIN_EMAIL/ADMIN_PASSWORD không hợp lệ.");
  const existing = await db.select({ id: users.id }).from(users).where(eq(users.email, email)).limit(1);
  if (existing.length > 0) return;
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

export async function initializeDatabase() {
  if (initialization) return initialization;
  initialization = (async () => {
    const db = await getDb();
    if (!db) throw new Error("DATABASE_URL chưa được cấu hình.");
    try {
      await migrate(db, { migrationsFolder: path.resolve(process.cwd(), "drizzle") });
    } catch (error) {
      // Older deployments may already have a tv_streams migration with a different tag.
      // Compatibility repair below can safely add only the missing columns.
      console.warn("[Database] Migration warning, running compatibility repair:", error instanceof Error ? error.message : error);
    }
    await ensureTvStreamsCompatibility(db);
    await ensureTvVideosCompatibility(db);
    await ensureAccountSessionsCompatibility();
    await ensureQrLoginCompatibility(db);
    await ensureDefaultAdmin(db);
  })();
  try {
    await initialization;
  } catch (error) {
    initialization = null;
    throw error;
  }
}

export async function ensureQrLoginCompatibility(db: ReturnType<typeof drizzle>) {
  await db.execute(sql.raw(`CREATE TABLE IF NOT EXISTS qr_login_challenges (
    id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
    nonceHash varchar(128) NOT NULL UNIQUE,
    deviceId varchar(160) NOT NULL,
    deviceName varchar(160) NOT NULL,
    ipAddress varchar(80) NULL,
    location varchar(160) NULL,
    userAgent text NULL,
    status varchar(20) NOT NULL DEFAULT 'pending',
    approvedUserId int NULL,
    approvedAt timestamp NULL,
    expiresAt timestamp NOT NULL,
    consumedAt timestamp NULL,
    createdAt timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX qr_login_challenges_status_expiry_idx (status, expiresAt)
  ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`));
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

export async function addFavorite(input: { userId: number; movieSlug: string; movieName: string; originName?: string; posterUrl?: string | null; year?: number | null }) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  await db.insert(movieFavorites).values({ ...input, originName: input.originName || null, posterUrl: input.posterUrl || null, year: input.year || null }).onDuplicateKeyUpdate({ set: { movieName: input.movieName, originName: input.originName || null, posterUrl: input.posterUrl || null, year: input.year || null } });
  return true;
}

export async function removeFavorite(userId: number, movieSlug: string) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  await db.delete(movieFavorites).where(and(eq(movieFavorites.userId, userId), eq(movieFavorites.movieSlug, movieSlug)));
  return true;
}

export async function recordWatchHistory(input: { userId: number; movieSlug: string; movieName: string; originName?: string; posterUrl?: string | null; year?: number | null; episodeSlug?: string; episodeName?: string; watchedSeconds?: number; durationSeconds?: number }) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  const safeEpisode = input.episodeSlug || "movie";
  await db.insert(movieWatchHistory).values({
    ...input,
    originName: input.originName || null,
    posterUrl: input.posterUrl || null,
    year: input.year || null,
    episodeSlug: safeEpisode,
    episodeName: input.episodeName || "Phim",
    watchedSeconds: Math.max(0, Math.floor(input.watchedSeconds || 0)),
    durationSeconds: Math.max(0, Math.floor(input.durationSeconds || 0)),
    lastWatchedAt: new Date(),
  }).onDuplicateKeyUpdate({
    set: {
      movieName: input.movieName,
      originName: input.originName || null,
      posterUrl: input.posterUrl || null,
      year: input.year || null,
      episodeName: input.episodeName || "Phim",
      watchedSeconds: Math.max(0, Math.floor(input.watchedSeconds || 0)),
      durationSeconds: Math.max(0, Math.floor(input.durationSeconds || 0)),
      lastWatchedAt: sql`CURRENT_TIMESTAMP`,
    },
  });
  return true;
}

export async function listWatchHistory(userId: number) {
  const db = await getDb();
  if (!db) return [];
  return db.select().from(movieWatchHistory).where(eq(movieWatchHistory.userId, userId)).orderBy(desc(movieWatchHistory.lastWatchedAt)).limit(100);
}

export async function removeWatchHistory(userId: number, movieSlug: string, episodeSlug?: string) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  const safeEpisode = episodeSlug || "movie";
  await db.delete(movieWatchHistory).where(and(eq(movieWatchHistory.userId, userId), eq(movieWatchHistory.movieSlug, movieSlug), eq(movieWatchHistory.episodeSlug, safeEpisode)));
  return true;
}

export async function clearWatchHistory(userId: number) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  await db.delete(movieWatchHistory).where(eq(movieWatchHistory.userId, userId));
  return true;
}

export async function getUserById(id: number) {
  const db = await getDb();
  if (!db) return undefined;
  const result = await db.select().from(users).where(eq(users.id, id)).limit(1);
  return result[0];
}

export async function updateLocalPassword(userId: number, passwordHash: string) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  await db.update(users).set({ passwordHash }).where(eq(users.id, userId));
  return true;
}

export async function updateLocalAccountByAdmin(input: { id: number; name?: string; email?: string; passwordHash?: string; role?: "user" | "admin" }) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  const updates: Record<string, unknown> = {};
  if (input.name !== undefined) updates.name = input.name;
  if (input.email !== undefined) {
    const existing = await db.select({ id: users.id }).from(users).where(eq(users.email, input.email)).limit(1);
    if (existing[0] && existing[0].id !== input.id) throw new Error("Email này đã được sử dụng bởi tài khoản khác.");
    updates.email = input.email;
  }
  if (input.passwordHash !== undefined) updates.passwordHash = input.passwordHash;
  if (input.role !== undefined) updates.role = input.role;
  if (Object.keys(updates).length === 0) return getUserById(input.id);
  await db.update(users).set(updates).where(eq(users.id, input.id));
  return getUserById(input.id);
}
