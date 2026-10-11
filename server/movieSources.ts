/**
 * Nguồn và tập do admin thêm thủ công cho một phim lấy từ API.
 *
 * Phim gốc (ví dụ từ phimapi) có sẵn một số nguồn như Vietsub, Thuyết minh. Admin có
 * thể bổ sung nguồn riêng (Lồng tiếng, Phụ đề rời...) kèm link M3U8 và phụ đề VTT, và
 * thêm bao nhiêu tập tùy ý. Những nguồn này được ghép vào kết quả `cinema.detail` nên
 * app đọc như nguồn bình thường, phụ đề hiển thị đúng tiến trình phim.
 */
import fs from "node:fs/promises";
import path from "node:path";
import crypto from "node:crypto";
import { and, asc, eq } from "drizzle-orm";
import { getDb } from "./db";
import { movieSourceEpisodes, movieSources } from "../drizzle/schema";
import { registerStreamSource } from "./cinema";

export type MovieSourceEpisode = {
  id: number;
  sourceId: number;
  name: string;
  streamUrl: string;
  subtitleUrl: string | null;
  hasUploadedSubtitle: boolean;
  sortOrder: number;
};

export type MovieSource = {
  id: number;
  movieSlug: string;
  name: string;
  sortOrder: number;
  episodes: MovieSourceEpisode[];
};

const SUBTITLE_DIR = "uploads/movie-subs";

function toEpisode(row: typeof movieSourceEpisodes.$inferSelect): MovieSourceEpisode {
  return {
    id: row.id,
    sourceId: row.sourceId,
    name: row.name,
    streamUrl: row.streamUrl,
    subtitleUrl: row.subtitleUrl ?? (row.subtitleVtt ? `/api/movies/subtitle/${row.id}.vtt` : null),
    hasUploadedSubtitle: Boolean(row.subtitleVtt && row.subtitleVtt.length > 0),
    sortOrder: row.sortOrder,
  };
}

/** Danh sách nguồn thủ công của một phim, kèm tập của từng nguồn. */
export async function listMovieSources(movieSlug: string): Promise<MovieSource[]> {
  const db = await getDb();
  if (!db) return [];
  const sources = await db
    .select()
    .from(movieSources)
    .where(eq(movieSources.movieSlug, movieSlug))
    .orderBy(asc(movieSources.sortOrder), asc(movieSources.id));
  if (sources.length === 0) return [];

  const episodes = await db
    .select()
    .from(movieSourceEpisodes)
    .orderBy(asc(movieSourceEpisodes.sortOrder), asc(movieSourceEpisodes.id));

  return sources.map((source) => ({
    id: source.id,
    movieSlug: source.movieSlug,
    name: source.name,
    sortOrder: source.sortOrder,
    episodes: episodes.filter((episode) => episode.sourceId === source.id).map(toEpisode),
  }));
}

/** Thêm một nguồn mới cho phim. */
export async function addMovieSource(movieSlug: string, name: string): Promise<MovieSource> {
  const db = await getDb();
  if (!db) throw new Error("Không kết nối được cơ sở dữ liệu");
  const existing = await listMovieSources(movieSlug);
  const [inserted] = await db
    .insert(movieSources)
    .values({ movieSlug, name, sortOrder: existing.length })
    .$returningId();
  return { id: inserted.id, movieSlug, name, sortOrder: existing.length, episodes: [] };
}

/** Đổi tên nguồn. */
export async function renameMovieSource(id: number, name: string): Promise<void> {
  const db = await getDb();
  if (!db) throw new Error("Không kết nối được cơ sở dữ liệu");
  await db.update(movieSources).set({ name }).where(eq(movieSources.id, id));
}

/** Xoá nguồn và toàn bộ tập của nó. */
export async function removeMovieSource(id: number): Promise<void> {
  const db = await getDb();
  if (!db) throw new Error("Không kết nối được cơ sở dữ liệu");
  await db.delete(movieSourceEpisodes).where(eq(movieSourceEpisodes.sourceId, id));
  await db.delete(movieSources).where(eq(movieSources.id, id));
}

/** Thêm một tập cho nguồn: link M3U8 bắt buộc, phụ đề có thể là link ngoài hoặc VTT đã tải lên. */
export async function addMovieEpisode(input: {
  sourceId: number;
  name: string;
  streamUrl: string;
  subtitleUrl?: string | null;
  subtitleVtt?: string | null;
}): Promise<MovieSourceEpisode> {
  const db = await getDb();
  if (!db) throw new Error("Không kết nối được cơ sở dữ liệu");
  const [source] = await db.select().from(movieSources).where(eq(movieSources.id, input.sourceId));
  if (!source) throw new Error("Không tìm thấy nguồn cần thêm tập");
  const episodes = await db
    .select()
    .from(movieSourceEpisodes)
    .where(eq(movieSourceEpisodes.sourceId, input.sourceId));
  const [inserted] = await db
    .insert(movieSourceEpisodes)
    .values({
      sourceId: input.sourceId,
      name: input.name,
      streamUrl: input.streamUrl,
      subtitleUrl: input.subtitleUrl?.trim() ? input.subtitleUrl.trim() : null,
      subtitleVtt: input.subtitleVtt ?? null,
      sortOrder: episodes.length,
    })
    .$returningId();
  const [row] = await db
    .select()
    .from(movieSourceEpisodes)
    .where(eq(movieSourceEpisodes.id, inserted.id));
  return toEpisode(row);
}

