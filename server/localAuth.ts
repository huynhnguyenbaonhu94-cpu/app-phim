import { randomBytes, scrypt as scryptCallback, timingSafeEqual } from "node:crypto";
import { SignJWT, jwtVerify } from "jose";
import { COOKIE_NAME, ONE_YEAR_MS } from "@shared/const";
import { parse as parseCookieHeader } from "cookie";
import type { Request } from "express";
import type { User } from "../drizzle/schema";
import { createAuthSession, getAuthSession, getUserByOpenId, touchAuthSession } from "./db";
import { ENV } from "./_core/env";

function deriveKey(password: string, salt: Buffer, length: number) {
  return new Promise<Buffer>((resolve, reject) => {
    scryptCallback(password, salt, length, { N: 16_384, r: 8, p: 1 }, (error, derived) => {
      if (error) reject(error);
      else resolve(derived as Buffer);
    });
  });
}
const PASSWORD_SCHEME = "scrypt-v1";
const SESSION_ISSUER = "cinemora-local";

function secretKey() {
  const secret = ENV.cookieSecret || (ENV.isProduction ? "" : "cinemora-development-secret-change-before-production");
  if (secret.length < 32) throw new Error("JWT_SECRET phải có ít nhất 32 ký tự.");
  return new TextEncoder().encode(secret);
}

export async function hashPassword(password: string) {
  const salt = randomBytes(16);
  const derived = await deriveKey(password, salt, 64);
  return `${PASSWORD_SCHEME}$${salt.toString("base64url")}$${derived.toString("base64url")}`;
}

export async function verifyPassword(password: string, stored: string | null) {
  if (!stored) return false;
  const [scheme, saltText, hashText] = stored.split("$");
  if (scheme !== PASSWORD_SCHEME || !saltText || !hashText) return false;
  try {
    const salt = Buffer.from(saltText, "base64url");
    const expected = Buffer.from(hashText, "base64url");
    const actual = await deriveKey(password, salt, expected.length);
    return actual.length === expected.length && timingSafeEqual(actual, expected);
  } catch {
    return false;
  }
}

export type NewSessionDevice = { deviceName?: string; deviceModel?: string; platform?: string };

function describeBrowserDevice(userAgent: string) {
  const model = /iPad/i.test(userAgent) ? "iPad" : /iPhone/i.test(userAgent) ? "iPhone" : /Android/i.test(userAgent) ? "Android" : /Windows/i.test(userAgent) ? "Windows PC" : /Mac OS X|Macintosh/i.test(userAgent) ? "Mac" : "Máy tính";
  const browser = /Edg\//i.test(userAgent) ? "Edge" : /Firefox\//i.test(userAgent) ? "Firefox" : /Chrome\//i.test(userAgent) ? "Chrome" : /Safari\//i.test(userAgent) ? "Safari" : "Trình duyệt";
  return { name: `${model} · ${browser}`.slice(0, 120), model: model.slice(0, 120) };
}

export async function createLocalSession(user: User, req: Request, device: NewSessionDevice = {}) {
  const id = randomBytes(18).toString("base64url");
  const signingKey = secretKey();
  const userAgent = String(req.headers["user-agent"] || "").slice(0, 500);
  const browser = describeBrowserDevice(userAgent);
  // Do not trust arbitrary X-Forwarded-For values: cPanel/proxy trust settings vary.
  const ipAddress = req.ip || null;
  await createAuthSession({
    id, userId: user.id,
    deviceName: (device.deviceName || (device.platform === "ios" ? "iPhone" : browser.name)).slice(0, 120),
    deviceModel: device.deviceModel?.slice(0, 120) || (device.platform === "ios" ? null : browser.model),
    platform: (device.platform || "web").slice(0, 40),
    ipAddress: ipAddress && ipAddress !== "::1" && ipAddress !== "127.0.0.1" ? ipAddress.slice(0, 64) : null,
    userAgent: userAgent || null,
  });
  const token = await new SignJWT({ userId: user.id, openId: user.openId, loginMethod: "email", sid: id })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setIssuer(SESSION_ISSUER)
    .setIssuedAt()
    .setExpirationTime(Math.floor((Date.now() + ONE_YEAR_MS) / 1000))
    .sign(signingKey);
  return { token, sessionId: id };
}

export async function authenticateLocalRequest(req: Request): Promise<{ user: User; sessionId: string } | null> {
  const cookies = parseCookieHeader(req.headers.cookie || "");
  const authorization = req.headers.authorization || "";
  const token = authorization.startsWith("Bearer ") ? authorization.slice(7).trim() : cookies[COOKIE_NAME];
  if (!token) return null;
  try {
    const { payload } = await jwtVerify(token, secretKey(), { algorithms: ["HS256"], issuer: SESSION_ISSUER });
    const openId = typeof payload.openId === "string" ? payload.openId : "";
    const sessionId = typeof payload.sid === "string" ? payload.sid : "";
    const userId = typeof payload.userId === "number" ? payload.userId : 0;
    if (!openId.startsWith("local_") || !sessionId || !userId) return null;
    const session = await getAuthSession(sessionId);
    if (!session || session.userId !== userId || session.revokedAt) return null;
    if (!(await touchAuthSession(sessionId))) return null;
    const user = await getUserByOpenId(openId);
    return user?.id === userId ? { user, sessionId } : null;
  } catch {
    return null;
  }
}
