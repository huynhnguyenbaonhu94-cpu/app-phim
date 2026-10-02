import { asc, eq, inArray } from "drizzle-orm";
import { getDb, ensureTvVideosCompatibility } from "./db";
import { tvVideos, tvVideoEpisodes, tvVideoQualities } from "../drizzle/schema";
import { checkStreamHealth, validateOptionalUrl, validateStreamUrl } from "./tvStreams";

export type TvVideoQualityInput = { label: string; streamUrl: string };
export type TvVideoEpisodeInput = { episodeNumber: number; name?: string; qualities: TvVideoQualityInput[] };
export type TvVideoPayload = { name: string; logoUrl?: string | null; description?: string | null; sortOrder?: number; isActive?: boolean; episodes: TvVideoEpisodeInput[] };

function clean(value: string | null | undefined, max: number) { return value?.trim().slice(0, max) || null; }
function normalize(input: TvVideoPayload) {
  const name = input.name.trim().slice(0, 180);
  if (!name) throw new Error("Tên video không được để trống.");
  if (!input.episodes.length) throw new Error("Video phải có ít nhất một tập.");
  const episodes = input.episodes.map((episode, index) => {
    if (!episode.qualities.length) throw new Error(`Tập ${index + 1} phải có ít nhất một chất lượng.`);
    return {
      episodeNumber: Math.max(1, Math.floor(episode.episodeNumber || index + 1)),
      name: clean(episode.name, 180) || `Tập ${episode.episodeNumber || index + 1}`,
      qualities: episode.qualities.map((quality) => ({
        label: quality.label.trim().slice(0, 40) || "Auto",
        streamUrl: validateStreamUrl(quality.streamUrl),
      })),
    };
  });
  return { name, logoUrl: validateOptionalUrl(input.logoUrl, "URL logo"), description: clean(input.description, 1000), sortOrder: Math.max(0, Math.min(100000, Math.floor(input.sortOrder ?? 0))), isActive: input.isActive !== false, episodes };
}

async function validateAllLinks(episodes: TvVideoEpisodeInput[]) {
  for (const episode of episodes) for (const quality of episode.qualities) {
    const health = await checkStreamHealth(quality.streamUrl);
    if (health.status !== "online") throw new Error(`Tập ${episode.episodeNumber} · ${quality.label}: ${health.message}`);
  }
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
  return videos.map((video) => ({ ...video, episodes: episodes.filter((episode) => episode.videoId === video.id).map((episode) => ({ ...episode, qualities: qualities.filter((quality) => quality.episodeId === episode.id) })) }));
}

export async function createTvVideo(input: TvVideoPayload) {
  const db = await getDb(); if (!db) throw new Error("Database is not available");
  await ensureTvVideosCompatibility(db);
  const values = normalize(input);
  await validateAllLinks(values.episodes);
  const inserted = await db.insert(tvVideos).values({ name: values.name, logoUrl: values.logoUrl, description: values.description, sortOrder: values.sortOrder, isActive: values.isActive });
  const videoId = Number((inserted as unknown as { insertId: number }).insertId);
  for (const episode of values.episodes) {
    const result = await db.insert(tvVideoEpisodes).values({ videoId, episodeNumber: episode.episodeNumber, name: episode.name });
    const episodeId = Number((result as unknown as { insertId: number }).insertId);
    await db.insert(tvVideoQualities).values(episode.qualities.map((quality) => ({ episodeId, label: quality.label, streamUrl: quality.streamUrl, healthStatus: "online", healthMessage: "Stream đang hoạt động" })));
  }
  return (await listTvVideos(true)).find((video) => video.id === videoId) || null;
}

export async function updateTvVideo(id: number, input: TvVideoPayload) {
  const db = await getDb(); if (!db) throw new Error("Database is not available");
  await ensureTvVideosCompatibility(db);
  const values = normalize(input);
  await validateAllLinks(values.episodes);
  await db.update(tvVideos).set({ name: values.name, logoUrl: values.logoUrl, description: values.description, sortOrder: values.sortOrder, isActive: values.isActive }).where(eq(tvVideos.id, id));
  const oldEpisodes = await db.select({ id: tvVideoEpisodes.id }).from(tvVideoEpisodes).where(eq(tvVideoEpisodes.videoId, id));
  if (oldEpisodes.length) await db.delete(tvVideoQualities).where(inArray(tvVideoQualities.episodeId, oldEpisodes.map((episode) => episode.id)));
  await db.delete(tvVideoEpisodes).where(eq(tvVideoEpisodes.videoId, id));
  for (const episode of values.episodes) {
    const result = await db.insert(tvVideoEpisodes).values({ videoId: id, episodeNumber: episode.episodeNumber, name: episode.name });
    const episodeId = Number((result as unknown as { insertId: number }).insertId);
    await db.insert(tvVideoQualities).values(episode.qualities.map((quality) => ({ episodeId, label: quality.label, streamUrl: quality.streamUrl, healthStatus: "online", healthMessage: "Stream đang hoạt động" })));
  }
  return (await listTvVideos(true)).find((video) => video.id === id) || null;
}

export async function deleteTvVideo(id: number) {
  const db = await getDb(); if (!db) throw new Error("Database is not available");
  const episodes = await db.select({ id: tvVideoEpisodes.id }).from(tvVideoEpisodes).where(eq(tvVideoEpisodes.videoId, id));
  if (episodes.length) await db.delete(tvVideoQualities).where(inArray(tvVideoQualities.episodeId, episodes.map((episode) => episode.id)));
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
    if (quality.healthStatus !== health.status || quality.healthMessage !== health.message) {
      await db.update(tvVideoQualities).set({ healthStatus: health.status, healthMessage: health.message }).where(eq(tvVideoQualities.id, quality.id));
    }
  }));
}
