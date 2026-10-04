import { asc, eq, inArray } from "drizzle-orm";
import { getDb, ensureTvVideosCompatibility } from "./db";
import { tvVideos, tvVideoEpisodes, tvVideoQualities, tvVideoSubtitles } from "../drizzle/schema";
import { checkStreamHealth, validateOptionalUrl, validateStreamUrl } from "./tvStreams";

export type TvVideoQualityInput = { label: string; streamUrl: string; subtitleUrl?: string | null; bilingualSubtitleUrl?: string | null };
export type TvVideoSubtitleInput = { language: string; subtitleUrl: string; isDefault?: boolean };
export type TvVideoEpisodeInput = { episodeNumber: number; name?: string; subtitleUrl?: string | null; bilingualSubtitleUrl?: string | null; subtitles?: TvVideoSubtitleInput[]; qualities: TvVideoQualityInput[] };
export type TvVideoPayload = { name: string; logoUrl?: string | null; description?: string | null; sortOrder?: number; isActive?: boolean; allowPip?: boolean; episodes: TvVideoEpisodeInput[] };

function clean(value: string | null | undefined, max: number) { return value?.trim().slice(0, max) || null; }
function validateSubtitleUrl(value: string | null | undefined) {
  if (!value?.trim()) return null;
  const trimmed = value.trim();
  if (trimmed.startsWith("/uploads/tv-subtitles/") || trimmed.startsWith("uploads/tv-subtitles/")) return trimmed.startsWith("/") ? trimmed : `/${trimmed}`;
  try { const url = new URL(trimmed); if (!["http:", "https:"].includes(url.protocol)) throw new Error(); return url.toString(); } catch { throw new Error("URL phụ đề phải là URL http(s) hoặc file VTT đã upload."); }
}
function normalize(input: TvVideoPayload) {
  const name = input.name.trim().slice(0, 180);
  if (!name) throw new Error("Tên video không được để trống.");
  if (!input.episodes.length) throw new Error("Video phải có ít nhất một tập.");
  const episodes = input.episodes.map((episode, index) => {
    if (!episode.qualities.length) throw new Error(`Tập ${index + 1} phải có ít nhất một chất lượng.`);
    const legacySubtitleUrl = validateSubtitleUrl(episode.subtitleUrl) ?? validateSubtitleUrl(episode.qualities[0]?.subtitleUrl);
    const additionalSubtitles = (episode.subtitles ?? []).map((subtitle) => {
      const subtitleUrl = validateSubtitleUrl(subtitle.subtitleUrl);
      if (!subtitleUrl) throw new Error(`Tập ${episode.episodeNumber}: URL phụ đề ${subtitle.language} không được để trống.`);
      return { language: subtitle.language.trim().slice(0, 40) || "原语言", subtitleUrl, isDefault: subtitle.isDefault === true };
    });
    const subtitles = legacySubtitleUrl
      ? [{ language: "Tiếng Việt", subtitleUrl: legacySubtitleUrl, isDefault: true }, ...additionalSubtitles.filter((subtitle) => subtitle.subtitleUrl !== legacySubtitleUrl).map((subtitle) => ({ ...subtitle, isDefault: false }))]
      : additionalSubtitles.map((subtitle, index) => ({ ...subtitle, isDefault: subtitle.isDefault || index === 0 }));
    return {
      episodeNumber: Math.max(1, Math.floor(episode.episodeNumber || index + 1)),
      name: clean(episode.name, 180) || `Tập ${episode.episodeNumber || index + 1}`,
      subtitleUrl: validateSubtitleUrl(episode.subtitleUrl),
      bilingualSubtitleUrl: validateSubtitleUrl(episode.bilingualSubtitleUrl),
      subtitles,
      qualities: episode.qualities.map((quality) => ({
        label: quality.label.trim().slice(0, 40) || "Auto",
        streamUrl: validateStreamUrl(quality.streamUrl),
        subtitleUrl: validateSubtitleUrl(quality.subtitleUrl),
        bilingualSubtitleUrl: validateSubtitleUrl(quality.bilingualSubtitleUrl),
      })),
    };
  });
  return { name, logoUrl: validateOptionalUrl(input.logoUrl, "URL logo"), description: clean(input.description, 1000), sortOrder: Math.max(0, Math.min(100000, Math.floor(input.sortOrder ?? 0))), isActive: input.isActive !== false, allowPip: input.allowPip !== false, episodes };
}

