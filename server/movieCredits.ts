/**
 * Lấy diễn viên và đạo diễn của một phim theo TMDB ID hoặc IMDB ID.
 *
 * Trang quản trị chỉ cần nhập một trong hai mã là có sẵn danh sách diễn viên kèm ảnh
 * và tên đạo diễn, thay vì gõ tay từng người.
 *
 * - TMDB ID: gọi thẳng `movie/{id}/credits`; nếu không có thì thử `tv/{id}/credits`
 *   (phim bộ nằm ở nhánh TV của TMDB) và lấy thêm `created_by` làm đạo diễn.
 * - IMDB ID (`tt…`): tra qua `find/{id}?external_source=imdb_id` để đổi sang TMDB ID
 *   rồi làm như trên.
 *
 * Kết quả nhớ tạm 10 phút để không gọi nguồn ngoài quá nhiều lần.
 */

import { tmdbGet } from "./actorSearch";

export type MovieCreditActor = { name: string; image: string };

export type MovieCreditsResult = {
  title: string;
  directors: string[];
  actors: MovieCreditActor[];
  notice: string | null;
};

const CACHE_TTL_MS = 10 * 60 * 1000;
/** Phim bộ có thể có hàng chục đạo diễn cho từng tập — chỉ giữ nhóm chính. */
const DIRECTOR_LIMIT = 6;
/** Ngôn ngữ khi đọc credits: en-US cho tên người dạng Latin, dễ đọc và dễ tìm lại. */
const CREDITS_LANGUAGE = "en-US";
const CACHE_MAX = 80;
const cache = new Map<string, { at: number; result: MovieCreditsResult }>();

type AnyRecord = Record<string, unknown>;

function str(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function num(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() !== "" && !Number.isNaN(Number(value))) return Number(value);
  return null;
}

function record(value: unknown): AnyRecord | null {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as AnyRecord) : null;
}

function records(value: unknown): AnyRecord[] {
  return Array.isArray(value) ? value.map(record).filter((item): item is AnyRecord => item !== null) : [];
}

function profileUrl(value: unknown): string {
  const path = str(value);
  return path ? `https://image.tmdb.org/t/p/w185${path}` : "";
}

/** TMDB ID chỉ nhận dạng số; IMDB ID nhận dạng tt… (hoặc số trần cũng quy về tt). */
function cleanTmdbId(value: string): string {
  return value.replace(/[^0-9]/g, "");
}

function cleanImdbId(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) return "";
  if (/^tt\d+$/i.test(trimmed)) return trimmed.toLowerCase();
  const digits = trimmed.replace(/[^0-9]/g, "");
  return digits ? `tt${digits}` : "";
}

/** Đổi IMDB ID sang TMDB ID bằng endpoint find của TMDB. */
async function resolveTmdbIdFromImdb(imdbId: string): Promise<{ id: string; mediaType: "movie" | "tv" } | null> {
  const payload = record(await tmdbGet(`/find/${encodeURIComponent(imdbId)}`, { external_source: "imdb_id" }));
  if (!payload) return null;
  const movie = records(payload.movie_results)[0];
  const movieId = num(movie?.id);
  if (movieId) return { id: String(movieId), mediaType: "movie" };
  const tv = records(payload.tv_results)[0];
  const tvId = num(tv?.id);
  if (tvId) return { id: String(tvId), mediaType: "tv" };
  return null;
}