/** Sửa thông tin một tập. */
export async function updateMovieEpisode(
  id: number,
  input: { name?: string; streamUrl?: string; subtitleUrl?: string | null; subtitleVtt?: string | null }
): Promise<void> {
  const db = await getDb();
  if (!db) throw new Error("Không kết nối được cơ sở dữ liệu");
  const patch: Record<string, unknown> = {};
  if (input.name !== undefined) patch.name = input.name;
  if (input.streamUrl !== undefined) patch.streamUrl = input.streamUrl;
  if (input.subtitleUrl !== undefined) {
    patch.subtitleUrl = input.subtitleUrl?.trim() ? input.subtitleUrl.trim() : null;
  }
  if (input.subtitleVtt !== undefined) patch.subtitleVtt = input.subtitleVtt;
  if (Object.keys(patch).length === 0) return;
  await db.update(movieSourceEpisodes).set(patch).where(eq(movieSourceEpisodes.id, id));
}

/** Xoá một tập. */
export async function removeMovieEpisode(id: number): Promise<void> {
  const db = await getDb();
  if (!db) throw new Error("Không kết nối được cơ sở dữ liệu");
  await db.delete(movieSourceEpisodes).where(eq(movieSourceEpisodes.id, id));
}

/** Sắp xếp lại tập của một nguồn theo danh sách id. */
export async function reorderMovieEpisodes(sourceId: number, ids: number[]): Promise<void> {
  const db = await getDb();
  if (!db) throw new Error("Không kết nối được cơ sở dữ liệu");
  for (let index = 0; index < ids.length; index += 1) {
    await db
      .update(movieSourceEpisodes)
      .set({ sortOrder: index })
      .where(and(eq(movieSourceEpisodes.id, ids[index]), eq(movieSourceEpisodes.sourceId, sourceId)));
  }
}

/** Chuẩn hoá phụ đề: chuyển SRT sang WebVTT vì AVPlayer chỉ đọc được VTT. */
export function toWebVTT(raw: string): string {
  const text = raw.replace(/\r\n?/g, "\n").trimStart();
  if (/^WEBVTT/i.test(text)) return text;
  const withHeader = text.replace(/^(\d+)\s*$/gm, "");
  const converted = withHeader.replace(/(\d{2}:\d{2}:\d{2}),(\d{3})/g, "$1.$2");
  return `WEBVTT\n\n${converted.trim()}\n`;
}

/** Lưu file phụ đề admin tải lên và trả về URL công khai. */
export async function saveMovieSubtitle(input: {
  base64: string;
  mimeType?: string;
  filename?: string;
}): Promise<{ url: string; content: string }> {
  const content = toWebVTT(Buffer.from(input.base64, "base64").toString("utf8"));
  const target = path.resolve(process.cwd(), SUBTITLE_DIR);
  await fs.mkdir(target, { recursive: true });
  const name = `${Date.now()}-${crypto.randomBytes(4).toString("hex")}.vtt`;
  await fs.writeFile(path.join(target, name), content, "utf8");
  return { url: `${SUBTITLE_DIR}/${name}`, content };
}

/** Nội dung VTT đã lưu của một tập, dùng cho route công khai. */
export async function movieSubtitleVtt(episodeId: number): Promise<string | null> {
  const db = await getDb();
  if (!db) return null;
  const [row] = await db
    .select()
    .from(movieSourceEpisodes)
    .where(eq(movieSourceEpisodes.id, episodeId));
  if (!row) return null;
  if (row.subtitleVtt && row.subtitleVtt.length > 0) return row.subtitleVtt;
  if (row.subtitleUrl) {
    try {
      const response = await fetch(row.subtitleUrl);
      if (response.ok) return toWebVTT(await response.text());
    } catch {
      return null;
    }
  }
  return null;
}

/**
 * Ghép nguồn thủ công vào danh sách nguồn của API.
 *
 * Mỗi tập trả về cả link gốc (`directStreamUrl`) và link qua proxy
 * (`streamUrl`) để app tự chọn; phụ đề trỏ tới file VTT đã lưu.
 */
export async function mergeCustomSources(
  movieSlug: string,
  servers: Array<{
    name: string;
    isAi: boolean;
    episodes: Array<{
      name: string;
      slug: string;
      filename: string;
      embedUrl: string | null;
      streamUrl: string | null;
      directStreamUrl: string | null;
      subtitleUrl?: string | null;
    }>;
  }>
): Promise<typeof servers> {
  const custom = await listMovieSources(movieSlug);
  if (custom.length === 0) return servers;
  const merged = [...servers];
  for (const source of custom) {
    if (source.episodes.length === 0) continue;
    merged.push({
      name: source.name,
      isAi: false,
      episodes: source.episodes.map((episode) => ({
        name: episode.name,
        slug: `custom-${episode.id}`,
        filename: episode.name,
        embedUrl: null,
        streamUrl: registerStreamSource(episode.streamUrl),
        directStreamUrl: episode.streamUrl,
        subtitleUrl: episode.subtitleUrl,
      })),
    });
  }
  return merged;
}