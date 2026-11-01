import { createHash } from "node:crypto";
import { storageBackend, storagePutPublicStable, storagePutStable, storageRead } from "./storage";

const IMAGE_HOSTS = new Set(["phimimg.com", "www.phimimg.com", "phimapi.com", "www.phimapi.com", "image.tmdb.org"]);
const MAX_IMAGE_BYTES = 12 * 1024 * 1024;
const MIRROR_REFRESH_MS = 30 * 24 * 60 * 60 * 1000;
const POSITIVE_MEMORY_MS = 30 * 60 * 1000;
const NEGATIVE_MEMORY_MS = 2 * 60 * 1000;
const CONFIG_MEMORY_MS = 30 * 1000;
const MAX_CONCURRENT_MIRRORS = 4;
const MAX_PENDING_MIRRORS = 500;
const MAX_ARTWORK_MEMORY_ENTRIES = 5_000;

type SupportedImage = { contentType: string; extension: "jpg" | "png" | "webp" | "gif" | "avif" };
type ArtworkManifest = {
  version: 1;
  key: string;
  contentType: SupportedImage["contentType"];
  cachedAt: number;
};
type MemoryEntry = { manifest: ArtworkManifest | null; expiresAt: number };
export type MirroredArtworkResult = { url?: string; bytes?: Buffer; contentType?: string } | null;

const artworkMemory = new Map<string, MemoryEntry>();
const pendingManifestReads = new Map<string, Promise<ArtworkManifest | null>>();
const pendingMirrors = new Map<string, Promise<MirroredArtworkResult>>();
let backendMemory: { isR2: boolean; expiresAt: number } | null = null;
let activeMirrors = 0;
const mirrorWaiters: Array<() => void> = [];

function sha256(value: string | Buffer) {
  return createHash("sha256").update(value).digest("hex");
}

function allowedHost(hostname: string) {
  const host = hostname.toLowerCase();
  return Array.from(IMAGE_HOSTS).some((allowed) => host === allowed || host.endsWith(`.${allowed}`));
}

export function isAllowedMovieArtworkSource(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === "https:" && !url.username && !url.password && !url.port && allowedHost(url.hostname);
  } catch {
    return false;
  }
}

function imageType(contentType: string | null): SupportedImage | null {
  const mime = (contentType || "").split(";", 1)[0].trim().toLowerCase();
  switch (mime) {
    case "image/jpeg": return { contentType: mime, extension: "jpg" };
    case "image/png": return { contentType: mime, extension: "png" };
    case "image/webp": return { contentType: mime, extension: "webp" };
    case "image/gif": return { contentType: mime, extension: "gif" };
    case "image/avif": return { contentType: mime, extension: "avif" };
    default: return null;
  }
}

function matchesImageSignature(bytes: Buffer, type: SupportedImage): boolean {
  if (type.extension === "jpg") return bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  if (type.extension === "png") return bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  if (type.extension === "webp") return bytes.length >= 12 && bytes.toString("ascii", 0, 4) === "RIFF" && bytes.toString("ascii", 8, 12) === "WEBP";
  if (type.extension === "gif") return bytes.toString("ascii", 0, 6) === "GIF87a" || bytes.toString("ascii", 0, 6) === "GIF89a";
  if (type.extension === "avif") return bytes.length >= 12 && bytes.toString("ascii", 4, 8) === "ftyp" && /^(avif|avis)$/.test(bytes.toString("ascii", 8, 12));
  return false;
}

async function readBodyLimited(response: Response): Promise<Buffer> {
  const declaredLength = Number(response.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > MAX_IMAGE_BYTES) throw new Error("Artwork exceeds size limit");
  if (!response.body) throw new Error("Artwork response is empty");
  const reader = response.body.getReader();
  const chunks: Buffer[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      const chunk = Buffer.from(value);
      total += chunk.byteLength;
      if (total > MAX_IMAGE_BYTES) {
        await reader.cancel();
        throw new Error("Artwork exceeds size limit");
      }
      chunks.push(chunk);
    }
  } finally {
    reader.releaseLock();
  }
  if (!total) throw new Error("Artwork response is empty");
  return Buffer.concat(chunks, total);
}

