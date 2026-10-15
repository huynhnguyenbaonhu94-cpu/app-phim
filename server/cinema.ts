import { randomUUID } from "node:crypto";
import { TRPCError } from "@trpc/server";
import { mergeCustomSources } from "./movieSources";
import {
  customMoviesForFilter,
  getCustomMovieBySlug,
  getCustomMovieDetail,
  registerCustomMovieView,
  searchCustomMovies,
} from "./customMovies";

const API_BASE = "https://phimapi.com";
const IMAGE_BASE = "https://phimimg.com/";
export const MAX_CINEMA_PAGE = 2_000;
const PUBLIC_BASE_URL = (process.env.PUBLIC_BASE_URL || "").replace(/\/+$/, "");
function apiRoute(path: string) { return PUBLIC_BASE_URL ? `${PUBLIC_BASE_URL}${path}` : path; }
const CACHE_TTL = 300_000; // 5 min — reduces token churn
const cache = new Map<string, { expires: number; value: unknown }>();
const pendingRequests = new Map<string, Promise<unknown>>();
const allowedImageHosts = new Set(["phimimg.com", "www.phimimg.com", "phimapi.com", "www.phimapi.com", "image.tmdb.org"]);
const allowedEmbedHosts = new Set(["player.phimapi.com"]);
// PhimAPI có thể luân phiên các CDN HLS. Chỉ cho phép các domain CDN đã biết,
// không mở proxy tới hostname tùy ý từ dữ liệu upstream.
const allowedStreamHosts = new Set(["cdn-player.com", "kvp726.com", "kkphimplayer6.com", "kkphimplayer7.com", "phim1280.tv"]);
const imageTokens = new Map<string, { url: string; expires: number }>();
const sourceImageTokens = new Map<string, { token: string; expires: number }>();
const embedTokens = new Map<string, { url: string; expires: number }>();
const streamTokens = new Map<string, { url: string; expires: number }>();

export type Movie = {
  id: string; slug: string; name: string; originName: string; poster: string | null; backdrop: string | null;
  year: number | null; quality: string; episodeCurrent: string; episodeTotal: number | null; time: string;
  lang: string; type: string; description: string; rating: number | null; categories: Array<{ name: string; slug: string }>; countries: Array<{ name: string; slug: string }>;
  alternativeNames: string[]; actors: string[]; directors: string[]; status: string; views: number | null;
  isCopyright: boolean; isTheatrical: boolean; trailerUrl: string | null; tmdbId: string | null; imdbId: string | null;
  createdAt: string | null; updatedAt: string | null;
};
export type MovieEpisodeQuality = { label: string; streamUrl: string | null; directStreamUrl: string | null; subtitleUrl: string | null };
export type MovieDetail = Movie & { servers: Array<{ name: string; isAi: boolean; episodes: Array<{ name: string; slug: string; filename: string; embedUrl: string | null; streamUrl: string | null; directStreamUrl: string | null; subtitleUrl?: string | null; qualities?: MovieEpisodeQuality[] }> }>; actorProfiles?: Array<{ name: string; image: string | null }> };

