import { and, desc, eq, sql } from "drizzle-orm";
import { drizzle } from "drizzle-orm/mysql2";
import { InsertUser, movieFavorites, movieWatchHistory, users } from "../drizzle/schema";
import { ENV } from "./_core/env";
import { randomUUID } from "node:crypto";

let _db: ReturnType<typeof drizzle> | null = null;

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

export async function recordWatchHistory(input: { userId: number; movieSlug: string; movieName: string; originName?: string; posterUrl?: string | null; year?: number | null; episodeSlug?: string; episodeName?: string; sourceName?: string; watchedSeconds?: number; durationSeconds?: number }) {
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
    sourceName: input.sourceName || null,
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
      sourceName: input.sourceName || null,
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

export async function removeWatchHistory(userId: number, historyId: number) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  await db.delete(movieWatchHistory).where(and(eq(movieWatchHistory.userId, userId), eq(movieWatchHistory.id, historyId)));
  return true;
}