async function fetchArtwork(source: string): Promise<{ bytes: Buffer; type: SupportedImage }> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12_000);
  let current = new URL(source);
  try {
    for (let redirect = 0; redirect <= 4; redirect += 1) {
      if (!isAllowedMovieArtworkSource(current.toString())) throw new Error("Artwork redirect host is not allowed");
      const response = await fetch(current, {
        redirect: "manual",
        headers: { accept: "image/avif,image/webp,image/png,image/jpeg,image/gif,*/*;q=0.2", "user-agent": "Cinemora/1.0" },
        signal: controller.signal,
      });
      if ([301, 302, 303, 307, 308].includes(response.status)) {
        const location = response.headers.get("location");
        await response.body?.cancel().catch(() => undefined);
        if (!location || redirect === 4) throw new Error("Artwork redirect is invalid");
        current = new URL(location, current);
        continue;
      }
      if (!response.ok) {
        await response.body?.cancel().catch(() => undefined);
        throw new Error(`Artwork origin returned ${response.status}`);
      }
      const type = imageType(response.headers.get("content-type"));
      if (!type) {
        await response.body?.cancel().catch(() => undefined);
        throw new Error("Artwork content type is not a supported raster image");
      }
      const bytes = await readBodyLimited(response);
      if (!matchesImageSignature(bytes, type)) throw new Error("Artwork bytes do not match their image type");
      return { bytes, type };
    }
    throw new Error("Artwork redirect limit exceeded");
  } finally {
    clearTimeout(timeout);
  }
}

function manifestKey(sourceHash: string) {
  return `movie-artwork-cache/${sourceHash}.json`;
}

function validManifest(value: unknown, sourceHash: string): value is ArtworkManifest {
  if (!value || typeof value !== "object") return false;
  const candidate = value as Partial<ArtworkManifest>;
  return candidate.version === 1
    && typeof candidate.key === "string"
    && candidate.key.startsWith(`public-assets/movie-artwork/${sourceHash}/`)
    && /^public-assets\/movie-artwork\/[a-f0-9]{64}\/[a-f0-9]{64}\.(jpg|png|webp|gif|avif)$/.test(candidate.key)
    && typeof candidate.contentType === "string"
    && imageType(candidate.contentType)?.contentType === candidate.contentType
    && Number.isFinite(candidate.cachedAt)
    && Number(candidate.cachedAt) > 0;
}

function publicRouteForKey(key: string) {
  return `/api/public-storage/${key.split("/").map(encodeURIComponent).join("/")}`;
}

async function isR2Ready(): Promise<boolean> {
  if (backendMemory && backendMemory.expiresAt > Date.now()) return backendMemory.isR2;
  let isR2 = false;
  try {
    isR2 = await storageBackend() === "r2";
  } catch (error) {
    console.warn("[movie-artwork] R2 configuration unavailable; keeping the existing image proxy", error instanceof Error ? error.message : "unknown error");
  }
  backendMemory = { isR2, expiresAt: Date.now() + CONFIG_MEMORY_MS };
  return isR2;
}

function rememberArtwork(sourceHash: string, manifest: ArtworkManifest | null, ttl: number) {
  artworkMemory.set(sourceHash, { manifest, expiresAt: Date.now() + ttl });
  if (artworkMemory.size <= MAX_ARTWORK_MEMORY_ENTRIES) return;
  const now = Date.now();
  for (const [key, value] of Array.from(artworkMemory.entries())) {
    if (value.expiresAt <= now) artworkMemory.delete(key);
  }
  while (artworkMemory.size > MAX_ARTWORK_MEMORY_ENTRIES) {
    const oldest = artworkMemory.keys().next().value as string | undefined;
    if (!oldest) break;
    artworkMemory.delete(oldest);
  }
}

async function readManifest(sourceHash: string): Promise<ArtworkManifest | null> {
  const memory = artworkMemory.get(sourceHash);
  if (memory && memory.expiresAt > Date.now()) return memory.manifest;
  const pending = pendingManifestReads.get(sourceHash);
  if (pending) return pending;
  const operation = (async () => {
    if (!(await isR2Ready())) return null;
    try {
      const parsed = JSON.parse((await storageRead(manifestKey(sourceHash))).toString("utf8")) as unknown;
      if (!validManifest(parsed, sourceHash)) throw new Error("Invalid artwork cache manifest");
      rememberArtwork(sourceHash, parsed, POSITIVE_MEMORY_MS);
      return parsed;
    } catch {
      rememberArtwork(sourceHash, null, NEGATIVE_MEMORY_MS);
      return null;
    }
  })();
  pendingManifestReads.set(sourceHash, operation);
  try {
    return await operation;
  } finally {
    pendingManifestReads.delete(sourceHash);
  }
}

