import { and, desc, eq, sql } from "drizzle-orm";
import { accountPreferences, accountSessions, type AccountSession } from "../drizzle/schema";
import { getDb } from "./db";

export async function createAccountSession(input: Omit<AccountSession, "createdAt" | "lastSeenAt" | "revokedAt" | "revokeReason">) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  await db.insert(accountSessions).values(input);
  return getAccountSessionById(input.id);
}
export async function getAccountSessionById(id: string) {
  const db = await getDb(); if (!db) return undefined;
  const rows = await db.select().from(accountSessions).where(eq(accountSessions.id, id)).limit(1); return rows[0];
}
export async function getAccountSessionByTokenHash(tokenHash: string) {
  const db = await getDb(); if (!db) return undefined;
  const rows = await db.select().from(accountSessions).where(eq(accountSessions.tokenHash, tokenHash)).limit(1); return rows[0];
}
export async function listAccountSessions(userId: number) {
  const db = await getDb(); if (!db) return [];
  return db.select().from(accountSessions).where(eq(accountSessions.userId, userId)).orderBy(desc(accountSessions.lastSeenAt));
}
export async function countActiveAccountSessions(userId: number) {
  const db = await getDb(); if (!db) return 0;
  const rows = await db.select({ count: sql<number>`count(*)` }).from(accountSessions).where(and(eq(accountSessions.userId, userId), sql`${accountSessions.revokedAt} IS NULL`));
  return Number(rows[0]?.count ?? 0);
}
export async function revokeSessionForDevice(userId: number, deviceId: string) {
  const db = await getDb(); if (!db) return;
  await db.update(accountSessions).set({ revokedAt: new Date(), revokeReason: "replaced" }).where(and(eq(accountSessions.userId, userId), eq(accountSessions.deviceId, deviceId), sql`${accountSessions.revokedAt} IS NULL`));
}
export async function touchAccountSession(id: string) {
  const db = await getDb(); if (!db) return;
  await db.update(accountSessions).set({ lastSeenAt: new Date() }).where(and(eq(accountSessions.id, id), sql`${accountSessions.revokedAt} IS NULL`));
}
export async function revokeAccountSession(id: string, reason = "logout") {
  const db = await getDb(); if (!db) return;
  await db.update(accountSessions).set({ revokedAt: new Date(), revokeReason: reason }).where(and(eq(accountSessions.id, id), sql`${accountSessions.revokedAt} IS NULL`));
}
export async function revokeAllAccountSessions(userId: number, exceptId?: string, reason = "logout_all") {
  const db = await getDb(); if (!db) return;
  const condition = exceptId ? and(eq(accountSessions.userId, userId), sql`${accountSessions.revokedAt} IS NULL`, sql`${accountSessions.id} <> ${exceptId}`) : and(eq(accountSessions.userId, userId), sql`${accountSessions.revokedAt} IS NULL`);
  await db.update(accountSessions).set({ revokedAt: new Date(), revokeReason: reason }).where(condition);
}
export async function getAccountPreferences(userId: number) {
  const db = await getDb(); if (!db) return undefined;
  const rows = await db.select().from(accountPreferences).where(eq(accountPreferences.userId, userId)).limit(1); return rows[0];
}
export async function saveAccountPreferences(userId: number, playbackDefaults: string) {
  const db = await getDb(); if (!db) throw new Error("Database is not available");
  await db.insert(accountPreferences).values({ userId, playbackDefaults }).onDuplicateKeyUpdate({ set: { playbackDefaults, updatedAt: new Date() } });
}
