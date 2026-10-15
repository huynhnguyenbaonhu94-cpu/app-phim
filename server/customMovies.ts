/**
 * Phim do admin thêm thủ công bằng link.
 *
 * Phim thủ công không lấy từ API nguồn: admin tự nhập tên, poster, thumbnail, diễn
 * viên, thể loại, quốc gia… rồi thêm nguồn và tập kèm link M3U8 (xem `movieSources`).
 *
 * Phim được trả về **cùng hình dạng** với phim lấy từ API (`Movie` / `MovieDetail`),
 * nên app đọc như phim bình thường: hiện trong danh sách, tìm kiếm, trang chi tiết,
 * có diễn viên kèm ảnh, và phát được ngay.
 */
import fs from "node:fs/promises";
import path from "node:path";
import crypto from "node:crypto";
import { asc, desc, eq, sql } from "drizzle-orm";
import { getDb } from "./db";
import { customMovies } from "../drizzle/schema";
import type { Movie, MovieDetail } from "./cinema";
import { registerStreamSource } from "./cinema";
import { listMovieSources } from "./movieSources";

export type CustomMovieTag = { name: string; slug: string };
/** Đầu vào từ biểu mẫu quản trị: slug có thể thiếu, sẽ tự sinh từ tên. */
export type CustomMovieTagInput = { name: string; slug?: string | null };
export type CustomMovieActor = { name: string; role?: string | null; image?: string | null };

export type CustomMovieInput = {
  name: string;
  slug?: string | null;
  originName?: string | null;
  alternativeNames?: string[];
  episodeCurrent?: string | null;
  episodeTotal?: number | null;
  createdDate?: string | null;
  updatedDate?: string | null;
  tmdbId?: string | null;
  imdbId?: string | null;
  categories?: CustomMovieTagInput[];
  countries?: CustomMovieTagInput[];
  rating?: string | null;
  viewsMode?: "real" | "mixed";
  viewsBase?: number;
  posterUrl?: string | null;
  thumbUrl?: string | null;
  description?: string | null;
  quality?: string | null;
  year?: number | null;
  lang?: string | null;
  time?: string | null;
  status?: string | null;
  movieType?: "series" | "single";
  actors?: CustomMovieActor[];
  directors?: string[];
  isPublished?: boolean;
};

type CustomMovieRow = typeof customMovies.$inferSelect;

const IMAGE_DIR = "uploads/movie-images";
const MAX_IMAGE_BYTES = 8 * 1024 * 1024;

function parseJson<T>(value: unknown, fallback: T): T {
  if (typeof value !== "string" || !value.trim()) return fallback;
  try {
    const parsed = JSON.parse(value);
    return (parsed ?? fallback) as T;
  } catch {
    return fallback;
  }
}

function jsonOrNull(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  if (Array.isArray(value) && value.length === 0) return null;
  return JSON.stringify(value);
}

function clean(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length ? trimmed.slice(0, 20_000) : null;
}

function iso(value: Date | null | undefined): string | null {
  if (!value) return null;
  const date = value instanceof Date ? value : new Date(String(value));
  if (Number.isNaN(date.getTime())) return null;
  return date.toISOString();
}

/** Slug không dấu, dùng làm khoá cho phim thủ công. */
export function slugifyMovieName(name: string): string {
  return name
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/đ/gi, "d")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 160);
}

function tags(value: unknown): CustomMovieTag[] {
  return parseJson<CustomMovieTag[]>(value, [])
    .filter((item) => item && typeof item.name === "string" && item.name.trim().length > 0)
    .map((item) => ({
      name: String(item.name).trim().slice(0, 120),
      slug: String(item.slug ?? slugifyMovieName(String(item.name))).trim().slice(0, 120),
    }));
}

function actorList(row: CustomMovieRow): CustomMovieActor[] {
  return parseJson<CustomMovieActor[]>(row.actors, [])
    .filter((item) => item && typeof item.name === "string" && item.name.trim().length > 0)
    .map((item) => ({
      name: String(item.name).trim().slice(0, 160),
      role: typeof item.role === "string" && item.role.trim() ? item.role.trim().slice(0, 160) : null,
      image: typeof item.image === "string" && item.image.trim() ? item.image.trim().slice(0, 2000) : null,
    }));
}