async function validateAllLinks(episodes: TvVideoEpisodeInput[]) {
  const healthByURL = new Map<string, Awaited<ReturnType<typeof checkStreamHealth>>>();
  for (const episode of episodes) for (const quality of episode.qualities) {
    const health = await checkStreamHealth(quality.streamUrl);
    healthByURL.set(quality.streamUrl, health);
    if (health.status === "offline") throw new Error(`Tập ${episode.episodeNumber} · ${quality.label}: ${health.message}`);
  }
  return healthByURL;
}

function getInsertId(result: unknown, label: string) {
  const raw = result as { insertId?: number | bigint; [key: number]: { insertId?: number | bigint } | undefined };
  const value = raw?.insertId ?? raw?.[0]?.insertId;
  const id = Number(value);
  if (!Number.isSafeInteger(id) || id <= 0) throw new Error(`Không thể lấy ID sau khi thêm ${label}. Vui lòng thử lại.`);
  return id;
}

export async function listTvVideos(includeInactive = false) {
  const db = await getDb(); if (!db) return [];
  await ensureTvVideosCompatibility(db);
  const videos = includeInactive ? await db.select().from(tvVideos).orderBy(asc(tvVideos.sortOrder), asc(tvVideos.id)) : await db.select().from(tvVideos).where(eq(tvVideos.isActive, true)).orderBy(asc(tvVideos.sortOrder), asc(tvVideos.id));
  if (!videos.length) return [];
  const ids = videos.map((video) => video.id);
  const episodes = await db.select().from(tvVideoEpisodes).where(inArray(tvVideoEpisodes.videoId, ids)).orderBy(asc(tvVideoEpisodes.episodeNumber), asc(tvVideoEpisodes.id));
  const episodeIds = episodes.map((episode) => episode.id);
  const qualities = episodeIds.length ? await db.select().from(tvVideoQualities).where(inArray(tvVideoQualities.episodeId, episodeIds)).orderBy(asc(tvVideoQualities.id)) : [];
  const subtitles = episodeIds.length ? await db.select().from(tvVideoSubtitles).where(inArray(tvVideoSubtitles.episodeId, episodeIds)).orderBy(asc(tvVideoSubtitles.id)) : [];
  return videos.map((video) => ({ ...video, episodes: episodes.filter((episode) => episode.videoId === video.id).map((episode) => ({ ...episode, qualities: qualities.filter((quality) => quality.episodeId === episode.id), subtitles: subtitles.filter((subtitle) => subtitle.episodeId === episode.id) })) }));
}

export async function createTvVideo(input: TvVideoPayload) {
  const db = await getDb(); if (!db) throw new Error("Database is not available");
  await ensureTvVideosCompatibility(db);
  const values = normalize(input);
  const healthByURL = await validateAllLinks(values.episodes);
  const inserted = await db.insert(tvVideos).values({ name: values.name, logoUrl: values.logoUrl, description: values.description, sortOrder: values.sortOrder, isActive: values.isActive, allowPip: values.allowPip });
  const videoId = getInsertId(inserted, "video");
  for (const episode of values.episodes) {
    const result = await db.insert(tvVideoEpisodes).values({ videoId, episodeNumber: episode.episodeNumber, name: episode.name, subtitleUrl: episode.subtitleUrl, bilingualSubtitleUrl: episode.bilingualSubtitleUrl });
    const episodeId = getInsertId(result, "tập");
    await db.insert(tvVideoQualities).values(episode.qualities.map((quality) => {
      const health = healthByURL.get(quality.streamUrl);
      return { episodeId, label: quality.label, streamUrl: quality.streamUrl, subtitleUrl: quality.subtitleUrl, bilingualSubtitleUrl: quality.bilingualSubtitleUrl, healthStatus: health?.status ?? "unknown", healthMessage: health?.message ?? "Chưa xác minh từ máy chủ" };
    }));
    if (episode.subtitles.length) await db.insert(tvVideoSubtitles).values(episode.subtitles.map((subtitle, index) => ({ episodeId, language: subtitle.language, subtitleUrl: subtitle.subtitleUrl!, isDefault: subtitle.isDefault || index === 0 })));
  }
  return (await listTvVideos(true)).find((video) => video.id === videoId) || null;
}

