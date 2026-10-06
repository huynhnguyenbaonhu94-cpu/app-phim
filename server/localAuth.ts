import { randomBytes, scrypt as scryptCallback, timingSafeEqual } from "node:crypto";
import { SignJWT, jwtVerify } from "jose";
import { COOKIE_NAME, ONE_YEAR_MS } from "@shared/const";
import { parse as parseCookieHeader } from "cookie";
import type { Request } from "express";
import type { User } from "../drizzle/schema";
import { getUserByOpenId } from "./db";
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
  return new TextEncoder().encode(ENV.cookieSecret || "cinemora-development-secret");
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

export async function createLocalSession(user: User) {
  return new SignJWT({ userId: user.id, openId: user.openId, loginMethod: "email" })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setIssuer(SESSION_ISSUER)
    .setIssuedAt()
    .setExpirationTime(Math.floor((Date.now() + ONE_YEAR_MS) / 1000))
    .sign(secretKey());
}

export async function authenticateLocalRequest(req: Request): Promise<User | null> {
  const cookies = parseCookieHeader(req.headers.cookie || "");
  const token = cookies[COOKIE_NAME];
  if (!token) return null;
  try {
    const { payload } = await jwtVerify(token, secretKey(), { algorithms: ["HS256"], issuer: SESSION_ISSUER });
    const openId = typeof payload.openId === "string" ? payload.openId : "";
    if (!openId.startsWith("local_")) return null;
    return (await getUserByOpenId(openId)) || null;
  } catch {
    return null;
  }
}
