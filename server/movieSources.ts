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
import { and, asc, eq, sql } from "drizzle-orm";
import { getDb } from "./db";
import { movieSourceEpisodes, movieSources } from "../drizzle/schema";
import { customDirectStreamUrl, registerCustomStreamSource } from "./cinema";

/** Một chất lượng của tập: mỗi chất lượng có link M3U8 và phụ đề riêng. */
export type MovieSourceQuality = {
  label: string;
  streamUrl: string;
  subtitleUrl: string | null;
};

export type MovieSourceEpisode = {
  id: number;
  sourceId: number;
  name: string;
  streamUrl: string;
  subtitleUrl: string | null;
  hasUploadedSubtitle: boolean;
  sortOrder: number;
  /** Chất lượng của tập (1080p, 2K, 4K…). Rỗng nghĩa là dùng link của tập. */
  qualities: MovieSourceQuality[];
};

export type MovieSource = {
  id: number;
  movieSlug: string;
  name: string;
  sortOrder: number;
  episodes: MovieSourceEpisode[];
};

const SUBTITLE_DIR = "uploads/movie-subs";

/** Đọc JSON chất lượng đã lưu; dữ liệu hỏng thì coi như không có chất lượng. */
function parseQualities(value: unknown): MovieSourceQuality[] {
  if (typeof value !== "string" || !value.trim()) return [];
  try {
    const parsed = JSON.parse(value);
    if (!Array.isArray(parsed)) return [];
    return parsed
      .filter((item: any) => item && typeof item.streamUrl === "string" && item.streamUrl.trim().length > 0)
      .map((item: any) => ({
        label: String(item.label ?? "Mặc định").trim().slice(0, 40) || "Mặc định",
        streamUrl: String(item.streamUrl).trim().slice(0, 2000),
        subtitleUrl: typeof item.subtitleUrl === "string" && item.subtitleUrl.trim() ? item.subtitleUrl.trim().slice(0, 2000) : null,
      }));
  } catch {
    return [];
  }
}

/**
 * Chuẩn hoá phụ đề của một chất lượng thành URL dùng được cho app.
 *
 * Tệp admin tải lên được lưu thành file VTT; link ngoài được máy chủ tải về, đổi
 * sang WebVTT rồi cũng lưu thành file — nhờ vậy lúc phát không phụ thuộc máy chủ
 * nguồn và AVPlayer luôn đọc được (AVPlayer chỉ đọc WebVTT).
 */
async function resolveSubtitleUrl(input: { subtitleUrl?: string | null; subtitleVtt?: string | null }): Promise<string | null> {
  const uploaded = input.subtitleVtt?.trim();
  if (uploaded) {
    const saved = await saveMovieSubtitle({ base64: Buffer.from(uploaded, "utf8").toString("base64"), filename: "quality.vtt" });
    return saved.url.startsWith("/") ? saved.url : `/${saved.url}`;
  }
  const link = input.subtitleUrl?.trim();
  if (!link) return null;
  const converted = await fetchSubtitleAsVtt(link);
  if (!converted) return link;
  const saved = await saveMovieSubtitle({ base64: Buffer.from(converted, "utf8").toString("base64"), filename: "quality.vtt" });
  return saved.url.startsWith("/") ? saved.url : `/${saved.url}`;
}

/** Lưu danh sách chất lượng của tập, kèm phụ đề riêng từng chất lượng. */
async function resolveQualities(input: Array<{ label?: string; streamUrl: string; subtitleUrl?: string | null; subtitleVtt?: string | null }> | undefined): Promise<string | null> {
  if (!input || input.length === 0) return null;
  const resolved: MovieSourceQuality[] = [];
  for (const item of input) {
    const streamUrl = item.streamUrl?.trim();
    if (!streamUrl) continue;
    resolved.push({
      label: String(item.label ?? "").trim().slice(0, 40) || "Mặc định",
      streamUrl: streamUrl.slice(0, 2000),
      subtitleUrl: await resolveSubtitleUrl({ subtitleUrl: item.subtitleUrl, subtitleVtt: item.subtitleVtt }),
    });
  }
  return resolved.length ? JSON.stringify(resolved) : null;
}

function toEpisode(row: typeof movieSourceEpisodes.$inferSelect): MovieSourceEpisode {
  return {
    id: row.id,
    sourceId: row.sourceId,
    name: row.name,
    streamUrl: row.streamUrl,
    // Luôn phát phụ đề qua route của máy chủ: file admin tải lên dùng trực tiếp,
    // link ngoài được máy chủ tải về và đổi sang WebVTT (AVPlayer chỉ đọc VTT).
    subtitleUrl: row.subtitleVtt || row.subtitleUrl ? `/api/movies/subtitle/${row.id}.vtt` : null,
    hasUploadedSubtitle: Boolean(row.subtitleVtt && row.subtitleVtt.length > 0),
    sortOrder: row.sortOrder,
    qualities: parseQualities(row.qualities),
  };
}