/** Lượt xem hiển thị: chỉ số thật, hoặc thật + số ảo khi admin chọn chế độ "vừa thật + ảo". */
function displayViews(row: CustomMovieRow): number {
  const real = Number(row.viewCount) || 0;
  if (row.viewsMode === "mixed") return real + (Number(row.viewsBase) || 0);
  return real;
}

/** Chuyển bản ghi thành hình dạng `Movie` mà app đang đọc. */
export function toApiMovie(row: CustomMovieRow): Movie {
  const people = actorList(row);
  const rating = Number(String(row.rating ?? "").replace(",", "."));
  return {
    id: `custom-${row.id}`,
    slug: row.slug,
    name: row.name,
    originName: row.originName ?? "",
    poster: row.posterUrl ?? row.thumbUrl ?? null,
    backdrop: row.thumbUrl ?? row.posterUrl ?? null,
    year: row.year ?? null,
    quality: row.quality ?? "FHD",
    episodeCurrent: row.episodeCurrent ?? (row.movieType === "single" ? "Full" : ""),
    episodeTotal: row.episodeTotal ?? null,
    time: row.time ?? "",
    lang: row.lang ?? "Vietsub",
    type: row.movieType === "single" ? "single" : "series",
    description: row.description ?? "",
    rating: Number.isFinite(rating) && rating > 0 ? rating : null,
    categories: tags(row.categories),
    countries: tags(row.countries),
    alternativeNames: parseJson<string[]>(row.alternativeNames, []).filter((item) => typeof item === "string" && item.trim().length > 0),
    actors: people.map((person) => person.name),
    directors: parseJson<string[]>(row.directors, []).filter((item) => typeof item === "string" && item.trim().length > 0),
    status: row.status ?? "",
    views: displayViews(row),
    isCopyright: false,
    isTheatrical: false,
    trailerUrl: null,
    tmdbId: row.tmdbId ?? null,
    imdbId: row.imdbId ?? null,
    createdAt: row.createdDate ?? iso(row.createdAt),
    // Ngày cập nhật luôn là mốc thật của bản ghi (tự đổi mỗi lần admin lưu),
    // không dùng cột updatedDate do admin nhập tay trước đây nữa.
    updatedAt: iso(row.updatedAt) ?? row.updatedDate,
  };
}

export async function listCustomMovies(): Promise<CustomMovieRow[]> {
  const db = await getDb();
  if (!db) return [];
  return db.select().from(customMovies).orderBy(desc(customMovies.updatedAt), asc(customMovies.id));
}

export async function getCustomMovieBySlug(slug: string): Promise<CustomMovieRow | null> {
  const db = await getDb();
  if (!db) return null;
  const [row] = await db.select().from(customMovies).where(eq(customMovies.slug, slug.trim())).limit(1);
  return row ?? null;
}

export async function getCustomMovieById(id: number): Promise<CustomMovieRow | null> {
  const db = await getDb();
  if (!db) return null;
  const [row] = await db.select().from(customMovies).where(eq(customMovies.id, id)).limit(1);
  return row ?? null;
}

async function uniqueSlug(desired: string, ignoreId?: number): Promise<string> {
  const db = await getDb();
  const base = slugifyMovieName(desired) || `phim-${Date.now()}`;
  if (!db) return base;
  for (let attempt = 0; attempt < 50; attempt += 1) {
    const candidate = attempt === 0 ? base : `${base}-${attempt + 1}`;
    const [existing] = await db.select({ id: customMovies.id }).from(customMovies).where(eq(customMovies.slug, candidate)).limit(1);
    if (!existing || (ignoreId && existing.id === ignoreId)) return candidate;
  }
  return `${base}-${crypto.randomBytes(3).toString("hex")}`;
}

