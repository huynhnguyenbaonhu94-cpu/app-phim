import { and, asc, eq } from "drizzle-orm";
import { ensureTvStreamsCompatibility, getDb } from "./db";
import { tvStreams } from "../drizzle/schema";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { randomUUID } from "node:crypto";

export type TvStreamPayload = {
  name: string;
  streamUrl: string;
  audioUrl?: string | null;
  logoUrl?: string | null;
  posterUrl?: string | null;
  description?: string | null;
  sortOrder?: number;
  isActive?: boolean;
};

type TvEvent = { type: "snapshot" | "changed"; version: number };
const listeners = new Set<(event: TvEvent) => void>();
let version = 0;

export function subscribeTvStreams(listener: (event: TvEvent) => void) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function publishTvStreamsChanged() {
  version += 1;
  const event: TvEvent = { type: "changed", version };
  listeners.forEach((listener) => listener(event));
}

export function currentTvStreamsVersion() { return version; }

function clean(value: string | null | undefined, max: number) {
  return value?.trim().slice(0, max) || null;
}

export function validateStreamUrl(value: string) {
  try {
    const url = new URL(value.trim());
    if (!["https:", "http:"].includes(url.protocol)) throw new Error("URL stream phải bắt đầu bằng http:// hoặc https://");
    return url.toString();
  } catch {
    throw new Error("URL stream không hợp lệ.");
  }
}

export function validateOptionalUrl(value: string | null | undefined, label = "URL") {
  if (!value?.trim()) return null;
  const trimmed = value.trim();
  if (trimmed.startsWith("/uploads/tv-posters/")) return trimmed.slice(0, 1000);
  if (trimmed.startsWith("uploads/tv-posters/")) return `/${trimmed}`.slice(0, 1000);
  try {
    const url = new URL(trimmed);
    if (!["https:", "http:"].includes(url.protocol)) throw new Error();
    return url.toString();
  } catch {
    throw new Error(`${label} không hợp lệ.`);
  }
}

export async function saveTvPoster(input: { base64: string; mimeType: "image/jpeg" | "image/png" | "image/webp" }) {
  const raw = input.base64.includes(",") ? input.base64.split(",", 2)[1] : input.base64;
  const bytes = Buffer.from(raw, "base64");
  if (!bytes.length || bytes.length > 8 * 1024 * 1024) throw new Error("Ảnh poster phải nhỏ hơn 8MB.");
  const extension = input.mimeType === "image/png" ? "png" : input.mimeType === "image/webp" ? "webp" : "jpg";
  const directory = path.resolve(process.cwd(), "uploads", "tv-posters");
  await mkdir(directory, { recursive: true });
  const filename = `${randomUUID()}.${extension}`;
  await writeFile(path.join(directory, filename), bytes, { flag: "wx" });
  return `/uploads/tv-posters/${filename}`;
}

export async function checkStreamHealth(streamUrl: string, audioUrl?: string | null) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8_000);
  try {
    const response = await fetch(streamUrl, {
      method: "GET",
      headers: { accept: "application/vnd.apple.mpegurl, application/x-mpegURL, video/*, */*", range: "bytes=0-2047", "user-agent": "Cinemora/1.0" },
      redirect: "follow",
      signal: controller.signal,
    });
    try { await response.body?.cancel(); } catch { /* response body cancellation is best effort */ }
    if (!response.ok) return { status: "offline" as const, message: `Stream HTTP ${response.status}` };
    if (audioUrl) {
      const audioResponse = await fetch(audioUrl, { method: "GET", headers: { accept: "audio/*, application/vnd.apple.mpegurl, */*", range: "bytes=0-2047", "user-agent": "Cinemora/1.0" }, redirect: "follow", signal: controller.signal });
      try { await audioResponse.body?.cancel(); } catch { /* best effort */ }
      if (!audioResponse.ok) return { status: "offline" as const, message: `Audio HTTP ${audioResponse.status}` };
      return { status: "online" as const, message: "Stream và audio đang hoạt động" };
    }
    return { status: "online" as const, message: "Stream đang hoạt động" };
  } catch (error) {
    return { status: "offline" as const, message: error instanceof Error && error.name === "AbortError" ? "Hết thời gian kiểm tra" : "Không kết nối được stream" };
  } finally {
    clearTimeout(timeout);
  }
}

