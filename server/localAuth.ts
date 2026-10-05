import { randomBytes, scrypt as scryptCallback, timingSafeEqual } from "node:crypto";
import { SignJWT, jwtVerify } from "jose";
import { COOKIE_NAME, ONE_YEAR_MS } from "@shared/const";
import { parse as parseCookieHeader } from "cookie";
import type { Request } from "express";
import type { User } from "../drizzle/schema";
import { getActiveDeviceSession, getUserByOpenId } from "./db";
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
  if (ENV.cookieSecret) return new TextEncoder().encode(ENV.cookieSecret);
  if (process.env.NODE_ENV === "development" || process.env.NODE_ENV === "test") {
    return new TextEncoder().encode("cinemora-development-only-secret");
  }
  throw new Error("JWT_SECRET must be configured for any non-development deployment.");
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

export async function createLocalSession(user: User, sessionId?: string, expiresAt: Date = new Date(Date.now() + ONE_YEAR_MS)) {
  const claims: Record<string, string | number> = { userId: user.id, openId: user.openId, loginMethod: "email" };
  if (sessionId) claims.sid = sessionId;
  return new SignJWT(claims)
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setIssuer(SESSION_ISSUER)
    .setIssuedAt()
    .setExpirationTime(Math.floor(expiresAt.getTime() / 1000))
    .sign(secretKey());
}

export async function authenticateLocalRequest(req: Request): Promise<{ user: User | null; sessionId: string | null; sessionInvalid: boolean; legacyToken?: string }> {
  const cookies = parseCookieHeader(req.headers.cookie || "");
  const authorization = req.headers.authorization;
  const bearer = typeof authorization === "string" && authorization.startsWith("Bearer ") ? authorization.slice(7).trim() : "";
  const token = bearer || cookies[COOKIE_NAME];
  if (!token) return { user: null, sessionId: null, sessionInvalid: false };
  try {
    const { payload } = await jwtVerify(token, secretKey(), { algorithms: ["HS256"], issuer: SESSION_ISSUER });
    const openId = typeof payload.openId === "string" ? payload.openId : "";
    if (!openId.startsWith("local_")) return { user: null, sessionId: null, sessionInvalid: false };
    const sessionId = typeof payload.sid === "string" ? payload.sid : null;
    const user = (await getUserByOpenId(openId)) || null;
    if (!user) return { user: null, sessionId, sessionInvalid: !!sessionId };
    // Context upgrades this legacy cookie to a revocable DB session transparently.
    if (!sessionId) return { user, sessionId: null, sessionInvalid: false, legacyToken: token };
    if (sessionId && !(await getActiveDeviceSession(sessionId, user.id))) return { user: null, sessionId, sessionInvalid: true };
    return { user, sessionId, sessionInvalid: false };
  } catch {
    return { user: null, sessionId: null, sessionInvalid: false };
  }
}