function buildValues(input: CustomMovieInput) {
  return {
    name: String(input.name).trim().slice(0, 200),
    originName: clean(input.originName),
    alternativeNames: jsonOrNull(input.alternativeNames),
    episodeCurrent: clean(input.episodeCurrent),
    episodeTotal: input.episodeTotal ?? null,
    createdDate: clean(input.createdDate),
    updatedDate: clean(input.updatedDate),
    tmdbId: clean(input.tmdbId),
    imdbId: clean(input.imdbId),
    categories: jsonOrNull(input.categories),
    countries: jsonOrNull(input.countries),
    rating: clean(input.rating),
    viewsMode: input.viewsMode === "mixed" ? "mixed" : "real",
    viewsBase: Math.max(0, Math.trunc(input.viewsBase ?? 0)),
    posterUrl: clean(input.posterUrl),
    thumbUrl: clean(input.thumbUrl),
    description: clean(input.description),
    quality: clean(input.quality),
    year: input.year ?? null,
    lang: clean(input.lang),
    time: clean(input.time),
    status: clean(input.status),
    movieType: input.movieType === "single" ? "single" : "series",
    actors: jsonOrNull(input.actors),
    directors: jsonOrNull(input.directors),
    isPublished: input.isPublished ?? true,
  };
}

export async function createCustomMovie(input: CustomMovieInput): Promise<CustomMovieRow> {
  const db = await getDb();
  if (!db) throw new Error("Không kết nối được cơ sở dữ liệu");
  const slug = await uniqueSlug(input.slug?.trim() ? input.slug : input.name);
  const [inserted] = await db
    .insert(customMovies)
    .values({ ...buildValues(input), slug })
    .$returningId();
  const row = await getCustomMovieById(inserted.id);
  if (!row) throw new Error("Không tạo được phim");
  return row;
}

export async function updateCustomMovie(id: number, input: CustomMovieInput): Promise<CustomMovieRow> {
  const db = await getDb();
  if (!db) throw new Error("Không kết nối được cơ sở dữ liệu");
  const current = await getCustomMovieById(id);
  if (!current) throw new Error("Không tìm thấy phim cần sửa");
  const slug = input.slug?.trim() && input.slug.trim() !== current.slug
    ? await uniqueSlug(input.slug, id)
    : current.slug;
  await db.update(customMovies).set({ ...buildValues(input), slug }).where(eq(customMovies.id, id));
  const row = await getCustomMovieById(id);
  if (!row) throw new Error("Không sửa được phim");
  return row;
}

export async function removeCustomMovie(id: number): Promise<void> {
  const db = await getDb();
  if (!db) throw new Error("Không kết nối được cơ sở dữ liệu");
  await db.delete(customMovies).where(eq(customMovies.id, id));
}

/** Tăng lượt xem thật khi có người mở trang chi tiết phim thủ công. */
export async function registerCustomMovieView(slug: string): Promise<void> {
  const db = await getDb();
  if (!db) return;
  try {
    await db.execute(sql`UPDATE \`custom_movies\` SET \`viewCount\` = \`viewCount\` + 1 WHERE \`slug\` = ${slug}`);
  } catch {
    /* đếm lượt xem không được làm hỏng việc mở phim */
  }
}

/** Trang chi tiết của phim thủ công, kèm nguồn/tập do admin thêm. */
export async function getCustomMovieDetail(slug: string): Promise<MovieDetail | null> {
  const row = await getCustomMovieBySlug(slug);
  if (!row || !row.isPublished) return null;
  const { mergeCustomSources } = await import("./movieSources");
  const movie = toApiMovie(row);
  const people = actorList(row);
  return {
    ...movie,
    actorProfiles: people.map((person) => ({ name: person.name, image: person.image ?? null })),
    servers: await mergeCustomSources(row.slug, []),
  };
}

/** Danh sách nguồn/tập của phim thủ công, dùng cho trang quản trị. */
export async function customMovieSources(slug: string) {
  return listMovieSources(slug);
}

export type CustomMovieFilter = {
  kinds?: string[];
  categories?: string[];
  countries?: string[];
  years?: number[];
};