function collectFromCredits(payload: AnyRecord, limit: number): { directors: string[]; actors: MovieCreditActor[] } {
  // Phim bộ gom đạo diễn của mọi tập, nên cân theo số tập đã làm rồi chỉ giữ nhóm chính.
  const ranked: Array<{ name: string; weight: number }> = [];
  for (const person of records(payload.crew)) {
    const job = str(person.job);
    // Phim bộ không ghi job Director, TMDB dùng Creator cho người tạo.
    // Riêng dạng aggregate_credits gom nhiều job vào mảng `jobs` cho từng người.
    const jobs = records(person.jobs).map(item => str(item.job));
    const isCreator = job === "Creator" || jobs.includes("Creator");
    const isDirector = job === "Director" || jobs.includes("Director") || isCreator;
    if (!isDirector) continue;
    const name = str(person.name);
    if (!name) continue;
    const episodes = num(person.total_episode_count) ?? 0;
    const weight = isCreator ? episodes + 1000 : episodes;
    const existing = ranked.find(item => item.name === name);
    if (existing) existing.weight = Math.max(existing.weight, weight);
    else ranked.push({ name, weight });
  }
  const directors = ranked
    .sort((a, b) => b.weight - a.weight)
    .slice(0, DIRECTOR_LIMIT)
    .map(item => item.name);
  const actors: MovieCreditActor[] = [];
  for (const person of records(payload.cast)) {
    const name = str(person.name) || str(person.original_name);
    if (!name || actors.some(actor => actor.name === name)) continue;
    actors.push({ name, image: profileUrl(person.profile_path) });
    if (actors.length >= limit) break;
  }
  return { directors, actors };
}

