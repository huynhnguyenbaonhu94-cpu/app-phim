import { asc, eq } from "drizzle-orm";
import { getDb } from "./db";
import { tvStreams } from "../drizzle/schema";

export type TvStreamPayload = {
  name: string;
  streamUrl: string;
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

export function validateOptionalUrl(value: string | null | undefined) {
  if (!value?.trim()) return null;
  try {
    const url = new URL(value.trim());
    if (!["https:", "http:"].includes(url.protocol)) throw new Error();
    return url.toString();
  } catch {
    throw new Error("URL poster/logo không hợp lệ.");
  }
}

export async function checkStreamHealth(streamUrl: string) {
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
    if (!response.ok) return { status: "offline" as const, message: `HTTP ${response.status}` };
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
  const query = db.select().from(tvStreams);
  const rows = includeInactive
    ? await query.orderBy(asc(tvStreams.sortOrder), asc(tvStreams.id))
    : await query.where(eq(tvStreams.isActive, true)).orderBy(asc(tvStreams.sortOrder), asc(tvStreams.id));
  return rows;
}

function normalizedValues(input: TvStreamPayload) {
  const values = {
    name: input.name.trim().slice(0, 120),
    streamUrl: validateStreamUrl(input.streamUrl),
    logoUrl: validateOptionalUrl(input.logoUrl),
    posterUrl: validateOptionalUrl(input.posterUrl),
    description: clean(input.description, 500),
    sortOrder: Math.max(0, Math.min(100000, Math.floor(input.sortOrder ?? 0))),
    isActive: input.isActive !== false,
  };
  if (!values.name) throw new Error("Tên kênh không được để trống.");
  return values;
}

async function refreshHealth(id: number, streamUrl: string) {
  const db = await getDb();
  if (!db) return;
  const health = await checkStreamHealth(streamUrl);
  await db.update(tvStreams).set({ healthStatus: health.status, healthMessage: health.message, lastCheckedAt: new Date() }).where(eq(tvStreams.id, id));
}

export async function createTvStream(input: TvStreamPayload) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  const values = normalizedValues(input);
  await db.insert(tvStreams).values(values);
  const rows = await db.select().from(tvStreams).where(eq(tvStreams.name, values.name)).orderBy(asc(tvStreams.id)).limit(1);
  const created = rows[0];
  if (!created) throw new Error("Không thể đọc stream vừa tạo.");
  await refreshHealth(created.id, created.streamUrl);
  publishTvStreamsChanged();
  const refreshed = await db.select().from(tvStreams).where(eq(tvStreams.id, created.id)).limit(1);
  return refreshed[0] || created;
}

export async function updateTvStream(id: number, input: TvStreamPayload) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  const values = normalizedValues(input);
  await db.update(tvStreams).set({ ...values, healthStatus: "unknown", healthMessage: "Đang kiểm tra…", lastCheckedAt: null }).where(eq(tvStreams.id, id));
  await refreshHealth(id, values.streamUrl);
  publishTvStreamsChanged();
  const rows = await db.select().from(tvStreams).where(eq(tvStreams.id, id)).limit(1);
  return rows[0] || null;
}

export async function deleteTvStream(id: number) {
  const db = await getDb();
  if (!db) throw new Error("Database is not available");
  await db.delete(tvStreams).where(eq(tvStreams.id, id));
  publishTvStreamsChanged();
  return true;
}