function cleanText(value: unknown, fallback = "") {
  if (typeof value !== "string") return fallback;
  return value.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim().slice(0, 680);
}
function cleanContent(value: unknown, fallback = "") {
  if (typeof value !== "string") return fallback;
  return value.replace(/<br\s*\/?>(?=\S)/gi, "\n").replace(/<\/p>\s*<p>/gi, "\n\n").replace(/<[^>]*>/g, "").replace(/&nbsp;/gi, " ").replace(/&amp;/gi, "&").replace(/&quot;/gi, '"').replace(/&#39;/gi, "'").replace(/[ \t]+/g, " ").replace(/\n[ \t]+/g, "\n").trim();
}

function resolveImage(value: unknown, pathImage?: string) {
  if (typeof value !== "string" || !value.trim()) return null;
  try {
    const raw = value.trim();
    const base = raw.startsWith("upload/") || raw.startsWith("/upload/") ? IMAGE_BASE : raw.startsWith("uploads/") || raw.startsWith("/uploads/") ? "https://phimapi.com/" : (pathImage || "https://phimapi.com/uploads/movies/");
    const url = new URL(raw, base);
    // Nhiều nguồn cũ trả ảnh http://. App iOS chặn http (ATS) nên đổi sang https
    // trước khi kiểm tra, thay vì loại bỏ và để phim trắng poster.
    if (url.protocol === "http:") url.protocol = "https:";
    if (url.protocol !== "https:" || !isAllowedImageHost(url.hostname)) return null;
    return url.toString();
  } catch { return null; }
}

function isAllowedImageHost(hostname: string) {
  const host = hostname.toLowerCase();
  return Array.from(allowedImageHosts).some((allowed) => host === allowed || host.endsWith(`.${allowed}`));
}

/**
 * Token ảnh chính là URL nguồn được mã hoá base64url. Nhờ vậy token không hết
 * hạn: trước đây token sống 2 giờ nên danh sách phim tải về lúc sáng, tới chiều
 * là hàng loạt poster trắng dù API vẫn trả đúng đường dẫn.
 */
function encodeImageToken(source: string) {
  return Buffer.from(source, "utf8").toString("base64url");
}

function decodeImageToken(token: string) {
  try {
    const source = Buffer.from(token, "base64url").toString("utf8");
    const url = new URL(source);
    if (url.protocol !== "https:" || !isAllowedImageHost(url.hostname)) return null;
    return url.toString();
  } catch { return null; }
}

function registerImageSource(source: string | null) {
  if (!source) return null;
  if (sourceImageTokens.size > 5_500) {
    const now = Date.now();
    for (const [cachedSource, entry] of Array.from(sourceImageTokens.entries())) {
      if (entry.expires <= now || !imageTokens.has(entry.token)) {
        sourceImageTokens.delete(cachedSource);
        imageTokens.delete(entry.token);
      }
    }
    while (sourceImageTokens.size > 5_000) {
      const oldest = sourceImageTokens.keys().next().value as string | undefined;
      if (!oldest) break;
      const entry = sourceImageTokens.get(oldest);
      if (entry) imageTokens.delete(entry.token);
      sourceImageTokens.delete(oldest);
    }
  }
  return apiRoute(`/api/cinema/image/${encodeImageToken(source)}`);
}

function imageUrl(value: unknown, pathImage?: string) { return registerImageSource(resolveImage(value, pathImage)); }

function embedUrl(value: unknown) {
  if (typeof value !== "string" || !value.trim()) return null;
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || !allowedEmbedHosts.has(url.hostname)) return null;
    const token = randomUUID().replaceAll("-", "");
    embedTokens.set(token, { url: url.toString(), expires: Date.now() + 120 * 60_000 }); // 2h TTL
    return apiRoute(`/api/cinema/player/${token}`);
  } catch { return null; }
}

export function getImageSource(token: string) {
  const stateless = decodeImageToken(token);
  if (stateless) return stateless;
  // Token cũ (ngẫu nhiên, có hạn) vẫn phải chạy để không phá link đang lưu.
  const entry = imageTokens.get(token);
  if (!entry || entry.expires < Date.now()) { imageTokens.delete(token); return null; }
  return entry.url;
}
export function getEmbedSource(token: string) {
  const entry = embedTokens.get(token);
  if (!entry || entry.expires < Date.now()) { embedTokens.delete(token); return null; }
  return entry.url;
}
export function getStreamSource(token: string) {
  const entry = streamTokens.get(token);
  if (!entry || entry.expires < Date.now()) { streamTokens.delete(token); return null; }
  return entry.url;
}

export function protectImageSource(value: string | null | undefined) {
  if (!value) return null;
  let pathname = value;
  try { pathname = new URL(value).pathname; } catch { /* Keep relative route as-is. */ }
  if (pathname.startsWith("/api/cinema/image/")) return registerImageSource(getImageSource(pathname.split("/").pop() || ""));
  return registerImageSource(resolveImage(value));
}

export function registerStreamSource(value: string) {
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || !Array.from(allowedStreamHosts).some((host) => url.hostname === host || url.hostname.endsWith(`.${host}`))) return null;
    const token = randomUUID().replaceAll("-", "");
    streamTokens.set(token, { url: url.toString(), expires: Date.now() + 6 * 60 * 60_000 });
    return apiRoute(`/api/cinema/stream/${token}`);
  } catch { return null; }
}

