import { createHash, randomBytes } from "node:crypto";
import { and, desc, eq, isNull, sql } from "drizzle-orm";
import type { Request } from "express";
import { accountSessions, users } from "../drizzle/schema";
import { COOKIE_NAME } from "@shared/const";
import { getDb } from "./db";

export const MAX_ACCOUNT_DEVICES = 5;
const ONLINE_WINDOW_MS = 90_000;

export type DeviceRequestMetadata = {
  deviceId?: string;
  deviceName?: string;
};

export type AccountDevice = {
  id: number;
  deviceId: string;
  deviceName: string;
  ipAddress: string;
  location: string;
  userAgent: string;
  createdAt: Date;
  lastSeenAt: Date;
  isOnline: boolean;
};

export type AdminAccountSummary = {
  id: number; openId: string; name: string | null; email: string | null; role: string; loginMethod: string | null;
  createdAt: Date; updatedAt: Date; lastSignedIn: Date; activeDeviceCount: number; favoriteCount: number; historyCount: number; latestDeviceSeenAt: Date | null;  avatar: string | null;
  badge: string | null;
};

function hashToken(token: string) {
  return createHash("sha256").update(token).digest("hex");
}

function requestIp(req: Request) {
  const forwarded = req.headers["x-forwarded-for"];
  const value = typeof forwarded === "string" ? forwarded.split(",")[0]?.trim() : req.ip;
  return value || "Không xác định";
}

function requestLocation(req: Request) {
  const country = req.headers["cf-ipcountry"] || req.headers["x-country-code"];
  return typeof country === "string" && country ? country : "Không xác định";
}

function defaultDeviceName(req: Request) {
  const agent = req.get("user-agent") || "Unknown device";
  if (/iPhone/i.test(agent)) return "iPhone";
  if (/iPad/i.test(agent)) return "iPad";
  if (/Android/i.test(agent)) return "Android";
  if (/Macintosh|Mac OS/i.test(agent)) return "Mac";
  if (/Windows/i.test(agent)) return "Windows PC";
  return agent.slice(0, 80);
}

export function getDeviceMetadata(req: Request, input: DeviceRequestMetadata = {}) {
  const rawDeviceId = input.deviceId?.trim();
  const deviceId = rawDeviceId && rawDeviceId.length <= 160
    ? rawDeviceId
    : `browser-${hashToken(`${req.get("user-agent") || "unknown"}|${requestIp(req)}`).slice(0, 32)}`;
  const rawName = input.deviceName?.trim();
  return {
    deviceId,
    deviceName: rawName ? rawName.slice(0, 160) : defaultDeviceName(req),
    ipAddress: requestIp(req).slice(0, 80),
    location: requestLocation(req).slice(0, 160),
    userAgent: (req.get("user-agent") || "").slice(0, 2000),
  };
}

export async function createDeviceSession(userId: number, req: Request, metadata: DeviceRequestMetadata = {}) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  const device = getDeviceMetadata(req, metadata);
  const existing = await db.select({ id: accountSessions.id })
    .from(accountSessions)
    .where(and(eq(accountSessions.userId, userId), eq(accountSessions.deviceId, device.deviceId), isNull(accountSessions.revokedAt)))
    .limit(1);
  if (existing[0]) {
    await db.update(accountSessions).set({ revokedAt: new Date() }).where(eq(accountSessions.id, existing[0].id));
  }
  const active = await db.select({ id: accountSessions.id })
    .from(accountSessions)
    .where(and(eq(accountSessions.userId, userId), isNull(accountSessions.revokedAt)));
  if (active.length >= MAX_ACCOUNT_DEVICES) {
    throw new Error(`Tài khoản chỉ được đăng nhập tối đa ${MAX_ACCOUNT_DEVICES} thiết bị. Hãy đăng xuất một thiết bị trước.`);
  }
  const token = randomBytes(48).toString("base64url");
  await db.insert(accountSessions).values({
    userId,
    tokenHash: hashToken(token),
    deviceId: device.deviceId,
    deviceName: device.deviceName,
    ipAddress: device.ipAddress,
    location: device.location,
    userAgent: device.userAgent,
  });
  return token;
}

export async function authenticateDeviceRequest(req: Request) {
  const token = req.headers.cookie?.match(new RegExp(`(?:^|;\\s*)${COOKIE_NAME}=([^;]+)`))?.[1];
  if (!token) return null;
  const db = await getDb();
  if (!db) return null;
  const rows = await db.select({ session: accountSessions, user: users })
    .from(accountSessions)
    .innerJoin(users, eq(accountSessions.userId, users.id))
    .where(and(eq(accountSessions.tokenHash, hashToken(token)), isNull(accountSessions.revokedAt)))
    .limit(1);
  const row = rows[0];
  if (!row) return null;
  await db.update(accountSessions).set({ lastSeenAt: new Date(), ipAddress: requestIp(req).slice(0, 80) }).where(eq(accountSessions.id, row.session.id));
  return { user: row.user, session: row.session };
}