async function saveManifest(sourceHash: string, manifest: ArtworkManifest) {
  const saved = await storagePutStable(manifestKey(sourceHash), JSON.stringify(manifest), "application/json");
  if (saved.backend !== "r2") throw new Error("R2 is not configured for persistent artwork cache");
  rememberArtwork(sourceHash, manifest, POSITIVE_MEMORY_MS);
}

async function withMirrorSlot<T>(task: () => Promise<T>): Promise<T> {
  if (activeMirrors >= MAX_CONCURRENT_MIRRORS) await new Promise<void>((resolve) => mirrorWaiters.push(resolve));
  activeMirrors += 1;
  try {
    return await task();
  } finally {
    activeMirrors -= 1;
    mirrorWaiters.shift()?.();
  }
}

/** Returns a warmed R2 URL without doing I/O on the catalog request path. */
export function getRememberedMovieArtworkUrl(source: string): string | null {
  if (!isAllowedMovieArtworkSource(source)) return null;
  const sourceHash = sha256(new URL(source).toString());
  const memory = artworkMemory.get(sourceHash);
  if (!memory || memory.expiresAt <= Date.now()) {
    artworkMemory.delete(sourceHash);
    return null;
  }
  const manifest = memory.manifest;
  if (!manifest) return null;
  if (Date.now() - manifest.cachedAt > MIRROR_REFRESH_MS) {
    void mirrorMovieArtwork(source).catch(() => undefined);
  }
  return publicRouteForKey(manifest.key);
}

/**
 * Mirror one allowlisted API image into R2. Image objects are content-addressed and
 * indexed by a private stable manifest. If refresh fails, the previous R2 image
 * remains usable. If R2 is unavailable, callers may fall back to the old image proxy.
 */
export async function mirrorMovieArtwork(source: string): Promise<MirroredArtworkResult> {
  if (!isAllowedMovieArtworkSource(source) || !(await isR2Ready())) return null;
  const normalizedSource = new URL(source).toString();
  const sourceHash = sha256(normalizedSource);
  const existingPending = pendingMirrors.get(sourceHash);
  if (existingPending) return existingPending;
  if (pendingMirrors.size >= MAX_PENDING_MIRRORS) return null;

  const operation = withMirrorSlot(async (): Promise<MirroredArtworkResult> => {
    let previous = await readManifest(sourceHash);
    if (previous && Date.now() - previous.cachedAt <= MIRROR_REFRESH_MS) {
      return { url: publicRouteForKey(previous.key) };
    }
    let downloaded: { bytes: Buffer; type: SupportedImage } | null = null;
    try {
      downloaded = await fetchArtwork(normalizedSource);
      const { bytes, type } = downloaded;
      const contentHash = sha256(bytes);
      const key = `movie-artwork/${sourceHash}/${contentHash}.${type.extension}`;
      const stored = await storagePutPublicStable(key, bytes, type.contentType);
      if (stored.backend !== "r2") throw new Error("R2 upload did not complete");
      const manifest: ArtworkManifest = { version: 1, key: stored.key, contentType: type.contentType, cachedAt: Date.now() };
      await saveManifest(sourceHash, manifest);
      return { url: publicRouteForKey(stored.key) };
    } catch (error) {
      if (previous) {
        rememberArtwork(sourceHash, previous, POSITIVE_MEMORY_MS);
        return { url: publicRouteForKey(previous.key) };
      }
      console.warn(`[movie-artwork] R2 mirror unavailable for ${sourceHash.slice(0, 12)}; retaining upstream proxy`, error instanceof Error ? error.message : "unknown error");
      if (downloaded) return { bytes: downloaded.bytes, contentType: downloaded.type.contentType };
      return null;
    }
  });
  pendingMirrors.set(sourceHash, operation);
  try {
    return await operation;
  } finally {
    pendingMirrors.delete(sourceHash);
  }
}