/**
 * Dùng riêng cho URI nằm trong playlist đã tải về (biến thể, khoá giải mã,
 * segment). Vẫn bắt buộc https nhưng cho phép host ngoài danh sách CDN đã biết,
 * vì nhiều nguồn trỏ sang host phụ. Token chỉ do máy chủ tạo từ playlist nên
 * bên ngoài không thể lợi dụng proxy để gọi host tuỳ ý.
 */
export function registerStreamSourceFromPlaylist(value: string) {
  try {
    const url = new URL(value);
    if (url.protocol !== "https:") return null;
    const token = randomUUID().replaceAll("-", "");
    streamTokens.set(token, { url: url.toString(), expires: Date.now() + 6 * 60 * 60_000 });
    return apiRoute(`/api/cinema/stream/${token}`);
  } catch { return null; }
}

function streamUrl(value: unknown) {
  if (typeof value !== "string" || !value.trim()) return null;
  return registerStreamSource(value.trim());
}

function streamUrlFromEmbed(value: unknown) {
  if (typeof value !== "string" || !value.trim()) return null;
  try {
    const embed = new URL(value.trim());
    if (!allowedEmbedHosts.has(embed.hostname)) return null;
    const nested = embed.searchParams.get("url");
    return nested ? streamUrl(nested) : null;
  } catch { return null; }
}

/**
 * Link M3U8 gốc, không qua proxy. Trình phát web thử link này trước vì nhiều CDN
 * chặn máy chủ nhưng cho trình duyệt tải bình thường; nếu lỗi thì mới quay về proxy.
 */
function directStreamUrl(value: unknown) {
  if (typeof value !== "string" || !value.trim()) return null;
  try {
    const url = new URL(value.trim());
    const allowed = url.protocol === "https:" && Array.from(allowedStreamHosts).some((host) => url.hostname === host || url.hostname.endsWith(`.${host}`));
    return allowed ? url.toString() : null;
  } catch { return null; }
}

function directStreamUrlFromEmbed(value: unknown) {
  if (typeof value !== "string" || !value.trim()) return null;
  try {
    const embed = new URL(value.trim());
    if (!allowedEmbedHosts.has(embed.hostname)) return null;
    return directStreamUrl(embed.searchParams.get("url"));
  } catch { return null; }
}

