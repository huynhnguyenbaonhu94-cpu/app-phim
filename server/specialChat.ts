import { and, asc, desc, eq, gt, inArray, max, sql } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import { getDb, getUserById } from "./db";
import { specialChatAttachments, specialChatMessages, users } from "../drizzle/schema";
import { storageBackend, storageGetSignedUrl, storagePut, storageRead } from "./storage";
import { authenticateLocalRequest } from "./localAuth";
import type { Express } from "express";

export const SPECIAL_CHAT_MEDIA_RULES = {
  image: { maxBytes: 8 * 1024 * 1024, mimes: ["image/jpeg", "image/png", "image/webp", "image/gif"] },
  video: { maxBytes: 32 * 1024 * 1024, mimes: ["video/mp4", "video/quicktime", "video/webm"] },
} as const;
const MAX_MESSAGES = 100;

type Sender = "user" | "admin";
export type SpecialChatMessage = {
  id: number;
  userId: number;
  sender: Sender;
  text: string | null;
  mediaUrl: string | null;
  mediaType: string | null;
  createdAt: string;
};
export type SpecialChatConversation = {
  userId: number;
  name: string | null;
  email: string | null;
  hasSpecialPrivileges: boolean;
  messageCount: number;
  lastMessageAt: string | null;
  lastMessagePreview: string | null;
};

function mediaUrl(attachmentId: number | null): string | null {
  return attachmentId ? `/api/special-chat/media/${attachmentId}` : null;
}
function asIso(value: Date | string | null | undefined): string {
  if (!value) return new Date(0).toISOString();
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? new Date(0).toISOString() : date.toISOString();
}
function normalizeFilename(filename: string | undefined, mimeType: string) {
  const fallback = mimeType.startsWith("video/") ? "video" : "image";
  const clean = (filename || fallback).replace(/[^a-zA-Z0-9._-]+/g, "_").slice(0, 140) || fallback;
  return clean;
}
function extensionForMime(mimeType: string) {
  return ({
    "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "image/gif": "gif",
    "video/mp4": "mp4", "video/quicktime": "mov", "video/webm": "webm",
  } as Record<string, string>)[mimeType];
}
function decodeBase64(base64: string) {
  const raw = base64.replace(/^data:[^;,]+;base64,/i, "").replace(/\s+/g, "");
  if (!raw || raw.length % 4 === 1 || !/^[A-Za-z0-9+/]*={0,2}$/.test(raw)) {
    throw new Error("Dữ liệu media base64 không hợp lệ.");
  }
  const bytes = Buffer.from(raw, "base64");
  if (!bytes.length) throw new Error("Tệp media rỗng.");
  return bytes;
}
function validateMedia(mimeType: string, byteSize: number) {
  const normalized = mimeType.trim().toLowerCase();
  const kind = normalized.startsWith("image/") ? SPECIAL_CHAT_MEDIA_RULES.image : normalized.startsWith("video/") ? SPECIAL_CHAT_MEDIA_RULES.video : null;
  if (!kind || !(kind.mimes as readonly string[]).includes(normalized)) throw new Error("Chỉ chấp nhận ảnh JPG/PNG/WebP/GIF hoặc video MP4/MOV/WebM.");
  if (byteSize > kind.maxBytes) throw new Error(`Tệp quá lớn (tối đa ${Math.round(kind.maxBytes / 1024 / 1024)}MB).`);
  return normalized;
}
async function ensureUserCanChat(userId: number, allowUnprivileged = false) {
  const user = await getUserById(userId);
  if (!user) throw new Error("Không tìm thấy tài khoản.");
  if (!allowUnprivileged && user.role !== "admin" && !user.hasSpecialPrivileges) throw new Error("Tài khoản chưa được cấp quyền chat đặc biệt.");
  return user;
}
async function attachmentForUser(attachmentId: number, userId: number) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  const rows = await db.select().from(specialChatAttachments).where(and(eq(specialChatAttachments.id, attachmentId), eq(specialChatAttachments.userId, userId))).limit(1);
  return rows[0];
}

