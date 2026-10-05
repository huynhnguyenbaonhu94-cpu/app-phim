import { createHash, randomBytes, scrypt as scryptCallback, timingSafeEqual } from "node:crypto";
import { COOKIE_NAME } from "@shared/const";
import { parse as parseCookieHeader } from "cookie";
import type { Request } from "express";
import type { User } from "../drizzle/schema";
import { countActiveAccountSessions, createAccountSession, getAccountSessionByTokenHash, revokeSessionForDevice, touchAccountSession } from "./accountSessions";

function deriveKey(password: string, salt: Buffer, length: number) {
  return new Promise<Buffer>((resolve, reject) => scryptCallback(password, salt, length, { N: 16_384, r: 8, p: 1 }, (error, derived) => error ? reject(error) : resolve(derived as Buffer)));
}
const PASSWORD_SCHEME = "scrypt-v1";
export function hashSessionToken(token: string) { return createHash("sha256").update(token).digest("hex"); }
export async function hashPassword(password: string) { const salt = randomBytes(16); const derived = await deriveKey(password, salt, 64); return `${PASSWORD_SCHEME}$${salt.toString("base64url")}$${derived.toString("base64url")}`; }
export async function verifyPassword(password: string, stored: string | null) {
  if (!stored) return false;
  const [scheme, saltText, hashText] = stored.split("$"); if (scheme !== PASSWORD_SCHEME || !saltText || !hashText) return false;
  try { const expected = Buffer.from(hashText, "base64url"); const actual = await deriveKey(password, Buffer.from(saltText, "base64url"), expected.length); return actual.length === expected.length && timingSafeEqual(actual, expected); } catch { return false; }
}

export type SessionMetadata = { deviceId: string; deviceName: string; deviceModel?: string; ipAddress?: string; userAgent?: string };
export async function createLocalSession(user: User, metadata: SessionMetadata) {
  await revokeSessionForDevice(user.id, metadata.deviceId);
  const activeCount = await countActiveAccountSessions(user.id);
  if (activeCount >= 5) throw new Error("Tài khoản đã đạt tối đa 5 thiết bị. Hãy đăng xuất một thiết bị trước khi đăng nhập thêm.");
  const token = randomBytes(32).toString("base64url");
  await createAccountSession({ id: randomBytes(24).toString("hex"), userId: user.id, tokenHash: hashSessionToken(token), deviceId: metadata.deviceId, deviceName: metadata.deviceName, deviceModel: metadata.deviceModel || null, ipAddress: metadata.ipAddress || null, userAgent: metadata.userAgent || null });
  return token;
}

export async function authenticateLocalRequestWithSession(req: Request) {
  const token = parseCookieHeader(req.headers.cookie || "")[COOKIE_NAME];
  if (!token) return { user: null, session: null };
  const session = await getAccountSessionByTokenHash(hashSessionToken(token));
  if (!session || session.revokedAt) return { user: null, session };
  // Resolve by numeric user id without relying on the legacy openId token payload.
  const dbUser = await (await import("./db")).getUserById(session.userId);
  if (!dbUser) return { user: null, session };
  if (Date.now() - new Date(session.lastSeenAt).getTime() > 20_000) await touchAccountSession(session.id);
  return { user: dbUser, session };
}
export async function authenticateLocalRequest(req: Request): Promise<User | null> { return (await authenticateLocalRequestWithSession(req)).user; }