function ratingValue(item: any) {
  const value = Number(item?.tmdb?.vote_average ?? item?.imdb?.vote_average ?? item?.rating ?? item?.score ?? 0);
  return Number.isFinite(value) && value > 0 ? Math.round(value * 10) / 10 : null;
}
function safeDate(value: unknown) {
  return typeof value === "string" && !Number.isNaN(Date.parse(value)) ? value : null;
}
function firstDate(...values: unknown[]) {
  for (const value of values) {
    const date = safeDate(value);
    if (date) return date;
  }
  return null;
}
function stringList(...values: unknown[]) {
  const value = values.find((candidate) => Array.isArray(candidate) || typeof candidate === "string");
  if (Array.isArray(value)) return value.map((x) => cleanText(x)).filter(Boolean);
  return typeof value === "string" ? value.split(/[,|]/).map((x) => cleanText(x)).filter(Boolean) : [];
}
function normalizeMovie(item: any, pathImage?: string): Movie {
  const poster = imageUrl(item?.poster_url, pathImage) || imageUrl(item?.thumb_url, pathImage);
  const backdrop = imageUrl(item?.thumb_url, pathImage) || poster;
  return {
    id: String(item?._id || item?.slug || "unknown"), slug: String(item?.slug || ""), name: cleanText(item?.name, "Chưa có tên"), originName: cleanText(item?.origin_name), poster, backdrop,
    year: Number.isFinite(Number(item?.year)) ? Number(item.year) : null, quality: cleanText(item?.quality, "HD"), episodeCurrent: cleanText(item?.episode_current, "Đang cập nhật"), episodeTotal: Number.isFinite(Number(item?.episode_total)) ? Number(item.episode_total) : null,
    time: cleanText(item?.time), lang: cleanText(item?.lang, "Vietsub"), type: cleanText(item?.type), description: cleanContent(item?.content, "Một hành trình điện ảnh đang chờ bạn khám phá."), rating: ratingValue(item),
    categories: Array.isArray(item?.category ?? item?.categories) ? (item.category ?? item.categories).map((x: any) => ({ name: cleanText(x?.name ?? x), slug: cleanText(x?.slug ?? x?.name ?? x) })).filter((x: any) => x.name) : [], countries: Array.isArray(item?.country ?? item?.countries) ? (item.country ?? item.countries).map((x: any) => ({ name: cleanText(x?.name ?? x), slug: cleanText(x?.slug ?? x?.name ?? x) })).filter((x: any) => x.name) : [],
    alternativeNames: stringList(item?.alternative_names, item?.alternativeNames),
    actors: stringList(item?.actor, item?.actors),
    directors: stringList(item?.director, item?.directors),
    status: cleanText(item?.status), views: Number.isFinite(Number(item?.view ?? item?.views ?? item?.view_count)) ? Number(item?.view ?? item?.views ?? item?.view_count) : null,
    isCopyright: Boolean(item?.is_copyright ?? item?.isCopyright), isTheatrical: Boolean(item?.chieurap ?? item?.isTheatrical),
    trailerUrl: typeof (item?.trailer_url ?? item?.trailerUrl) === "string" ? (item.trailer_url ?? item.trailerUrl) : null,
    tmdbId: item?.tmdb?.id ?? item?.tmdb_id ?? item?.tmdbId ? String(item?.tmdb?.id ?? item?.tmdb_id ?? item?.tmdbId) : null, imdbId: item?.imdb?.id ?? item?.imdb_id ?? item?.imdbId ? String(item?.imdb?.id ?? item?.imdb_id ?? item?.imdbId) : null,
    createdAt: firstDate(item?.created?.time, item?.created_at, item?.createdAt), updatedAt: firstDate(item?.modified?.time, item?.updated_at, item?.updatedAt),
  };
}
function unwrapItems(payload: any) {
  const data = payload?.data ?? payload;
  return { items: Array.isArray(data?.items) ? data.items : [], pagination: data?.params?.pagination ?? payload?.pagination ?? null, pathImage: payload?.pathImage ?? data?.pathImage };
}
async function upstream(path: string, query: Record<string, string | number | undefined> = {}, options: { bypassCache?: boolean } = {}) {
  const params = new URLSearchParams();
  Object.entries(query).forEach(([key, value]) => { if (value !== undefined && value !== "") params.set(key, String(value)); });
  const url = `${API_BASE}${path}${params.size ? `?${params.toString()}` : ""}`;
  const cached = cache.get(url);
  if (!options.bypassCache && cached && cached.expires > Date.now()) return cached.value as any;
  const pending = pendingRequests.get(url);
  if (pending) return pending as Promise<any>;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8_000);
  const request = (async () => {
    try {
      const response = await fetch(url, { headers: { accept: "application/json", "user-agent": "Cinemora/1.0" }, signal: controller.signal });
      if (!response.ok) throw new Error(`Upstream ${response.status}`);
      const json = await response.json();
      cache.set(url, { expires: Date.now() + CACHE_TTL, value: json });
      return json;
    } catch (error) {
      console.error("[cinema] upstream request failed", error instanceof Error ? error.message : "unknown");
      throw new TRPCError({ code: "BAD_GATEWAY", message: "Nguồn phim đang bận. Vui lòng thử lại sau ít phút." });
    } finally {
      clearTimeout(timeout);
      pendingRequests.delete(url);
    }
  })();
  pendingRequests.set(url, request);
  return request;
}
function safePage(page?: number) { return Math.min(MAX_CINEMA_PAGE, Math.max(1, Math.floor(page || 1))); }
function safeSlug(value: string) {
  if (!/^[a-z0-9-]{2,120}$/i.test(value)) throw new TRPCError({ code: "BAD_REQUEST", message: "Mã phim không hợp lệ." });
  return value;
}
function safeFilterSlug(value: string) {
  if (!/^[a-z0-9-]{2,80}$/i.test(value)) throw new TRPCError({ code: "BAD_REQUEST", message: "Bộ lọc không hợp lệ." });
  return value;
}

export async function getPersistentPosterSource(slug: string, publicPosterUrl?: string | null) {
  if (publicPosterUrl?.startsWith("/api/cinema/image/")) {
    const source = getImageSource(publicPosterUrl.split("/").pop() || "");
    if (source) return source;
  }
  const payload = await getMoviePayload(slug);
  const item = payload?.data?.item ?? payload?.movie;
  return resolveImage(item?.poster_url || item?.thumb_url, payload?.pathImage);
}