function isCompleted(row: CustomMovieRow): boolean {
  const marker = `${row.status ?? ""} ${row.episodeCurrent ?? ""}`.toLocaleLowerCase("vi-VN");
  if (/(hoàn tất|hoan tat|hoàn thành|hoan thanh|full|completed|complete|end)/i.test(marker)) return true;
  if (row.episodeTotal && row.episodeCurrent) {
    const numbers = row.episodeCurrent.match(/\d+/g)?.map(Number) || [];
    const current = numbers[numbers.length - 1];
    if (current && current >= row.episodeTotal) return true;
  }
  return false;
}

/**
 * Phim thủ công khớp bộ lọc của Thư viện.
 *
 * Quy ước giống API nguồn: nhiều lựa chọn trong cùng một nhóm là HOẶC, giữa các
 * nhóm là VÀ.
 */
export async function customMoviesForFilter(filter: CustomMovieFilter): Promise<Movie[]> {
  const rows = (await listCustomMovies()).filter((row) => row.isPublished);
  if (rows.length === 0) return [];

  const kinds = (filter.kinds ?? []).map((value) => value.trim()).filter(Boolean);
  const categories = (filter.categories ?? []).map((value) => value.trim()).filter(Boolean);
  const countries = (filter.countries ?? []).map((value) => value.trim()).filter(Boolean);
  const years = (filter.years ?? []).filter((value) => Number.isInteger(value));

  return rows
    .filter((row) => {
      if (kinds.length) {
        const matched = kinds.some((kind) => {
          if (kind === "single") return row.movieType === "single";
          if (kind === "series" || kind === "shows") return row.movieType === "series";
          if (kind === "ongoing") return row.movieType === "series" && !isCompleted(row);
          if (kind === "completed") return row.movieType === "series" && isCompleted(row);
          // latest, vietsub, thuyetminh…: phim thủ công luôn được coi là hợp lệ.
          return true;
        });
        if (!matched) return false;
      }
      if (categories.length) {
        const own = tags(row.categories);
        if (!categories.some((value) => own.some((item) => item.slug === value || item.name === value))) return false;
      }
      if (countries.length) {
        const own = tags(row.countries);
        if (!countries.some((value) => own.some((item) => item.slug === value || item.name === value))) return false;
      }
      if (years.length && (!row.year || !years.includes(row.year))) return false;
      return true;
    })
    .map(toApiMovie);
}

/**
 * Bỏ dấu tiếng Việt và hạ chữ thường để so khớp tên phim.
 *
 * Nhờ vậy "thuc tinh" tìm được "Thức Tỉnh" và "vision quest" tìm được
 * "VisionQuest" — người dùng không phải gõ đúng dấu hay đúng hoa thường.
 */
function foldText(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/đ/g, "d")
    .replace(/Đ/g, "D")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();
}

/** Tìm phim thủ công theo tên tiếng Việt, tên tiếng Anh và tên khác. */
export async function searchCustomMovies(keyword: string): Promise<Movie[]> {
  const needle = foldText(keyword);
  if (needle.length < 2) return [];
  const rows = (await listCustomMovies()).filter((row) => row.isPublished);
  return rows
    .filter((row) => {
      const haystack = foldText([
        row.name,
        row.originName ?? "",
        ...parseJson<string[]>(row.alternativeNames, []),
      ].join(" "));
      return haystack.includes(needle);
    })
    .map(toApiMovie);
}

/** Ghi ảnh đã kiểm tra xuống thư mục uploads và trả về URL công khai. */
async function storeImageBuffer(buffer: Buffer): Promise<{ url: string; mimeType: string }> {
  if (buffer.byteLength === 0) throw new Error("Ảnh rỗng");
  if (buffer.byteLength > MAX_IMAGE_BYTES) throw new Error("Ảnh vượt quá 8MB");
  const kind = detectImageKind(buffer);
  if (!kind) throw new Error("Chỉ nhận ảnh JPEG, PNG hoặc WebP");
  const target = path.resolve(process.cwd(), IMAGE_DIR);
  await fs.mkdir(target, { recursive: true });
  const name = `${Date.now()}-${crypto.randomBytes(4).toString("hex")}.${kind}`;
  await fs.writeFile(path.join(target, name), buffer);
  return { url: `/${IMAGE_DIR}/${name}`, mimeType: kind === "jpg" ? "image/jpeg" : `image/${kind}` };
}

