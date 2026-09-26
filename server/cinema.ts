import { randomUUID } from "node:crypto";
import { TRPCError } from "@trpc/server";

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
export type MovieDetail = Movie & { servers: Array<{ name: string; isAi: boolean; episodes: Array<{ name: string; slug: string; filename: string; embedUrl: string | null; streamUrl: string | null }> }>; actorProfiles?: Array<{ name: string; image: string | null }> };

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
    if (url.protocol !== "https:" || !allowedImageHosts.has(url.hostname)) return null;
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
  const expires = Date.now() + 120 * 60_000;
  const existing = sourceImageTokens.get(source);
  if (existing && existing.expires > Date.now() && imageTokens.has(existing.token)) {
    imageTokens.set(existing.token, { url: source, expires });
    sourceImageTokens.set(source, { token: existing.token, expires });
    return apiRoute(`/api/cinema/image/${existing.token}`);
  }
  const token = randomUUID().replaceAll("-", "");
  imageTokens.set(token, { url: source, expires });
  sourceImageTokens.set(source, { token, expires });
  return apiRoute(`/api/cinema/image/${token}`);
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
    streamTokens.set(token, { url: url.toString(), expires: Date.now() + 10 * 60_000 });
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
async function upstream(path: string, query: Record<string, string | number | undefined> = {}) {
  const params = new URLSearchParams();
  Object.entries(query).forEach(([key, value]) => { if (value !== undefined && value !== "") params.set(key, String(value)); });
  const url = `${API_BASE}${path}${params.size ? `?${params.toString()}` : ""}`;
  const cached = cache.get(url);
  if (cached && cached.expires > Date.now()) return cached.value as any;
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
  return { items: items.map((item: any) => normalizeMovie(item, pathImage)), pagination };
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
  subteam: "/v1/api/danh-sach/subteam",
  theatrical: "/v1/api/danh-sach/phim-chieu-rap",
};
export async function getMovies(input: { kind: keyof typeof listEndpoints; page?: number; category?: string; country?: string; year?: number }) {
  const category = input.category?.trim() || undefined;
  const country = input.country?.trim() || undefined;
  const year = input.year;
  let endpoint = listEndpoints[input.kind];
  let query: Record<string, string | number | undefined> = { page: safePage(input.page), limit: 24, category, country, year };
  // KKPhim có endpoint chuyên biệt cho từng bộ lọc. Dùng chúng khi chỉ có
  // một filter để API trả đúng params.pagination và tránh kết quả không lọc.
  if (input.kind === "latest" && category && !country && !year) {
    endpoint = `/v1/api/the-loai/${encodeURIComponent(safeFilterSlug(category))}`;
    query = { page: safePage(input.page), limit: 24 };
  } else if (input.kind === "latest" && country && !category && !year) {
    endpoint = `/v1/api/quoc-gia/${encodeURIComponent(safeFilterSlug(country))}`;
    query = { page: safePage(input.page), limit: 24 };
  } else if (input.kind === "latest" && year && !category && !country) {
    endpoint = `/v1/api/nam/${year}`;
    query = { page: safePage(input.page), limit: 24 };
  }
  const payload = await upstream(endpoint, query);
  const { items, pagination, pathImage } = unwrapItems(payload);
  return { items: items.map((item: any) => normalizeMovie(item, pathImage)), pagination };
}
export async function searchMovies(input: { keyword: string; page?: number }) {
  const keyword = input.keyword.trim().slice(0, 80);
  if (keyword.length < 2) return { items: [], pagination: null };
  const payload = await upstream("/v1/api/tim-kiem", { keyword, page: safePage(input.page), limit: 24 });
  const { items, pagination, pathImage } = unwrapItems(payload);
  return { items: items.map((item: any) => normalizeMovie(item, pathImage)), pagination };
}
export async function getMovieDetail(rawSlug: string): Promise<MovieDetail> {
  const slug = safeSlug(rawSlug);
  const payload = await getMoviePayload(slug);
  const item = payload?.data?.item ?? payload?.movie ?? null;
  if (!item) throw new TRPCError({ code: "NOT_FOUND", message: "Không tìm thấy bộ phim này." });
  const movie = normalizeMovie(item, payload?.pathImage);
  const rawServers = item?.episodes ?? payload?.episodes ?? [];
  const servers = Array.isArray(rawServers) ? rawServers.map((server: any) => ({ name: cleanText(server?.server_name, "Nguồn phim"), isAi: Boolean(server?.is_ai), episodes: Array.isArray(server?.server_data) ? server.server_data.map((episode: any) => {
    const embed = embedUrl(episode?.link_embed);
    const stream = streamUrl(episode?.link_m3u8) || streamUrlFromEmbed(episode?.link_embed);
    return { name: cleanText(episode?.name, "Tập phim"), slug: cleanText(episode?.slug), filename: cleanText(episode?.filename), embedUrl: embed, streamUrl: stream };
  }).filter((episode: any) => episode.slug && (episode.embedUrl || episode.streamUrl)) : [] })).filter((server: any) => server.episodes.length > 0) : [];
  const actorProfiles = await getMoviePeople(slug);
  return { ...movie, actorProfiles, servers };
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