async function getMoviePayload(rawSlug: string) {
  const slug = safeSlug(rawSlug);
  try {
    const v1Payload = await upstream(`/v1/api/phim/${encodeURIComponent(slug)}`);
    if (v1Payload?.data?.item ?? v1Payload?.movie) return v1Payload;
  } catch (error) {
    console.warn("[cinema] v1 detail endpoint failed, trying legacy endpoint", error instanceof Error ? error.message : "unknown");
  }
  return upstream(`/phim/${encodeURIComponent(slug)}`);
}

async function getMoviePeople(slug: string) {
  try {
    const payload = await upstream(`/v1/api/phim/${encodeURIComponent(slug)}/peoples`);
    const data = payload?.data ?? payload;
    const sizes = data?.profile_sizes ?? {};
    const imageBase = typeof sizes.w185 === "string" ? sizes.w185 : "https://image.tmdb.org/t/p/w185";
    const people = Array.isArray(data?.peoples) ? data.peoples : [];
    return people
      .filter((person: any) => typeof person?.name === "string" && person.name.trim())
      .slice(0, 24)
      .map((person: any) => ({
        name: person.name.trim(),
        image: typeof person.profile_path === "string" && person.profile_path.trim()
          ? `${imageBase.replace(/\/$/, "")}/${person.profile_path.replace(/^\//, "")}`
          : null,
      }));
  } catch {
    return [] as Array<{ name: string; image: string | null }>;
  }
}

export async function getHome(page = 1) {
  const payload = await upstream("/v1/api/home", { page: safePage(page) });
  const { items, pagination, pathImage } = unwrapItems(payload);
  const apiItems = items.map((item: any) => normalizeMovie(item, pathImage));
  // Phim thủ công xuất hiện trên trang chủ của app như phim bình thường.
  const custom = safePage(page) === 1 ? await customMoviesForFilter({}) : [];
  if (custom.length === 0) return { items: apiItems, pagination };
  const seen = new Set(custom.map((movie) => movie.slug));
  return { items: [...custom, ...apiItems.filter((movie: Movie) => !seen.has(movie.slug))], pagination };
}
const listEndpoints: Record<string, string> = {
  latest: "/v1/api/danh-sach/phim-moi",
  single: "/v1/api/danh-sach/phim-le",
  series: "/v1/api/danh-sach/phim-bo",
  shows: "/v1/api/danh-sach/tv-shows",
  animation: "/v1/api/danh-sach/hoat-hinh",
  vietsub: "/v1/api/danh-sach/phim-vietsub",
  thuyetminh: "/v1/api/danh-sach/phim-thuyet-minh",
  longtieng: "/v1/api/danh-sach/phim-long-tieng",
  ongoing: "/v1/api/danh-sach/phim-bo",
  completed: "/v1/api/danh-sach/phim-bo",
  subteam: "/v1/api/danh-sach/subteam",
  theatrical: "/v1/api/danh-sach/phim-chieu-rap",
};
function isCompletedSeries(movie: Movie) {
  const marker = `${movie.status || ""} ${movie.episodeCurrent || ""}`.toLocaleLowerCase("vi-VN");
  if (/(hoàn tất|hoan tat|hoàn thành|hoan thanh|full|completed|complete|end)/i.test(marker)) return true;
  if (movie.episodeTotal && movie.episodeCurrent) {
    const numbers = movie.episodeCurrent.match(/\d+/g)?.map(Number) || [];
    const current = numbers[numbers.length - 1];
    if (current && current >= movie.episodeTotal) return true;
  }
  return false;
}
type MovieListResult = { items: Movie[]; pagination: ReturnType<typeof unwrapItems>["pagination"] };

export const MAX_FILTER_COMBOS = 12;
const PAGE_LIMIT = 24;

export type MovieFilterInput = {
  kind?: keyof typeof listEndpoints;
  page?: number;
  category?: string;
  country?: string;
  year?: number;
  refresh?: boolean;
  areas?: never;
  /** Lọc nhiều lựa chọn cùng lúc: ví dụ Phim Bộ + Phim Lẻ, nhiều thể loại… */
  kinds?: string[];
  categories?: string[];
  countries?: string[];
  years?: number[];
};

type Combo = { kind: keyof typeof listEndpoints; category?: string; country?: string; year?: number };