/** Danh sách nguồn thủ công của một phim, kèm tập của từng nguồn. */
/**
 * Đánh dấu phim vừa được admin sửa.
 *
 * Ngày cập nhật của phim thủ công phải đổi khi admin thêm/sửa/xoá nguồn hoặc tập,
 * nhưng không được đổi khi chỉ có người xem mở phim.
 */
async function touchMovie(slug: string | null | undefined): Promise<void> {
  if (!slug) return;
  const db = await getDb();
  if (!db) return;
  try {
    await db.execute(sql`UPDATE \`custom_movies\` SET \`updatedAt\` = NOW() WHERE \`slug\` = ${slug}`);
  } catch {
    /* đánh dấu ngày không được làm hỏng thao tác chính */
  }
}

/** Slug phim của một nguồn (dùng trước khi xoá để còn biết đánh dấu phim nào). */
async function sourceMovieSlug(sourceId: number): Promise<string | null> {
  const db = await getDb();
  if (!db) return null;
  const [row] = await db.select().from(movieSources).where(eq(movieSources.id, sourceId));
  return row?.movieSlug ?? null;
}

/** Slug phim của tập (đi ngược từ tập sang nguồn). */
async function episodeMovieSlug(episodeId: number): Promise<string | null> {
  const db = await getDb();
  if (!db) return null;
  const [episode] = await db
    .select()
    .from(movieSourceEpisodes)
    .where(eq(movieSourceEpisodes.id, episodeId));
  if (!episode) return null;
  return sourceMovieSlug(episode.sourceId);
}

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
  await touchMovie(movieSlug);
  return { id: inserted.id, movieSlug, name, sortOrder: existing.length, episodes: [] };
}

/** Đổi tên nguồn. */
export async function renameMovieSource(id: number, name: string): Promise<void> {
  const db = await getDb();
  if (!db) throw new Error("Không kết nối được cơ sở dữ liệu");
  const movieSlug = await sourceMovieSlug(id);
  await db.update(movieSources).set({ name }).where(eq(movieSources.id, id));
  await touchMovie(movieSlug);
}

/** Xoá nguồn và toàn bộ tập của nó. */
export async function removeMovieSource(id: number): Promise<void> {
  const db = await getDb();
  if (!db) throw new Error("Không kết nối được cơ sở dữ liệu");
  const movieSlug = await sourceMovieSlug(id);
  await db.delete(movieSourceEpisodes).where(eq(movieSourceEpisodes.sourceId, id));
  await db.delete(movieSources).where(eq(movieSources.id, id));
  await touchMovie(movieSlug);
}

/** Thêm một tập cho nguồn: link M3U8 bắt buộc, phụ đề có thể là link ngoài hoặc VTT đã tải lên. */
export async function addMovieEpisode(input: {
  sourceId: number;
  name: string;
  streamUrl: string;
  subtitleUrl?: string | null;
  subtitleVtt?: string | null;
  qualities?: Array<{ label?: string; streamUrl: string; subtitleUrl?: string | null; subtitleVtt?: string | null }>;
}): Promise<MovieSourceEpisode> {
  const db = await getDb();
  if (!db) throw new Error("Không kết nối được cơ sở dữ liệu");
  const [source] = await db.select().from(movieSources).where(eq(movieSources.id, input.sourceId));
  if (!source) throw new Error("Không tìm thấy nguồn cần thêm tập");
  const episodes = await db
    .select()
    .from(movieSourceEpisodes)
    .where(eq(movieSourceEpisodes.sourceId, input.sourceId));
  const subtitleLink = input.subtitleUrl?.trim() ? input.subtitleUrl.trim() : null;
  // Đổi ngay link SRT/VTT sang WebVTT khi lưu để lúc phát không phải chờ và
  // không phụ thuộc việc máy chủ nguồn có cho tải lại hay không.
  const subtitleVtt =
    input.subtitleVtt ?? (subtitleLink ? await fetchSubtitleAsVtt(subtitleLink) : null);
  const qualities = await resolveQualities(input.qualities);
  const [inserted] = await db
    .insert(movieSourceEpisodes)
    .values({
      sourceId: input.sourceId,
      name: input.name,
      streamUrl: input.streamUrl,
      subtitleUrl: subtitleLink,
      subtitleVtt: subtitleVtt,
      qualities,
      sortOrder: episodes.length,
    })
    .$returningId();
  const [row] = await db
    .select()
    .from(movieSourceEpisodes)
    .where(eq(movieSourceEpisodes.id, inserted.id));
  await touchMovie(source.movieSlug);
  return toEpisode(row);
}

