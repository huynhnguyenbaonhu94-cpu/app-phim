import { asc, eq } from "drizzle-orm";
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

type ProbeResult = { status: "online" | "offline" | "unknown"; message: string };
const transientProbeStatuses = new Set([401, 403, 408, 425, 429, 500, 501, 502, 503, 504, 520, 521, 522, 523, 524]);

function probeHeaders(url: string, label: string, useRange: boolean) {
  const headers: Record<string, string> = {
    accept: label === "Audio" ? "audio/*, application/vnd.apple.mpegurl, */*" : "application/vnd.apple.mpegurl, application/x-mpegURL, video/*, */*",
    "cache-control": "no-cache",
    "user-agent": "Mozilla/5.0 (compatible; Cinemora-TV-Health/1.0)",
  };
  try {
    const hostname = new URL(url).hostname;
    if (hostname === "d4.dhcn.vn" || hostname === "media.dhcn.vn") {
      headers.origin = "https://baothanhhoa.vn";
      headers.referer = "https://baothanhhoa.vn/";
    }
  } catch { /* URL validation is handled before health probing. */ }
  // Some CDNs reject Range requests even though their HLS URL plays normally.
  if (useRange) headers.range = "bytes=0-2047";
  return headers;
}

async function probeStreamUrl(url: string, label: string): Promise<ProbeResult> {
  let lastNetworkError = false;
  for (const useRange of [true, false]) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8_000);
    try {
      const headers = probeHeaders(url, label, useRange);
      const response = await fetch(url, { method: "GET", headers, redirect: "follow", signal: controller.signal });
      try { await response.body?.cancel(); } catch { /* best effort */ }
      if (response.ok) return { status: "online", message: `${label} đang hoạt động` };
      // A range probe can be rejected while a normal GET is valid; retry without Range.
      if (useRange && (response.status === 400 || response.status === 405 || response.status === 416 || transientProbeStatuses.has(response.status))) continue;
      // CDN edge authorization/rate-limit errors are often short-lived. Do not
      // hide a channel that still plays in the app; keep it visible as unknown.
      if (transientProbeStatuses.has(response.status)) {
        return { status: "unknown", message: `${label} tạm thời không xác minh được (HTTP ${response.status})` };
      }
      return { status: "offline", message: `${label} HTTP ${response.status}` };
    } catch (error) {
      lastNetworkError = true;
      if (!useRange) {
        const message = error instanceof Error && error.name === "AbortError" ? "Không xác minh được: hết thời gian" : "Không xác minh được từ máy chủ";
        return { status: "unknown", message };
      }
    } finally {
      clearTimeout(timeout);
    }
  }
  return { status: lastNetworkError ? "unknown" : "offline", message: "Không xác minh được từ máy chủ" };
}

export async function checkStreamHealth(streamUrl: string, audioUrl?: string | null) {
  const stream = await probeStreamUrl(streamUrl, "Stream");
  if (stream.status !== "online") return stream;
  if (audioUrl) {
    const audio = await probeStreamUrl(audioUrl, "Audio");
    if (audio.status !== "online") return audio;
    return { status: "online" as const, message: "Stream và audio đang hoạt động" };
  }
  return stream;
}

export async function listTvStreams(includeInactive = false) {
  const db = await getDb();
  if (!db) return [];
  await ensureTvStreamsCompatibility(db);
  const query = db.select().from(tvStreams);
  const rows = includeInactive
    ? await query.orderBy(asc(tvStreams.sortOrder), asc(tvStreams.id))
    : await query.where(eq(tvStreams.isActive, true)).orderBy(asc(tvStreams.sortOrder), asc(tvStreams.id));
  // Unknown means the server could not verify the CDN, not that playback is broken.
  // Keep it visible so a playable stream is not silently removed from the app.
  return includeInactive ? rows : rows.filter(row => row.healthStatus !== "offline");
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