export async function listTvStreams(includeInactive = false) {
  const db = await getDb();
  if (!db) return [];
  await ensureTvStreamsCompatibility(db);
  const query = db.select().from(tvStreams);
  const rows = includeInactive
    ? await query.orderBy(asc(tvStreams.sortOrder), asc(tvStreams.id))
    : await query.where(and(eq(tvStreams.isActive, true), eq(tvStreams.healthStatus, "online"))).orderBy(asc(tvStreams.sortOrder), asc(tvStreams.id));
  return rows;
}

function normalizedValues(input: TvStreamPayload) {
  const values = {
    name: input.name.trim().slice(0, 120),
    streamUrl: validateStreamUrl(input.streamUrl),
    audioUrl: validateOptionalUrl(input.audioUrl, "URL audio"),
    posterUrl: validateOptionalUrl(input.posterUrl),
    description: clean(input.description, 500),
    sortOrder: Math.max(0, Math.min(100000, Math.floor(input.sortOrder ?? 0))),
    isActive: input.isActive !== false,
  };
  if (!values.name) throw new Error("Tên kênh không được để trống.");
  return values;
}

async function refreshHealth(id: number, streamUrl: string, audioUrl?: string | null) {
  const db = await getDb();
  if (!db) return;
  const health = await checkStreamHealth(streamUrl, audioUrl);
  await db.update(tvStreams).set({ healthStatus: health.status, healthMessage: health.message, lastCheckedAt: new Date() }).where(eq(tvStreams.id, id));
}

export async function refreshAllTvStreamsHealth() {
  const db = await getDb();
  if (!db) return;
  await ensureTvStreamsCompatibility(db);
  const rows = await db.select().from(tvStreams);
  let changed = false;
  await Promise.all(rows.filter((row) => row.isActive).map(async (row) => {
    const health = await checkStreamHealth(row.streamUrl, row.audioUrl);
    if (row.healthStatus !== health.status || row.healthMessage !== health.message) changed = true;
    await db.update(tvStreams)
      .set({ healthStatus: health.status, healthMessage: health.message, lastCheckedAt: new Date() })
      .where(eq(tvStreams.id, row.id));
  }));
  if (changed) publishTvStreamsChanged();
}

export async function createTvStream(input: TvStreamPayload) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  await ensureTvStreamsCompatibility(db);
  const values = normalizedValues(input);
  await db.insert(tvStreams).values({ ...values, healthStatus: "unknown", healthMessage: "Đang kiểm tra…", lastCheckedAt: new Date() });
  const rows = await db.select().from(tvStreams).where(eq(tvStreams.name, values.name)).orderBy(asc(tvStreams.id)).limit(1);
  const created = rows[0];
  if (!created) throw new Error("Không thể đọc stream vừa tạo.");
  await refreshHealth(created.id, created.streamUrl, created.audioUrl);
  publishTvStreamsChanged();
  const refreshed = await db.select().from(tvStreams).where(eq(tvStreams.id, created.id)).limit(1);
  return refreshed[0] || created;
}

export async function updateTvStream(id: number, input: TvStreamPayload) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  await ensureTvStreamsCompatibility(db);
  const values = normalizedValues(input);
  await db.update(tvStreams).set({ ...values, healthStatus: "unknown", healthMessage: "Đang kiểm tra…", lastCheckedAt: new Date() }).where(eq(tvStreams.id, id));
  await refreshHealth(id, values.streamUrl, values.audioUrl);
  publishTvStreamsChanged();
  const rows = await db.select().from(tvStreams).where(eq(tvStreams.id, id)).limit(1);
  return rows[0] || null;
}

export async function deleteTvStream(id: number) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  await ensureTvStreamsCompatibility(db);
  await db.delete(tvStreams).where(eq(tvStreams.id, id));
  publishTvStreamsChanged();
  return true;
}
