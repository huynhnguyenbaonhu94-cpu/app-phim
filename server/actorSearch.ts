/**
 * Tìm diễn viên để admin thêm vào phim thủ công.
 *
 * - Nếu có `TMDB_API_KEY` (hoặc `TMDB_ACCESS_TOKEN`) trong môi trường thì dùng TMDB:
 *   gợi ý kèm ảnh, nghề nghiệp và độ phổ biến.
 * - Nếu chưa cấu hình khoá thì dùng **Wikidata** (miễn phí, không cần khoá): tên, mô tả,
 *   ảnh từ Wikimedia Commons và mã IMDb (P345) nếu có.
 *
 * Kết quả được nhớ tạm 10 phút để không gọi nguồn ngoài quá nhiều lần.
 */

import http from "node:http";
import https from "node:https";

export type ActorSuggestion = {
  name: string;
  image: string;
  description: string;
  imdbId: string;
  tmdbId: number | null;
  source: "tmdb" | "wikidata";
};

export type ActorSearchResult = {
  items: ActorSuggestion[];
  source: "tmdb" | "wikidata";
  notice: string | null;
};

/** Từ khoá loại bỏ gợi ý không phù hợp với website phim. */
const BLOCKED_WORDS = [
  "pornographic",
  "porn",
  "adult film",
  "adult actor",
  "erotic",
  "khiêu dâm",
  "phim người lớn",
  "diễn viên người lớn",
  "sex worker",
];

function isBlocked(item: ActorSuggestion): boolean {
  const haystack = `${item.name} ${item.description}`.toLocaleLowerCase("vi-VN");
  return BLOCKED_WORDS.some(word => haystack.includes(word));
}

const CACHE_TTL_MS = 10 * 60 * 1000;
const CACHE_MAX = 120;
const cache = new Map<string, { at: number; result: ActorSearchResult }>();

function tmdbKey(): string {
  return (process.env.TMDB_API_KEY || process.env.TMDB_ACCESS_TOKEN || "").trim();
}

type AnyRecord = Record<string, unknown>;

function str(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function record(value: unknown): AnyRecord | null {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as AnyRecord) : null;
}

/**
 * Gọi API JSON bằng `node:https` (không phụ thuộc `fetch` toàn cục).
 *
 * Nhờ vậy chạy được cả trên hosting cPanel dùng Node 16/17 — nơi `fetch` chưa có —
 * và thông báo lỗi rõ ràng hơn khi máy chủ không kết nối ra ngoài được.
 */
type NetError = NodeJS.ErrnoException & { address?: string; port?: number; cause?: { code?: string } };

/** Mô tả lỗi mạng kèm mã lỗi để biết chính xác vì sao không kết nối được. */
function describeNetworkError(error: unknown): string {
  const err = (error ?? {}) as NetError;
  const parts: string[] = [];
  if (err.message) parts.push(err.message);
  if (err.code) parts.push(`mã ${err.code}`);
  if (err.syscall) parts.push(err.syscall);
  if (err.address) parts.push(`${err.address}${err.port ? `:${err.port}` : ""}`);
  if (err.cause?.code) parts.push(`gốc ${err.cause.code}`);
  return parts.join(" · ") || "lỗi không xác định";
}

/** Lỗi thuộc về đường truyền (đáng thử lại bằng IPv4) hay không. */
function isNetworkFailure(error: unknown): boolean {
  const code = (error as NetError)?.code ?? "";
  // Chỉ thử lại IPv4 với lỗi định tuyến/DNS; hết thời gian thì không thử lại để phản hồi nhanh.
  return (
    code === "ENETUNREACH" ||
    code === "EHOSTUNREACH" ||
    code === "ECONNREFUSED" ||
    code === "EAI_AGAIN" ||
    code === "EPIPE" ||
    code === ""
  );
}

/** Gọi JSON: tự thử lại một lần chỉ dùng IPv4 (nhiều hosting bật IPv6 nhưng không ra được ngoài). */
async function fetchJson(
  url: string,
  headers: Record<string, string> = {},
  timeoutMs = 6000,
): Promise<unknown> {
  try {
    return await requestJson(url, headers, timeoutMs);
  } catch (error) {
    if (!isNetworkFailure(error)) throw error;
    const first = describeNetworkError(error);
    try {
      return await requestJson(url, headers, timeoutMs, 3, 4);
    } catch (retryError) {
      throw new Error(`${describeNetworkError(retryError)} (lần đầu: ${first})`);
    }
  }
}