/** Rút gọn tiêu đề để so khớp (bỏ dấu, khoảng trắng và dấu câu, giữ mọi hệ chữ). */
function normalizeTitle(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/đ/g, "d")
    .replace(/Đ/g, "D")
    .toLowerCase()
    .replace(/[\s.,'’"“”\-–—_:;!?()\[\]{}·•/\\|@#$%^&*+=~`<>]+/g, "");
}

/** Điểm khớp tiêu đề: trùng hẳn 3, chứa nhau 2, không khớp 0. */
function titleScore(candidate: string, wanted: string): number {
  const a = normalizeTitle(candidate);
  const b = normalizeTitle(wanted);
  if (!a || !b) return 0;
  if (a === b) return 3;
  if (a.includes(b) || b.includes(a)) return 2;
  return 0;
}

type LoadedCredits = { mediaType: "movie" | "tv"; title: string; directors: string[]; actors: MovieCreditActor[] };

/** Lấy credits của đúng một nhánh movie/tv. */
async function loadOneCredits(
  mediaType: "movie" | "tv",
  id: string,
  limit: number,
): Promise<LoadedCredits | null> {
  // Phim bộ: /credits của TMDB chỉ trả vài người (đôi khi đúng 2), danh sách đầy đủ
  // như trên web TMDB nằm ở /aggregate_credits — gom diễn viên của mọi mùa.
  const encoded = encodeURIComponent(id);
  const paths =
    mediaType === "tv"
      ? [`/tv/${encoded}/aggregate_credits`, `/tv/${encoded}/credits`]
      : [`/movie/${encoded}/credits`];

  let best: { directors: string[]; actors: MovieCreditActor[] } | null = null;
  for (const path of paths) {
    try {
      const payload = record(await tmdbGet(path, { language: CREDITS_LANGUAGE }));
      if (!payload) continue;
      const collected = collectFromCredits(payload, limit);
      // Giữ bản nhiều diễn viên nhất giữa các đường.
      if (!best || collected.actors.length > best.actors.length) best = collected;
    } catch {
      /* thử đường còn lại */
    }
  }
  if (!best || (best.actors.length === 0 && best.directors.length === 0)) return null;

  let title = "";
  try {
    // Tiêu đề dùng để đối chiếu với ô Tên phim: lấy bản tiếng Anh cho khớp tên quốc tế.
    const detail = record(await tmdbGet(`/${mediaType}/${encoded}`, { language: CREDITS_LANGUAGE }));
    title = str(detail?.title) || str(detail?.name);
    // Người tạo phim bộ đứng đầu danh sách đạo diễn.
    for (const person of records(detail?.created_by)) {
      const name = str(person.name);
      if (name && !best.directors.includes(name)) best.directors.unshift(name);
    }
    best.directors = best.directors.slice(0, DIRECTOR_LIMIT);
  } catch {
    /* thiếu phần chi tiết cũng không sao, chỉ cần credits */
  }
  return { mediaType, title, directors: best.directors, actors: best.actors };
}

/**
 * Đọc credits của phim.
 *
 * Mã số TMDB có thể trùng nhau giữa nhánh phim lẻ và phim bộ, nên khi biết tên phim
 * thì đọc cả hai nhánh rồi chọn bản khớp tên nhất — tránh trường hợp lấy nhầm phim
 * khác chỉ có vài diễn viên và không có đạo diễn.
 */
async function loadCredits(
  id: string,
  preferred: "movie" | "tv" | null,
  limit: number,
  wantedTitle: string,
): Promise<LoadedCredits | null> {
  const order: Array<"movie" | "tv"> = preferred ? [preferred, preferred === "movie" ? "tv" : "movie"] : ["movie", "tv"];
  const loaded: LoadedCredits[] = [];
  let lastError: unknown = null;
  for (const mediaType of order) {
    try {
      const one = await loadOneCredits(mediaType, id, limit);
      if (one) loaded.push(one);
    } catch (error) {
      // Giữ lại lỗi thật (thiếu khoá TMDB, mạng hỏng…) để báo đúng cho quản trị viên.
      lastError = error;
    }
  }
  if (loaded.length === 0 && lastError) {
    throw lastError instanceof Error ? lastError : new Error("Không gọi được TMDB");
  }
  if (loaded.length === 0) return null;

  const wanted = normalizeTitle(wantedTitle);
  if (wanted) {
    let best = loaded[0];
    let bestScore = titleScore(best.title, wantedTitle);
    for (const item of loaded.slice(1)) {
      const score = titleScore(item.title, wantedTitle);
      if (score > bestScore) {
        best = item;
        bestScore = score;
      }
    }
    if (bestScore > 0) return best;
  }

  // Không đối chiếu được tên (ô Tên phim trống, hoặc tên không khớp cả hai nhánh):
  // nhánh ưu tiên có thể chỉ là phim trùng số nên chọn nhánh đầy đủ dữ liệu hơn hẳn.
  const preferredFirst = loaded[0];
  const richest = [...loaded].sort((a, b) => b.actors.length - a.actors.length)[0];
  if (richest !== preferredFirst && richest.actors.length >= Math.max(5, preferredFirst.actors.length * 3)) {
    return richest;
  }
  return preferredFirst;
}

export async function fetchMovieCredits(input: {
  tmdbId?: string | null;
  imdbId?: string | null;
  limit?: number;
  movieType?: "series" | "single" | null;
  title?: string | null;
}): Promise<MovieCreditsResult> {
  const limit = Math.min(Math.max(input.limit ?? 30, 1), 60);
  const tmdbId = cleanTmdbId(str(input.tmdbId));
  const imdbId = cleanImdbId(str(input.imdbId));
  const wantedTitle = str(input.title);
  if (!tmdbId && !imdbId) throw new Error("Cần TMDB ID hoặc IMDB ID để lấy diễn viên và đạo diễn");

  const key = `${tmdbId}|${imdbId}|${limit}|${str(input.movieType)}|${wantedTitle}`;
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < CACHE_TTL_MS) return hit.result;

  let resolvedId = tmdbId;
  let preferred: "movie" | "tv" | null = null;
  if (!resolvedId) {
    const found = await resolveTmdbIdFromImdb(imdbId);
    if (!found) {
      throw new Error(`Không tìm thấy phim với IMDB ID ${imdbId} trên TMDB`);
    }
    resolvedId = found.id;
    preferred = found.mediaType;
  }

  // Loại phim trong form giúp chọn đúng nhánh khi mã số trùng nhau.
  if (!preferred && input.movieType) preferred = input.movieType === "series" ? "tv" : "movie";

  const loaded = await loadCredits(resolvedId, preferred, limit, wantedTitle);
  if (!loaded) {
    throw new Error(`TMDB không có dữ liệu diễn viên cho mã ${resolvedId}`);
  }

  const result: MovieCreditsResult = {
    title: loaded.title,
    directors: loaded.directors,
    actors: loaded.actors,
    notice:
      loaded.actors.length === 0
        ? "TMDB chưa có danh sách diễn viên cho phim này."
        : loaded.directors.length === 0
          ? "TMDB chưa ghi đạo diễn cho phim này — bạn có thể thêm tay ở ô Đạo diễn."
          : null,
  };
  cache.set(key, { at: Date.now(), result });
  if (cache.size > CACHE_MAX) {
    const oldest = cache.keys().next().value;
    if (oldest) cache.delete(oldest);
  }
  return result;
}