/** Sửa thông tin một tập. */
export async function updateMovieEpisode(
  id: number,
  input: {
    name?: string;
    streamUrl?: string;
    subtitleUrl?: string | null;
    subtitleVtt?: string | null;
    qualities?: Array<{ label?: string; streamUrl: string; subtitleUrl?: string | null; subtitleVtt?: string | null }>;
  }
): Promise<void> {
  const db = await getDb();
  if (!db) throw new Error("Không kết nối được cơ sở dữ liệu");
  const movieSlug = await episodeMovieSlug(id);
  const patch: Record<string, unknown> = {};
  if (input.name !== undefined) patch.name = input.name;
  if (input.streamUrl !== undefined) patch.streamUrl = input.streamUrl;
  if (input.subtitleUrl !== undefined) {
    const link = input.subtitleUrl?.trim() ? input.subtitleUrl.trim() : null;
    patch.subtitleUrl = link;
    // Đổi link mới sang WebVTT; xoá link thì bỏ luôn VTT đã lưu.
    if (input.subtitleVtt === undefined) {
      patch.subtitleVtt = link ? await fetchSubtitleAsVtt(link) : null;
    }
  }
  if (input.subtitleVtt !== undefined) patch.subtitleVtt = input.subtitleVtt;
  if (input.qualities !== undefined) patch.qualities = await resolveQualities(input.qualities);
  if (Object.keys(patch).length === 0) return;
  await db.update(movieSourceEpisodes).set(patch).where(eq(movieSourceEpisodes.id, id));
  await touchMovie(movieSlug);
}

/** Xoá một tập. */
export async function removeMovieEpisode(id: number): Promise<void> {
  const db = await getDb();
  if (!db) throw new Error("Không kết nối được cơ sở dữ liệu");
  const movieSlug = await episodeMovieSlug(id);
  await db.delete(movieSourceEpisodes).where(eq(movieSourceEpisodes.id, id));
  await touchMovie(movieSlug);
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
  await touchMovie(await sourceMovieSlug(sourceId));
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

/**
 * Tải phụ đề từ link ngoài và đổi sang WebVTT.
 *
 * Trả về `null` khi không tải được (link sai, mạng chặn, file rỗng) để nơi gọi
 * biết mà giữ nguyên link gốc làm phương án dự phòng.
 */
export async function fetchSubtitleAsVtt(link: string): Promise<string | null> {
  const trimmed = link.trim();
  if (!/^https?:\/\//i.test(trimmed)) return null;
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 12_000);
    const response = await fetch(trimmed, { signal: controller.signal, redirect: "follow" });
    clearTimeout(timer);
    if (!response.ok) return null;
    const text = await response.text();
    if (!text.trim()) return null;
    return toWebVTT(text);
  } catch {
    return null;
  }
}

/** Link phụ đề gốc của một tập, dùng khi máy chủ không tải được phụ đề. */
export async function movieSubtitleFallbackUrl(episodeId: number): Promise<string | null> {
  const db = await getDb();
  if (!db) return null;
  const [row] = await db.select().from(movieSourceEpisodes).where(eq(movieSourceEpisodes.id, episodeId));
  const link = row?.subtitleUrl?.trim();
  return link && /^https?:\/\//i.test(link) ? link : null;
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
  if (row.subtitleUrl) return fetchSubtitleAsVtt(row.subtitleUrl);
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
        streamUrl: registerCustomStreamSource(episode.qualities[0]?.streamUrl ?? episode.streamUrl),
        directStreamUrl: customDirectStreamUrl(episode.qualities[0]?.streamUrl ?? episode.streamUrl),
        subtitleUrl: episode.qualities[0]?.subtitleUrl ?? episode.subtitleUrl,
        // Danh sách chất lượng để app cho người xem chọn 1080p / 2K / 4K…
        qualities: episode.qualities.length
          ? episode.qualities.map((quality) => ({
              label: quality.label,
              streamUrl: registerCustomStreamSource(quality.streamUrl),
              directStreamUrl: customDirectStreamUrl(quality.streamUrl),
              subtitleUrl: quality.subtitleUrl,
            }))
          : undefined,
      })),
    });
  }
  return merged;
}