function requestJson(
  url: string,
  headers: Record<string, string> = {},
  timeoutMs = 6000,
  redirects = 3,
  family?: 4 | 6,
): Promise<unknown> {
  return new Promise((resolve, reject) => {
    let target: URL;
    try {
      target = new URL(url);
    } catch {
      reject(new Error("Địa chỉ nguồn không hợp lệ"));
      return;
    }
    const client = target.protocol === "http:" ? http : https;
    const request = client.get(
      url,
      {
        headers: {
          accept: "application/json",
          // Nhiều hosting dùng ModSecurity/WAF chặn user-agent lạ, nên dùng UA giống trình duyệt.
          "user-agent":
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
          ...headers,
        },
        timeout: timeoutMs,
        ...(family ? { family } : {}),
      },
      response => {
        const status = response.statusCode ?? 0;
        const location = response.headers.location;
        if (status >= 300 && status < 400 && location && redirects > 0) {
          response.resume();
          requestJson(new URL(location, url).toString(), headers, timeoutMs, redirects - 1, family).then(resolve, reject);
          return;
        }
        if (status < 200 || status >= 300) {
          response.resume();
          reject(new Error(status === 401 ? "Khoá TMDB không đúng (mã 401)" : `Nguồn trả về mã ${status}`));
          return;
        }
        let raw = "";
        response.setEncoding("utf8");
        response.on("data", (chunk: string) => {
          raw += chunk;
          if (raw.length > 4_000_000) {
            request.destroy();
            reject(new Error("Dữ liệu nguồn trả về quá lớn"));
          }
        });
        response.on("end", () => {
          try {
            resolve(JSON.parse(raw));
          } catch {
            reject(new Error("Nguồn trả về dữ liệu không đọc được"));
          }
        });
      },
    );
    request.on("timeout", () => request.destroy(new Error("Hết thời gian kết nối")));
    request.on("error", error => reject(error));
  });
}

/** Thông tin xác thực TMDB: khoá v3 (32 ký tự) hoặc token v4 (JWT dài). */
function tmdbAuth(): { headers: Record<string, string>; params: URLSearchParams } {
  const key = tmdbKey();
  const headers: Record<string, string> = {};
  const params = new URLSearchParams();
  if (key.length > 40) headers.authorization = `Bearer ${key}`;
  else params.set("api_key", key);
  return { headers, params };
}

/** Tên chỉ gồm ký tự Latinh (tránh hiện tên gốc tiếng Hàn, Trung, Nhật…). */
function isLatinName(value: string): boolean {
  return value.length > 0 && /^[\x20-\x7E]+$/.test(value);
}

/** Chuẩn hoá tên để so khớp: bỏ dấu, bỏ khoảng trắng và dấu gạch. */
function normalizeName(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase("vi-VN")
    .replace(/[^a-z0-9]/g, "");
}

/**
 * Lấy thêm tên thường dùng (also_known_as) và mã IMDb cho một diễn viên.
 *
 * TMDB trả `name` là tên gốc (có thể là tiếng Hàn), nên nếu tên gốc không phải
 * chữ Latinh thì ưu tiên bí danh Latinh đầu tiên (ví dụ 송혜교 → Song Hye-kyo).
 */
async function enrichTmdbPerson<T extends ActorSuggestion>(item: T, query: string): Promise<T> {
  if (!item.tmdbId) return item;
  try {
    const auth = tmdbAuth();
    const detailParams = new URLSearchParams(auth.params);
    detailParams.set("language", "vi-VN");
    const detail = record(
      await fetchJson(`https://api.themoviedb.org/3/person/${item.tmdbId}?${detailParams.toString()}`, auth.headers, 6000),
    );
    if (!detail) return item;
    const aliases = Array.isArray(detail.also_known_as) ? (detail.also_known_as as unknown[]).map(str) : [];
    // Ưu tiên bí danh khớp với từ khoá đang tìm (Song Hye Kyo → Song Hye-kyo).
    const wanted = normalizeName(query);
    const latinAlias =
      aliases.find(alias => normalizeName(alias) === wanted) ||
      aliases.find(alias => isLatinName(alias) && alias.length > 2 && !/\d/.test(alias)) ||
      "";
    const profile = str(detail.profile_path);
    return {
      ...item,
      name: isLatinName(item.name) ? item.name : latinAlias || item.name,
      image: item.image || (profile ? `https://image.tmdb.org/t/p/w185${profile}` : ""),
      imdbId: str(detail.imdb_id) || item.imdbId,
    };
  } catch {
    return item;
  }
}