/** Lưu ảnh poster/thumbnail/diễn viên admin tải lên, trả về URL công khai. */
export async function saveMovieImage(input: {
  base64: string;
  filename?: string;
  mimeType?: string;
}): Promise<{ url: string }> {
  const raw = input.base64.includes(",") ? input.base64.slice(input.base64.indexOf(",") + 1) : input.base64;
  const { url } = await storeImageBuffer(Buffer.from(raw, "base64"));
  return { url };
}

/** Chặn địa chỉ nội bộ để link do admin nhập không quét được mạng nội bộ của máy chủ. */
function assertPublicHost(hostname: string) {
  const host = hostname.trim().toLocaleLowerCase();
  if (!host) throw new Error("Link ảnh không hợp lệ");
  const blockedNames = ["localhost", "localhost.localdomain", "ip6-localhost", "metadata.google.internal"];
  if (blockedNames.includes(host) || host.endsWith(".local") || host.endsWith(".internal")) {
    throw new Error("Không hỗ trợ địa chỉ nội bộ");
  }
  const ipv4 = host.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (ipv4) {
    const [a, b] = [Number(ipv4[1]), Number(ipv4[2])];
    const isPrivate =
      a === 0 || a === 10 || a === 127 ||
      (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && b === 168);
    if (isPrivate) throw new Error("Không hỗ trợ địa chỉ nội bộ");
  }
  if (host.startsWith("[") || host.includes(":")) {
    if (host === "[::1]" || host.startsWith("[fe80") || host.startsWith("[fc") || host.startsWith("[fd")) {
      throw new Error("Không hỗ trợ địa chỉ nội bộ");
    }
  }
}

/**
 * Tải ảnh từ link ngoài về máy chủ.
 *
 * Nhờ vậy ảnh xem trước và **cắt ảnh** luôn hoạt động (không phụ thuộc CORS của nơi
 * lưu ảnh) và ảnh vẫn còn khi link gốc hỏng. Ảnh được kiểm tra bằng magic bytes.
 */
export async function importMovieImageFromUrl(input: { url: string }): Promise<{ url: string; mimeType: string }> {
  const raw = String(input.url || "").trim();
  if (!raw) throw new Error("Chưa có link ảnh");
  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch {
    throw new Error("Link ảnh không hợp lệ");
  }
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    throw new Error("Chỉ nhận link http hoặc https");
  }
  assertPublicHost(parsed.hostname);

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 20000);
  try {
    const response = await fetch(parsed.toString(), {
      signal: controller.signal,
      redirect: "follow",
      headers: {
        "user-agent": "Mozilla/5.0 (compatible; CinemoraBot/1.0)",
        accept: "image/avif,image/webp,image/png,image/jpeg,*/*;q=0.8",
      },
    });
    if (!response.ok) throw new Error(`Không tải được ảnh (mã ${response.status})`);
    if (response.url) assertPublicHost(new URL(response.url).hostname);
    const declared = Number(response.headers.get("content-length") || 0);
    if (declared > MAX_IMAGE_BYTES) throw new Error("Ảnh vượt quá 8MB");
    const buffer = Buffer.from(await response.arrayBuffer());
    return await storeImageBuffer(buffer);
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") throw new Error("Hết thời gian tải ảnh");
    throw error instanceof Error ? error : new Error("Không tải được ảnh từ link này");
  } finally {
    clearTimeout(timer);
  }
}

/** Nhận dạng ảnh bằng magic bytes, không tin phần mở rộng tên tệp. */
function detectImageKind(buffer: Buffer): "jpg" | "png" | "webp" | null {
  if (buffer.length > 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) return "jpg";
  if (buffer.length > 8 && buffer.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return "png";
  if (buffer.length > 12 && buffer.subarray(0, 4).toString("ascii") === "RIFF" && buffer.subarray(8, 12).toString("ascii") === "WEBP") return "webp";
  return null;
}