export async function uploadSpecialChatMedia(input: { userId: number; base64: string; filename?: string; mimeType: string; allowUnprivileged?: boolean }) {
  await ensureUserCanChat(input.userId, input.allowUnprivileged);
  const bytes = decodeBase64(input.base64);
  const mimeType = validateMedia(input.mimeType, bytes.byteLength);
  const extension = extensionForMime(mimeType);
  if (!extension) throw new Error("MIME không được hỗ trợ.");
  const filename = normalizeFilename(input.filename, mimeType);
  const storageKey = `special-chat/${input.userId}/${randomUUID()}.${extension}`;
  await storagePut(storageKey, bytes, mimeType);
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  const result = await db.insert(specialChatAttachments).values({ userId: input.userId, storageKey, originalFilename: filename, mimeType, byteSize: bytes.byteLength }).$returningId();
  const attachmentId = Number(result[0]?.id);
  if (!Number.isFinite(attachmentId) || attachmentId <= 0) throw new Error("Không tạo được attachment.");
  return { attachmentId, mimeType, byteSize: bytes.byteLength, mediaUrl: mediaUrl(attachmentId) };
}

async function mapMessages(rows: Array<{ message: typeof specialChatMessages.$inferSelect; attachment: typeof specialChatAttachments.$inferSelect | null }>): Promise<SpecialChatMessage[]> {
  return rows.map(({ message, attachment }) => ({
    id: message.id,
    userId: message.userId,
    sender: message.sender as Sender,
    text: message.text ?? null,
    mediaUrl: mediaUrl(attachment?.id ?? null),
    mediaType: attachment?.mimeType ?? null,
    createdAt: asIso(message.createdAt),
  }));
}
export async function listSpecialChatMessages(userId: number, afterId?: number, allowUnprivileged = false) {
  await ensureUserCanChat(userId, allowUnprivileged);
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  const conditions = [eq(specialChatMessages.userId, userId)];
  if (afterId !== undefined) conditions.push(gt(specialChatMessages.id, afterId));
  const rows = await db.select({ message: specialChatMessages, attachment: specialChatAttachments })
    .from(specialChatMessages)
    .leftJoin(specialChatAttachments, and(eq(specialChatMessages.attachmentId, specialChatAttachments.id), eq(specialChatAttachments.userId, userId)))
    .where(and(...conditions)).orderBy(asc(specialChatMessages.id)).limit(MAX_MESSAGES);
  return mapMessages(rows);
}
export async function sendSpecialChatMessage(input: { userId: number; sender: Sender; text?: string | null; attachmentId?: number | null; clientRequestId?: string | null; allowUnprivileged?: boolean }) {
  await ensureUserCanChat(input.userId, input.allowUnprivileged);
  const text = input.text?.trim() || null;
  const attachmentId = input.attachmentId ?? null;
  if (!text && !attachmentId) throw new Error("Tin nhắn cần có nội dung hoặc media.");
  if (text && text.length > 4000) throw new Error("Tin nhắn tối đa 4000 ký tự.");
  if (attachmentId) {
    const attachment = await attachmentForUser(attachmentId, input.userId);
    if (!attachment) throw new Error("Attachment không thuộc cuộc hội thoại này.");
  }
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  const clientRequestId = input.clientRequestId?.trim() || randomUUID();
  const existing = await db.select({ message: specialChatMessages, attachment: specialChatAttachments })
    .from(specialChatMessages)
    .leftJoin(specialChatAttachments, and(eq(specialChatMessages.attachmentId, specialChatAttachments.id), eq(specialChatAttachments.userId, input.userId)))
    .where(and(eq(specialChatMessages.userId, input.userId), eq(specialChatMessages.clientRequestId, clientRequestId)))
    .limit(1);
  if (existing[0]) return (await mapMessages(existing))[0];
  let id = 0;
  try {
    const result = await db.insert(specialChatMessages).values({ userId: input.userId, sender: input.sender, text, attachmentId, clientRequestId }).$returningId();
    id = Number(result[0]?.id);
  } catch (error) {
    // Concurrent retries can hit the unique request key after the first insert committed.
    const existing = await db.select({ message: specialChatMessages, attachment: specialChatAttachments })
      .from(specialChatMessages)
      .leftJoin(specialChatAttachments, and(eq(specialChatMessages.attachmentId, specialChatAttachments.id), eq(specialChatAttachments.userId, input.userId)))
      .where(and(eq(specialChatMessages.userId, input.userId), eq(specialChatMessages.clientRequestId, clientRequestId)))
      .limit(1);
    if (existing[0]) return (await mapMessages(existing))[0];
    throw error;
  }
  const rows = Number.isSafeInteger(id) && id > 0
    ? await db.select({ message: specialChatMessages, attachment: specialChatAttachments }).from(specialChatMessages)
      .leftJoin(specialChatAttachments, and(eq(specialChatMessages.attachmentId, specialChatAttachments.id), eq(specialChatAttachments.userId, input.userId)))
      .where(eq(specialChatMessages.id, id)).limit(1)
    : await db.select({ message: specialChatMessages, attachment: specialChatAttachments }).from(specialChatMessages)
      .leftJoin(specialChatAttachments, and(eq(specialChatMessages.attachmentId, specialChatAttachments.id), eq(specialChatAttachments.userId, input.userId)))
      .where(and(eq(specialChatMessages.userId, input.userId), eq(specialChatMessages.clientRequestId, clientRequestId))).limit(1);
  const mapped = await mapMessages(rows);
  if (!mapped[0]) throw new Error("Không đọc lại được tin nhắn.");
  return mapped[0];
}