/** TMDB: tìm diễn viên theo tên. */
async function searchTmdb(query: string, limit: number): Promise<ActorSuggestion[]> {
  const { headers, params } = tmdbAuth();
  const search = new URLSearchParams(params);
  search.set("query", query);
  search.set("language", "vi-VN");
  search.set("include_adult", "false");
  search.set("page", "1");
  const url = `https://api.themoviedb.org/3/search/person?${search.toString()}`;

  const payload = record(await fetchJson(url, headers));
  const results = Array.isArray(payload?.results) ? (payload?.results as unknown[]) : [];
  const people: Array<ActorSuggestion & { department: string }> = results
    .map(item => record(item))
    .filter((item): item is AnyRecord => Boolean(item))
    .map(item => {
      const profile = str(item.profile_path);
      return {
        name: str(item.name),
        image: profile ? `https://image.tmdb.org/t/p/w185${profile}` : "",
        description: str(item.known_for_department) || "Diễn viên",
        imdbId: "",
        tmdbId: typeof item.id === "number" ? item.id : null,
        source: "tmdb" as const,
        department: str(item.known_for_department),
      };
    })
    .filter(item => item.name.length > 0);

  // Ưu tiên người làm diễn xuất (Acting); nếu không có thì giữ nguyên kết quả.
  const acting = people.filter(person => person.department === "Acting");
  const chosen = (acting.length > 0 ? acting : people).slice(0, limit);
  const enriched = await Promise.all(chosen.map(person => enrichTmdbPerson(person, query)));
  return enriched.map(({ department, ...rest }) => rest);
}

/** Wikidata: tìm người thật (P31 = Q5) kèm ảnh Commons và mã IMDb. */
async function searchWikidata(query: string, limit: number): Promise<ActorSuggestion[]> {
  const searchUrl =
    "https://www.wikidata.org/w/api.php?" +
    new URLSearchParams({
      action: "wbsearchentities",
      search: query,
      language: "vi",
      uselang: "vi",
      type: "item",
      limit: String(Math.min(20, limit * 2)),
      format: "json",
      origin: "*",
    }).toString();

  const searchPayload = record(await fetchJson(searchUrl));
  const found = Array.isArray(searchPayload?.search) ? (searchPayload?.search as unknown[]) : [];
  const ids = found
    .map(item => str(record(item)?.id))
    .filter(id => /^Q\d+$/.test(id));
  if (ids.length === 0) return [];

  const entityUrl =
    "https://www.wikidata.org/w/api.php?" +
    new URLSearchParams({
      action: "wbgetentities",
      ids: ids.slice(0, 20).join("|"),
      props: "labels|descriptions|claims",
      languages: "vi|en",
      format: "json",
      origin: "*",
    }).toString();

  const entityPayload = record(await fetchJson(entityUrl));
  const entities = record(entityPayload?.entities);
  if (!entities) return [];

  const items: ActorSuggestion[] = [];
  for (const id of ids) {
    const entity = record(entities[id]);
    if (!entity) continue;
    const claims = record(entity.claims);
    const instanceOf = claimValues(claims, "P31");
    if (!instanceOf.includes("Q5")) continue;

    const labels = record(entity.labels);
    const descriptions = record(entity.descriptions);
    const name = str(record(labels?.vi)?.value) || str(record(labels?.en)?.value);
    if (!name) continue;

    const imageFile = claimValues(claims, "P18")[0] || "";
    const imdbId = claimValues(claims, "P345")[0] || "";
    items.push({
      name,
      image: imageFile
        ? `https://commons.wikimedia.org/wiki/Special:FilePath/${encodeURIComponent(imageFile)}?width=320`
        : "",
      description: str(record(descriptions?.vi)?.value) || str(record(descriptions?.en)?.value),
      imdbId,
      tmdbId: null,
      source: "wikidata",
    });
    if (items.length >= limit) break;
  }
  return items;
}

/** Lấy các giá trị chuỗi của một thuộc tính Wikidata. */
function claimValues(claims: AnyRecord | null, property: string): string[] {
  const list = claims && Array.isArray(claims[property]) ? (claims[property] as unknown[]) : [];
  return list
    .map(claim => record(record(record(claim)?.mainsnak)?.datavalue)?.value)
    .map(value => (typeof value === "string" ? value : str(record(value)?.id)))
    .filter(value => value.length > 0);
}