function uniqueStrings(values: string[]): string[] {
  return Array.from(new Set(values.map((value) => value.trim()).filter(Boolean)));
}

/**
 * Dựng danh sách tổ hợp lọc từ lựa chọn của người dùng.
 *
 * Quy ước: nhiều lựa chọn trong **cùng một nhóm** là HOẶC (Phim Bộ hoặc Phim Lẻ),
 * giữa các nhóm là VÀ (thuộc thể loại đã chọn VÀ thuộc quốc gia đã chọn…).
 * Mỗi tổ hợp là một truy vấn nguồn; kết quả được gộp và khử trùng theo slug.
 */
function buildCombos(input: MovieFilterInput): Combo[] {
  const kinds = uniqueStrings((input.kinds || []).filter((value) => value && value in listEndpoints)) as Array<keyof typeof listEndpoints>;
  const kindList: Array<keyof typeof listEndpoints> = kinds.length ? kinds : [input.kind ?? "latest"];
  const categories = uniqueStrings(input.categories?.length ? input.categories : input.category ? [input.category] : []);
  const countries = uniqueStrings(input.countries?.length ? input.countries : input.country ? [input.country] : []);
  const years = Array.from(
    new Set((input.years?.length ? input.years : input.year ? [input.year] : []).filter((value) => Number.isInteger(value)))
  );
  const categoryList: Array<string | undefined> = categories.length ? categories : [undefined];
  const countryList: Array<string | undefined> = countries.length ? countries : [undefined];
  const yearList: Array<number | undefined> = years.length ? years : [undefined];
  const combos: Combo[] = [];
  for (const kind of kindList) {
    for (const category of categoryList) {
      for (const country of countryList) {
        for (const year of yearList) {
          combos.push({ kind, category, country, year });
        }
      }
    }
  }
  return combos;
}

/**
 * Kiểm tra lại ngay tại máy chủ: phim trả về phải khớp đúng bộ lọc.
 *
 * API nguồn có những endpoint bỏ qua tham số lọc, nên bước này loại bỏ mọi phim
 * không đúng thể loại / quốc gia / năm đã chọn — nhờ vậy kết quả không bao giờ
 * "lọc mà ra phim khác".
 */
function matchesCombo(movie: Movie, combo: Combo): boolean {
  if (combo.category && !movie.categories.some((item) => item.slug === combo.category || item.name === combo.category)) return false;
  if (combo.country && !movie.countries.some((item) => item.slug === combo.country || item.name === combo.country)) return false;
  if (combo.year && movie.year !== combo.year) return false;
  return true;
}

/** Gọi nguồn cho đúng một tổ hợp lọc. */
async function listCombo(combo: Combo, page: number, refresh: boolean) {
  const endpoint = listEndpoints[combo.kind] ?? listEndpoints.latest;
  const payload = await upstream(
    endpoint,
    { page, limit: PAGE_LIMIT, category: combo.category, country: combo.country, year: combo.year },
    { bypassCache: refresh }
  );
  const { items, pagination, pathImage } = unwrapItems(payload);
  return {
    combo,
    items: (items as any[]).map((item) => normalizeMovie(item, pathImage)),
    pagination,
  };
}