export async function revokeSession(token: string | undefined) {
  if (!token) return;
  const db = await getDb();
  if (!db) return;
  await db.update(accountSessions).set({ revokedAt: new Date() }).where(eq(accountSessions.tokenHash, hashToken(token)));
}

export async function revokeAllSessions(userId: number) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  await db.update(accountSessions).set({ revokedAt: new Date() }).where(and(eq(accountSessions.userId, userId), isNull(accountSessions.revokedAt)));
}

export async function revokeDevice(userId: number, id: number) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  await db.update(accountSessions).set({ revokedAt: new Date() }).where(and(eq(accountSessions.userId, userId), eq(accountSessions.id, id), isNull(accountSessions.revokedAt)));
}

export async function listAccountDevices(userId: number): Promise<AccountDevice[]> {
  const db = await getDb();
  if (!db) return [];
  const rows = await db.select().from(accountSessions)
    .where(and(eq(accountSessions.userId, userId), isNull(accountSessions.revokedAt)))
    .orderBy(desc(accountSessions.lastSeenAt));
  const now = Date.now();
  return rows.map((row) => ({
    id: row.id,
    deviceId: row.deviceId,
    deviceName: row.deviceName,
    ipAddress: row.ipAddress || "Không xác định",
    location: row.location || "Không xác định",
    userAgent: row.userAgent || "",
    createdAt: row.createdAt,
    lastSeenAt: row.lastSeenAt,
    isOnline: now - row.lastSeenAt.getTime() <= ONLINE_WINDOW_MS,
  }));
}

export async function listAllAccountSummaries(): Promise<AdminAccountSummary[]> {
  const db = await getDb();
  if (!db) return [];
  const [rows] = await db.execute(sql.raw(`
    SELECT u.id, u.openId, u.name, u.email, u.role, u.avatar, u.badge, u.loginMethod, u.createdAt, u.updatedAt, u.lastSignedIn,
      COUNT(DISTINCT CASE WHEN s.revokedAt IS NULL THEN s.id END) AS activeDeviceCount,
      COUNT(DISTINCT f.id) AS favoriteCount, COUNT(DISTINCT h.id) AS historyCount,
      MAX(CASE WHEN s.revokedAt IS NULL THEN s.lastSeenAt END) AS latestDeviceSeenAt
    FROM users u
    LEFT JOIN account_sessions s ON s.userId = u.id
    LEFT JOIN movie_favorites f ON f.userId = u.id
    LEFT JOIN movie_watch_history h ON h.userId = u.id
    GROUP BY u.id, u.openId, u.name, u.email, u.role, u.avatar, u.badge, u.loginMethod, u.createdAt, u.updatedAt, u.lastSignedIn
    ORDER BY u.createdAt DESC
  `));
  return (rows as unknown as Array<Record<string, unknown>>).map((row) => ({
    id: Number(row.id), openId: String(row.openId), name: row.name as string | null, email: row.email as string | null, role: String(row.role), avatar: (row.avatar as string | null) ?? null, badge: (row.badge as string | null) ?? null, loginMethod: row.loginMethod as string | null,
    createdAt: new Date(String(row.createdAt)), updatedAt: new Date(String(row.updatedAt)), lastSignedIn: new Date(String(row.lastSignedIn)),
    activeDeviceCount: Number(row.activeDeviceCount || 0), favoriteCount: Number(row.favoriteCount || 0), historyCount: Number(row.historyCount || 0),
    latestDeviceSeenAt: row.latestDeviceSeenAt ? new Date(String(row.latestDeviceSeenAt)) : null,
  }));
}

export async function ensureAccountSessionsCompatibility() {
  const db = await getDb();
  if (!db) return;
  await db.execute(sql.raw(`CREATE TABLE IF NOT EXISTS account_sessions (
    id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
    userId int NOT NULL,
    tokenHash varchar(128) NOT NULL UNIQUE,
    deviceId varchar(160) NOT NULL,
    deviceName varchar(160) NOT NULL,
    ipAddress varchar(80) NULL,
    location varchar(160) NULL,
    userAgent text NULL,
    createdAt timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    lastSeenAt timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revokedAt timestamp NULL,
    INDEX account_sessions_user_active_idx (userId, revokedAt),
    INDEX account_sessions_user_device_idx (userId, deviceId),
    INDEX account_sessions_last_seen_idx (lastSeenAt)
  ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`));
}