/** Tìm diễn viên: ưu tiên TMDB, không có khoá thì dùng Wikidata. */
export async function searchActors(input: { query: string; limit?: number }): Promise<ActorSearchResult> {
  const query = input.query.trim();
  const limit = Math.min(Math.max(input.limit ?? 8, 1), 20);
  if (query.length < 2) return { items: [], source: tmdbKey() ? "tmdb" : "wikidata", notice: null };

  const cacheKey = `${tmdbKey() ? "tmdb" : "wikidata"}:${limit}:${query.toLocaleLowerCase("vi-VN")}`;
  const cached = cache.get(cacheKey);
  if (cached && Date.now() - cached.at < CACHE_TTL_MS) return cached.result;

  const usingTmdb = Boolean(tmdbKey());
  try {
    const raw = usingTmdb ? await searchTmdb(query, limit) : await searchWikidata(query, limit);
    const items = raw.filter(item => !isBlocked(item)).slice(0, limit);
    const result: ActorSearchResult = {
      items,
      source: usingTmdb ? "tmdb" : "wikidata",
      notice: usingTmdb
        ? null
        : "Chưa cấu hình TMDB_API_KEY nên đang tìm bằng Wikidata (miễn phí). Thêm biến môi trường TMDB_API_KEY để có kết quả đầy đủ hơn.",
    };
    remember(cacheKey, result);
    return result;
  } catch (error) {
    // Nếu TMDB lỗi (hết hạn mức, sai khoá…) thì vẫn cố tìm bằng Wikidata.
    if (usingTmdb) {
      try {
        const items = await searchWikidata(query, limit);
        const result: ActorSearchResult = {
          items,
          source: "wikidata",
          notice: "TMDB không phản hồi nên đang dùng Wikidata. Kiểm tra lại TMDB_API_KEY.",
        };
        remember(cacheKey, result);
        return result;
      } catch {
        /* rơi xuống lỗi bên dưới */
      }
    }
    throw error instanceof Error ? error : new Error("Không tìm được diễn viên");
  }
}

/** Trạng thái kết nối để admin kiểm tra nhanh trên hosting. */
export type ActorSearchStatus = {
  nodeVersion: string;
  keyConfigured: boolean;
  keyHint: string;
  outbound: { ok: boolean; message: string };
  tmdb: { ok: boolean; message: string };
  wikidata: { ok: boolean; message: string };
};

/** Thử một địa chỉ bất kỳ để biết máy chủ có ra được Internet hay không. */
function probe(url: string, timeoutMs = 10000, family?: 4 | 6): Promise<void> {
  return new Promise((resolve, reject) => {
    const client = url.startsWith("http:") ? http : https;
    const request = client.get(
      url,
      {
        headers: {
          "user-agent":
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
        },
        timeout: timeoutMs,
        ...(family ? { family } : {}),
      },
      response => {
        response.resume();
        resolve();
      },
    );
    request.on("timeout", () => request.destroy(Object.assign(new Error("Hết thời gian kết nối"), { code: "ETIMEDOUT" })));
    request.on("error", error => reject(error));
  });
}

function describeError(error: unknown): string {
  return error instanceof Error && error.message ? error.message : "Lỗi không xác định";
}

/** Kiểm tra khoá TMDB và kết nối ra ngoài của máy chủ. */
export async function actorSearchStatus(): Promise<ActorSearchStatus> {
  const key = tmdbKey();
  const status: ActorSearchStatus = {
    nodeVersion: process.version,
    keyConfigured: Boolean(key),
    keyHint: key ? `${key.slice(0, 4)}…${key.slice(-4)}` : "",
    outbound: { ok: false, message: "chưa kiểm tra" },
    tmdb: { ok: false, message: key ? "chưa kiểm tra" : "chưa cấu hình TMDB_API_KEY" },
    wikidata: { ok: false, message: "chưa kiểm tra" },
  };

  try {
    await probe("https://example.com/");
    status.outbound = { ok: true, message: "hoạt động" };
  } catch (error) {
    status.outbound = { ok: false, message: describeNetworkError(error) };
  }

  if (key) {
    try {
      const items = await searchTmdb("Tom Hanks", 1);
      status.tmdb = { ok: items.length > 0, message: items.length > 0 ? "hoạt động" : "không có kết quả" };
    } catch (error) {
      status.tmdb = { ok: false, message: describeError(error) };
    }
  }

  try {
    const items = await searchWikidata("Tom Hanks", 1);
    status.wikidata = { ok: items.length > 0, message: items.length > 0 ? "hoạt động" : "không có kết quả" };
  } catch (error) {
    status.wikidata = { ok: false, message: describeError(error) };
  }

  return status;
}

function remember(key: string, result: ActorSearchResult) {
  if (cache.size >= CACHE_MAX) {
    const oldest = cache.keys().next().value;
    if (oldest) cache.delete(oldest);
  }
  cache.set(key, { at: Date.now(), result });
}