export async function getMovies(input: MovieFilterInput): Promise<MovieListResult> {
  const combos = buildCombos(input);
  if (combos.length > MAX_FILTER_COMBOS) {
    throw new TRPCError({
      code: "BAD_REQUEST",
      message: `Bộ lọc đang có ${combos.length} tổ hợp. Hãy bớt lựa chọn (tối đa ${MAX_FILTER_COMBOS} tổ hợp).`,
    });
  }
  const page = safePage(input.page);
  const results = await Promise.all(combos.map((combo) => listCombo(combo, page, Boolean(input.refresh))));

  const seen = new Set<string>();
  const merged: Movie[] = [];
  for (const result of results) {
    for (const movie of result.items) {
      if (!movie.slug || seen.has(movie.slug)) continue;
      if (!matchesCombo(movie, result.combo)) continue;
      seen.add(movie.slug);
      merged.push(movie);
    }
  }
  // Phim admin thêm thủ công được trộn vào danh sách, ưu tiên theo thời gian cập nhật.
  if (page === 1) {
    const custom = await customMoviesForFilter({
      kinds: uniqueStrings((input.kinds || []).filter((value) => value && value in listEndpoints)),
      categories: uniqueStrings(input.categories?.length ? input.categories : input.category ? [input.category] : []),
      countries: uniqueStrings(input.countries?.length ? input.countries : input.country ? [input.country] : []),
      years: Array.from(new Set((input.years?.length ? input.years : input.year ? [input.year] : []).filter((value) => Number.isInteger(value)))),
    });
    for (const movie of custom) {
      if (!movie.slug || seen.has(movie.slug)) continue;
      seen.add(movie.slug);
      merged.push(movie);
    }
  }
  merged.sort((a, b) => String(b.updatedAt ?? "").localeCompare(String(a.updatedAt ?? "")));

  const kindKey = combos[0]?.kind ?? "latest";
  const filtered =
    kindKey === "ongoing"
      ? merged.filter((movie) => !isCompletedSeries(movie))
      : kindKey === "completed"
        ? merged.filter(isCompletedSeries)
        : merged;

  // Một tổ hợp: nguồn cho số liệu chính xác (tổng số phim, tổng số trang).
  // Nhiều tổ hợp: không có tổng chính xác nên trả `null` thay vì con số sai.
  const pagination =
    results.length === 1
      ? results[0].pagination
      : {
          currentPage: page,
          totalItems: null,
          totalPages: null,
          itemsPerPage: filtered.length,
          hasNextPage: results.some((result) => {
            const info: any = result.pagination ?? {};
            if (typeof info.hasNextPage === "boolean") return info.hasNextPage;
            const total = Number(info.totalItems);
            if (Number.isFinite(total) && total > 0) return total > page * PAGE_LIMIT;
            return result.items.length >= PAGE_LIMIT;
          }),
        };

  return { items: filtered, pagination };
}

export type FilterDimension = "categories" | "countries" | "years";

/**
 * Đếm số phim của từng lựa chọn trong một nhóm lọc.
 *
 * Mỗi lựa chọn được đếm bằng một truy vấn chỉ có một giá trị cho mỗi nhóm, nên
 * `totalItems` của nguồn là con số chính xác (đã trừ các lựa chọn khác đang bật).
 */
export async function getFilterCounts(
  input: MovieFilterInput & { dimension: FilterDimension; options: string[] }
): Promise<Record<string, number>> {
  const options = uniqueStrings(input.options).slice(0, 24);
  if (options.length === 0) return {};
  const kind = uniqueStrings((input.kinds || []).filter((value) => value && value in listEndpoints))[0] as
    | keyof typeof listEndpoints
    | undefined;
  const base: Combo = {
    kind: kind ?? input.kind ?? "latest",
    category: uniqueStrings(input.categories?.length ? input.categories : input.category ? [input.category] : [])[0],
    country: uniqueStrings(input.countries?.length ? input.countries : input.country ? [input.country] : [])[0],
    year: (input.years?.length ? input.years : input.year ? [input.year] : [])[0],
  };

  const entries = await Promise.all(
    options.map(async (option) => {
      const combo: Combo = { ...base };
      if (input.dimension === "categories") combo.category = option;
      else if (input.dimension === "countries") combo.country = option;
      else {
        const value = Number.parseInt(option, 10);
        if (!Number.isFinite(value)) return null;
        combo.year = value;
      }
      try {
        const result = await listCombo(combo, 1, false);
        const total = Number((result.pagination as any)?.totalItems);
        return Number.isFinite(total) ? ([option, total] as [string, number]) : null;
      } catch {
        return null;
      }
    })
  );

  const counts: Record<string, number> = {};
  for (const entry of entries) {
    if (entry) counts[entry[0]] = entry[1];
  }
  return counts;
}