export async function updateTvVideo(id: number, input: TvVideoPayload) {
  const db = await getDb(); if (!db) throw new Error("Database is not available");
  await ensureTvVideosCompatibility(db);
  const values = normalize(input);
  const healthByURL = await validateAllLinks(values.episodes);
  await db.update(tvVideos).set({ name: values.name, logoUrl: values.logoUrl, description: values.description, sortOrder: values.sortOrder, isActive: values.isActive, allowPip: values.allowPip }).where(eq(tvVideos.id, id));
  const oldEpisodes = await db.select({ id: tvVideoEpisodes.id }).from(tvVideoEpisodes).where(eq(tvVideoEpisodes.videoId, id));
  if (oldEpisodes.length) {
    const oldEpisodeIds = oldEpisodes.map((episode) => episode.id);
    await db.delete(tvVideoSubtitles).where(inArray(tvVideoSubtitles.episodeId, oldEpisodeIds));
    await db.delete(tvVideoQualities).where(inArray(tvVideoQualities.episodeId, oldEpisodeIds));
  }
  await db.delete(tvVideoEpisodes).where(eq(tvVideoEpisodes.videoId, id));
  for (const episode of values.episodes) {
    const result = await db.insert(tvVideoEpisodes).values({ videoId: id, episodeNumber: episode.episodeNumber, name: episode.name, subtitleUrl: episode.subtitleUrl, bilingualSubtitleUrl: episode.bilingualSubtitleUrl });
    const episodeId = getInsertId(result, "tập");
    await db.insert(tvVideoQualities).values(episode.qualities.map((quality) => {
      const health = healthByURL.get(quality.streamUrl);
      return { episodeId, label: quality.label, streamUrl: quality.streamUrl, subtitleUrl: quality.subtitleUrl, bilingualSubtitleUrl: quality.bilingualSubtitleUrl, healthStatus: health?.status ?? "unknown", healthMessage: health?.message ?? "Chưa xác minh từ máy chủ" };
    }));
    if (episode.subtitles.length) await db.insert(tvVideoSubtitles).values(episode.subtitles.map((subtitle, index) => ({ episodeId, language: subtitle.language, subtitleUrl: subtitle.subtitleUrl!, isDefault: subtitle.isDefault || index === 0 })));
  }
  return (await listTvVideos(true)).find((video) => video.id === id) || null;
}

export async function deleteTvVideo(id: number) {
  const db = await getDb(); if (!db) throw new Error("Database is not available");
  const episodes = await db.select({ id: tvVideoEpisodes.id }).from(tvVideoEpisodes).where(eq(tvVideoEpisodes.videoId, id));
  if (episodes.length) {
    const episodeIds = episodes.map((episode) => episode.id);
    await db.delete(tvVideoSubtitles).where(inArray(tvVideoSubtitles.episodeId, episodeIds));
    await db.delete(tvVideoQualities).where(inArray(tvVideoQualities.episodeId, episodeIds));
  }
  await db.delete(tvVideoEpisodes).where(eq(tvVideoEpisodes.videoId, id));
  await db.delete(tvVideos).where(eq(tvVideos.id, id));
  return true;
}

export async function refreshAllTvVideosHealth() {
  const db = await getDb(); if (!db) return;
  await ensureTvVideosCompatibility(db);
  const qualities = await db.select().from(tvVideoQualities);
  await Promise.all(qualities.map(async (quality) => {
    const health = await checkStreamHealth(quality.streamUrl);
    // Do not downgrade a previously working link because a CDN temporarily
    // blocks the server-side health probe. The player can still be opened by
    // the client, which may have different network/headers than this server.
    if (health.status === "unknown") {
      if (quality.healthStatus === "unknown" && quality.healthMessage !== health.message) {
        await db.update(tvVideoQualities).set({ healthMessage: health.message }).where(eq(tvVideoQualities.id, quality.id));
      }
      return;
    }
    if (quality.healthStatus !== health.status || quality.healthMessage !== health.message) {
      await db.update(tvVideoQualities).set({ healthStatus: health.status, healthMessage: health.message }).where(eq(tvVideoQualities.id, quality.id));
    }
  }));
}