export async function listSpecialChatConversations(): Promise<SpecialChatConversation[]> {
  const db = await getDb();
  if (!db) return [];
  const latest = max(specialChatMessages.createdAt);
  const grouped = await db.select({ userId: specialChatMessages.userId, lastMessageAt: latest, messageCount: sql<number>`count(*)` })
    .from(specialChatMessages).groupBy(specialChatMessages.userId).orderBy(desc(latest)).limit(200);
  if (!grouped.length) return [];
  const profileRows = await db.select({ id: users.id, name: users.name, email: users.email, hasSpecialPrivileges: users.hasSpecialPrivileges })
    .from(users).where(inArray(users.id, grouped.map(row => row.userId)));
  const profiles = new Map(profileRows.map(profile => [profile.id, profile]));
  const previews = await Promise.all(grouped.map(async row => {
    const latestMessage = await db.select({ text: specialChatMessages.text, attachmentId: specialChatMessages.attachmentId }).from(specialChatMessages)
      .where(and(eq(specialChatMessages.userId, row.userId), eq(specialChatMessages.createdAt, row.lastMessageAt!))).orderBy(desc(specialChatMessages.id)).limit(1);
    return [row.userId, latestMessage[0]] as const;
  }));
  const previewMap = new Map(previews);
  return grouped.map(row => {
    const profile = profiles.get(row.userId);
    const last = previewMap.get(row.userId);
    return { userId: row.userId, name: profile?.name ?? null, email: profile?.email ?? null, hasSpecialPrivileges: Boolean(profile?.hasSpecialPrivileges), messageCount: Number(row.messageCount), lastMessageAt: row.lastMessageAt ? asIso(row.lastMessageAt) : null, lastMessagePreview: last?.text || (last?.attachmentId ? "[Media]" : null) };
  });
}

export async function getSpecialChatAttachmentForAccess(attachmentId: number, viewer: { id: number; role: string; hasSpecialPrivileges: boolean }) {
  const db = await getDb();
  if (!db) return undefined;
  const rows = await db.select().from(specialChatAttachments).where(eq(specialChatAttachments.id, attachmentId)).limit(1);
  const attachment = rows[0];
  if (!attachment) return undefined;
  if (viewer.role !== "admin" && (!viewer.hasSpecialPrivileges || attachment.userId !== viewer.id)) return undefined;
  return attachment;
}
export async function signedSpecialChatMediaUrl(attachment: { storageKey: string }) {
  return storageGetSignedUrl(attachment.storageKey);
}

/** Media không public: mỗi request phải có session và được kiểm tra ownership. */
export function registerSpecialChatMediaRoute(app: Express) {
  app.get("/api/special-chat/media/:id", async (req, res) => {
    const id = Number.parseInt(String(req.params.id), 10);
    if (!Number.isInteger(id) || id <= 0) return res.status(400).send("Bad attachment id");
    const viewer = await authenticateLocalRequest(req);
    if (!viewer) return res.status(401).send("Unauthorized");
    const attachment = await getSpecialChatAttachmentForAccess(id, viewer);
    if (!attachment) return res.status(404).send("Not found");
    try {
      res.setHeader("Cache-Control", "private, no-store");
      res.setHeader("Content-Type", attachment.mimeType);
      res.setHeader("Content-Disposition", `inline; filename="${attachment.originalFilename.replace(/[^a-zA-Z0-9._-]/g, "_")}"`);
      if (await storageBackend() === "local") {
        return res.status(200).send(await storageRead(attachment.storageKey));
      }
      const signedUrl = await signedSpecialChatMediaUrl(attachment);
      if (!signedUrl) return res.status(200).send(await storageRead(attachment.storageKey));
      return res.redirect(307, signedUrl);
    } catch (error) {
      console.error("[SpecialChat] protected media failed:", error);
      return res.status(502).send("Media unavailable");
    }
  });
}