export async function searchMovies(input: { keyword: string; page?: number }) {
  const keyword = input.keyword.trim().slice(0, 80);
  if (keyword.length < 2) return { items: [], pagination: null };
  const payload = await upstream("/v1/api/tim-kiem", { keyword, page: safePage(input.page), limit: 24 });
  const { items, pagination, pathImage } = unwrapItems(payload);
  const apiItems = items.map((item: any) => normalizeMovie(item, pathImage));
  // Phim admin thêm thủ công cũng phải tìm thấy được, và đứng trước kết quả API.
  const custom = safePage(input.page) === 1 ? await searchCustomMovies(keyword) : [];
  const seen = new Set(custom.map((movie) => movie.slug));
  return {
    items: [...custom, ...apiItems.filter((movie: Movie) => !seen.has(movie.slug))],
    pagination,
  };
}
export async function getMovieDetail(rawSlug: string): Promise<MovieDetail> {
  const slug = safeSlug(rawSlug);
  // Phim thủ công có slug riêng: trả về ngay, kèm nguồn/tập admin đã thêm.
  const custom = await getCustomMovieBySlug(rawSlug.trim() || slug);
  if (custom && custom.isPublished) {
    const detail = await getCustomMovieDetail(custom.slug);
    if (detail) {
      void registerCustomMovieView(custom.slug);
      return detail;
    }
  }
  const payload = await getMoviePayload(slug);
  const item = payload?.data?.item ?? payload?.movie ?? null;
  if (!item) throw new TRPCError({ code: "NOT_FOUND", message: "Không tìm thấy bộ phim này." });
  const movie = normalizeMovie(item, payload?.pathImage);
  const rawServers = item?.episodes ?? payload?.episodes ?? [];
  const servers = Array.isArray(rawServers) ? rawServers.map((server: any) => ({ name: cleanText(server?.server_name, "Nguồn phim"), isAi: Boolean(server?.is_ai), episodes: Array.isArray(server?.server_data) ? server.server_data.map((episode: any) => {
    const embed = embedUrl(episode?.link_embed);
    const stream = streamUrl(episode?.link_m3u8) || streamUrlFromEmbed(episode?.link_embed);
    const direct = directStreamUrl(episode?.link_m3u8) || directStreamUrlFromEmbed(episode?.link_embed);
    return { name: cleanText(episode?.name, "Tập phim"), slug: cleanText(episode?.slug), filename: cleanText(episode?.filename), embedUrl: embed, streamUrl: stream, directStreamUrl: direct };
  }).filter((episode: any) => episode.slug) : [] })).filter((server: any) => server.episodes.length > 0) : [];
  const actorProfiles = await getMoviePeople(slug);
  // Nguồn và tập do admin thêm thủ công được ghép vào như nguồn bình thường.
  return { ...movie, actorProfiles, servers: await mergeCustomSources(rawSlug, servers) };
}
export async function getDailyUpdates(page = 1) {
  // Cache ngắn hơn (2 phút) vì đây là dữ liệu cập nhật liên tục trong ngày
  const path = "/v1/api/danh-sach/phim-moi";
  const query = { page: safePage(page), limit: 12, sort_field: "modified.time", sort_type: "desc" };
  const params = new URLSearchParams();
  Object.entries(query).forEach(([key, value]) => { if (value !== undefined) params.set(key, String(value)); });
  const url = `${API_BASE}${path}?${params.toString()}`;

  // Dùng cache riêng TTL 2 phút
  const DAILY_TTL = 120_000;
  const cached = cache.get(`daily:${url}`);
  if (cached && cached.expires > Date.now()) {
    const { items, pagination, pathImage } = unwrapItems(cached.value);
    return { items: items.map((item: any) => normalizeMovie(item, pathImage)), pagination };
  }
  const payload = await upstream(path, { ...query });
  cache.set(`daily:${url}`, { expires: Date.now() + DAILY_TTL, value: payload });
  const { items, pagination, pathImage } = unwrapItems(payload);
  return { items: items.map((item: any) => normalizeMovie(item, pathImage)), pagination };
}

export async function getCatalogMeta() {
  const [categories, countries, years] = await Promise.all([upstream("/the-loai"), upstream("/quoc-gia"), upstream("/nam-phat-hanh")]);
  const itemsOf = (payload: any) => {
    const items = payload?.data?.items ?? payload?.items ?? payload?.data ?? [];
    return Array.isArray(items) ? items : [];
  };
  return {
    categories: itemsOf(categories).map((x: any) => ({ name: cleanText(x?.name), slug: cleanText(x?.slug) })).filter((x: any) => x.name && x.slug),
    countries: itemsOf(countries).map((x: any) => ({ name: cleanText(x?.name), slug: cleanText(x?.slug) })).filter((x: any) => x.name && x.slug),
    years: itemsOf(years).map((x: any) => Number(typeof x === "object" ? x?.year : x)).filter((x: number) => Number.isFinite(x)),
  };
}
