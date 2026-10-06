import { createHash, randomBytes } from "node:crypto";
import { and, eq, gt, isNull, lt } from "drizzle-orm";
import type { Request } from "express";
import { qrLoginChallenges, users } from "../drizzle/schema";
import { getDb } from "./db";
import { createDeviceSession, getDeviceMetadata } from "./accountSessions";

export const QR_LOGIN_TTL_MS = 2 * 60 * 1000;
const QR_PREFIX = "cinemora-qr-v1:";

function hashNonce(nonce: string) {
  return createHash("sha256").update(nonce).digest("hex");
}

function cleanNonce(value: string) {
  const nonce = value.startsWith(QR_PREFIX) ? value.slice(QR_PREFIX.length) : value;
  if (!/^[A-Za-z0-9_-]{32,160}$/.test(nonce)) throw new Error("Mã QR không hợp lệ.");
  return nonce;
}

export function qrPayload(nonce: string) {
  return `${QR_PREFIX}${nonce}`;
}

export async function createQrLoginChallenge(req: Request, input: { deviceId?: string; deviceName?: string }) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  await db.delete(qrLoginChallenges).where(lt(qrLoginChallenges.expiresAt, new Date()));
  const device = getDeviceMetadata(req, input);
  const nonce = randomBytes(32).toString("base64url");
  const expiresAt = new Date(Date.now() + QR_LOGIN_TTL_MS);
  await db.insert(qrLoginChallenges).values({
    nonceHash: hashNonce(nonce), deviceId: device.deviceId, deviceName: device.deviceName,
    ipAddress: device.ipAddress, location: device.location, userAgent: device.userAgent, expiresAt,
  });
  return { nonce, payload: qrPayload(nonce), expiresAt };
}

async function findChallenge(nonceInput: string) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  const nonce = cleanNonce(nonceInput);
  const rows = await db.select({ challenge: qrLoginChallenges, user: users })
    .from(qrLoginChallenges)
    .leftJoin(users, eq(qrLoginChallenges.approvedUserId, users.id))
    .where(eq(qrLoginChallenges.nonceHash, hashNonce(nonce))).limit(1);
  return { db, row: rows[0] };
}

export async function qrLoginStatus(nonceInput: string) {
  const { db, row } = await findChallenge(nonceInput);
  if (!row) return { status: "invalid" as const };
  const challenge = row.challenge;
  if (challenge.status === "pending" && challenge.expiresAt.getTime() <= Date.now()) {
    await db.update(qrLoginChallenges).set({ status: "expired" }).where(and(eq(qrLoginChallenges.id, challenge.id), eq(qrLoginChallenges.status, "pending")));
    return { status: "expired" as const };
  }
  return {
    status: challenge.status as "pending" | "approved" | "denied" | "expired" | "consumed",
    expiresAt: challenge.expiresAt,
    deviceName: challenge.deviceName,
    approver: row.user ? { name: row.user.name, email: row.user.email } : null,
  };
}

export async function approveQrLogin(nonceInput: string, userId: number, approved: boolean) {
  const { db, row } = await findChallenge(nonceInput);
  if (!row) throw new Error("Mã QR không tồn tại hoặc đã hết hạn.");
  const challenge = row.challenge;
  if (challenge.status !== "pending" || challenge.expiresAt.getTime() <= Date.now()) {
    if (challenge.status === "pending") await db.update(qrLoginChallenges).set({ status: "expired" }).where(eq(qrLoginChallenges.id, challenge.id));
    throw new Error("Mã QR đã hết hạn hoặc đã được xử lý.");
  }
  await db.update(qrLoginChallenges).set({ status: approved ? "approved" : "denied", approvedUserId: approved ? userId : null, approvedAt: approved ? new Date() : null })
    .where(and(eq(qrLoginChallenges.id, challenge.id), eq(qrLoginChallenges.status, "pending"), gt(qrLoginChallenges.expiresAt, new Date())));
  return qrLoginStatus(nonceInput);
}

export async function completeQrLogin(req: Request, nonceInput: string, metadata: { deviceId?: string; deviceName?: string }) {
  const { db, row } = await findChallenge(nonceInput);
  if (!row || !row.user) throw new Error("Mã QR chưa được chấp nhận.");
  const challenge = row.challenge;
  if (challenge.status !== "approved" || challenge.expiresAt.getTime() <= Date.now() || challenge.consumedAt) throw new Error("Mã QR chưa được chấp nhận hoặc đã hết hạn.");
  const consumedAt = new Date();
  const result = await db.update(qrLoginChallenges).set({ status: "consumed", consumedAt }).where(and(eq(qrLoginChallenges.id, challenge.id), eq(qrLoginChallenges.status, "approved"), isNull(qrLoginChallenges.consumedAt)));
  if (result[0].affectedRows !== 1) throw new Error("Mã QR đã được sử dụng.");
  try {
    const token = await createDeviceSession(row.user.id, req, metadata);
    return { token, user: row.user };
  } catch (error) {
    // If the account is already at the five-device limit, leave the approved
    // challenge retryable instead of consuming it without issuing a session.
    await db.update(qrLoginChallenges).set({ status: "approved", consumedAt: null }).where(eq(qrLoginChallenges.id, challenge.id));
    throw error;
  }
}
