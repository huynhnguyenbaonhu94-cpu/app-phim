import { createCipheriv, createDecipheriv, createHash, randomBytes, randomUUID } from "node:crypto";
import { mkdir, readFile, readdir, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { eq } from "drizzle-orm";
import { DeleteObjectCommand, GetObjectCommand, HeadObjectCommand, ListObjectsV2Command, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { getDb } from "./db";
import { r2Settings } from "../drizzle/schema";

const SETTINGS_ID = 1;
// Keep the fallback outside Express' public /uploads mount.
const LOCAL_ROOT = path.resolve(process.env.LOCAL_PRIVATE_UPLOAD_DIR || path.resolve(process.cwd(), ".private-uploads"));
const DEFAULT_REGION = "auto";

type R2Config = {
  endpoint: string;
  bucket: string;
  region: string;
  accessKeyId: string;
  secretAccessKey: string;
  publicBaseUrl?: string;
};

export type R2PublicSettings = {
  configured: boolean;
  backend: "r2" | "local";
  endpoint: string | null;
  bucket: string | null;
  region: string;
  publicBaseUrl: string | null;
  hasAccessKeyId: boolean;
  hasSecretAccessKey: boolean;
  encryptionKeyConfigured: boolean;
  backupEnabled: boolean;
  backupFrequency: "daily" | "weekly";
  scheduleHourVietnam: number;
  updatedAt: string | null;
};

export type SaveR2SettingsInput = {
  endpoint?: string | null;
  bucket?: string | null;
  region?: string | null;
  accessKeyId?: string | null;
  secretAccessKey?: string | null;
  publicBaseUrl?: string | null;
  backupEnabled?: boolean;
  backupFrequency?: "daily" | "weekly";
  scheduleHourVietnam?: number;
};

function clean(value: string | null | undefined) {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

function validateR2Endpoint(value: string): string {
  let parsed: URL;
  try { parsed = new URL(value); } catch { throw new Error("S3 API endpoint không phải URL hợp lệ."); }
  if (parsed.protocol !== "https:" || !parsed.hostname.toLowerCase().endsWith(".r2.cloudflarestorage.com") || parsed.username || parsed.password || parsed.port || parsed.pathname !== "/" || parsed.search || parsed.hash) {
    throw new Error("S3 API endpoint phải là endpoint HTTPS Cloudflare R2 (…r2.cloudflarestorage.com), không phải public URL.");
  }
  return parsed.origin;
}

function validatePublicBaseUrl(value: string | null): string | null {
  if (!value) return null;
  let parsed: URL;
  try { parsed = new URL(value); } catch { throw new Error("Public base URL không hợp lệ."); }
  if (parsed.protocol !== "https:" || parsed.username || parsed.password || parsed.search || parsed.hash) throw new Error("Public base URL phải là HTTPS, không chứa credentials, query hoặc fragment.");
  return parsed.toString().replace(/\/+$/, "");
}

function encryptionKey(): Buffer {
  const raw = clean(process.env.R2_SETTINGS_ENCRYPTION_KEY);
  if (!raw) {
    throw new Error("Thiếu R2_SETTINGS_ENCRYPTION_KEY: cần cấu hình khóa ổn định server-side để mã hóa secret R2 at-rest.");
  }
  if (Buffer.byteLength(raw, "utf8") < 32) throw new Error("R2_SETTINGS_ENCRYPTION_KEY phải dài tối thiểu 32 byte và cần được giữ ổn định sau khi lưu credentials.");
  return createHash("sha256").update(raw, "utf8").digest();
}

function encryptSecret(value: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", encryptionKey(), iv);
  const ciphertext = Buffer.concat([cipher.update(value, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `${iv.toString("base64url")}.${tag.toString("base64url")}.${ciphertext.toString("base64url")}`;
}

function decryptSecret(value: string | null | undefined): string | null {
  if (!value) return null;
  const parts = value.split(".");
  if (parts.length !== 3) throw new Error("R2 secret lưu trữ không hợp lệ; cần lưu lại cấu hình R2.");
  try {
    const decipher = createDecipheriv("aes-256-gcm", encryptionKey(), Buffer.from(parts[0], "base64url"));
    decipher.setAuthTag(Buffer.from(parts[1], "base64url"));
    return Buffer.concat([decipher.update(Buffer.from(parts[2], "base64url")), decipher.final()]).toString("utf8");
  } catch {
    throw new Error("Không giải mã được secret R2; kiểm tra R2_SETTINGS_ENCRYPTION_KEY có ổn định sau khi restart không.");
  }
}

async function savedSettings() {
  const db = await getDb();
  if (!db) return undefined;
  const rows = await db.select().from(r2Settings).where(eq(r2Settings.id, SETTINGS_ID)).limit(1);
  return rows[0];
}

function envConfig(): R2Config | null {
  const endpoint = clean(process.env.R2_ENDPOINT || process.env.CLOUDFLARE_R2_ENDPOINT);
  const bucket = clean(process.env.R2_BUCKET || process.env.CLOUDFLARE_R2_BUCKET);
  const accessKeyId = clean(process.env.R2_ACCESS_KEY_ID || process.env.CLOUDFLARE_R2_ACCESS_KEY_ID);
  const secretAccessKey = clean(process.env.R2_SECRET_ACCESS_KEY || process.env.CLOUDFLARE_R2_SECRET_ACCESS_KEY);
  if (!endpoint && !bucket && !accessKeyId && !secretAccessKey) return null;
  if (!endpoint || !bucket || !accessKeyId || !secretAccessKey) {
    throw new Error("Cấu hình R2 chưa đủ: cần R2_ENDPOINT, R2_BUCKET, R2_ACCESS_KEY_ID và R2_SECRET_ACCESS_KEY.");
  }
  return {
    endpoint: validateR2Endpoint(endpoint),
    bucket,
    accessKeyId,
    secretAccessKey,
    region: clean(process.env.R2_REGION || process.env.CLOUDFLARE_R2_REGION) || DEFAULT_REGION,
    publicBaseUrl: validatePublicBaseUrl(clean(process.env.R2_PUBLIC_BASE_URL || process.env.CLOUDFLARE_R2_PUBLIC_BASE_URL)) || undefined,
  };
}

async function resolveConfig(): Promise<R2Config | null> {
  const row = await savedSettings();
  if (row?.endpoint || row?.bucket || row?.accessKeyIdEncrypted || row?.secretAccessKeyEncrypted) {
    const endpoint = clean(row.endpoint);
    const bucket = clean(row.bucket);
    const accessKeyId = decryptSecret(row.accessKeyIdEncrypted);
    const secretAccessKey = decryptSecret(row.secretAccessKeyEncrypted);
    if (!endpoint || !bucket || !accessKeyId || !secretAccessKey) {
      throw new Error("Cấu hình R2 trong database chưa đủ; cần endpoint, bucket, access key và secret key.");
    }
    return {
      endpoint: validateR2Endpoint(endpoint),
      bucket,
      accessKeyId,
      secretAccessKey,
      region: clean(row.region) || DEFAULT_REGION,
      publicBaseUrl: validatePublicBaseUrl(clean(row.publicBaseUrl)) || undefined,
    };
  }
  return envConfig();
}

function normalizeKey(relKey: string): string {
  const key = relKey.replace(/^\/+/, "").replace(/\\/g, "/");
  if (!key || key.split("/").some((part) => part === ".." || part === ".")) throw new Error("Storage key không hợp lệ.");
  return key;
}

function appendHashSuffix(relKey: string): string {
  const hash = randomUUID().replace(/-/g, "").slice(0, 8);
  const lastDot = relKey.lastIndexOf(".");
  if (lastDot === -1) return `${relKey}_${hash}`;
  return `${relKey.slice(0, lastDot)}_${hash}${relKey.slice(lastDot)}`;
}

/** Old chat records stored the unhashed key even though storagePut wrote the suffixed key. */
function legacyChatKeyPattern(key: string) {
  if (!key.startsWith("special-chat/")) return null;
  const extension = path.extname(key);
  if (!extension) return null;
  const stem = key.slice(0, -extension.length);
  if (/_([a-f0-9]{8})$/i.test(path.basename(stem))) return null;
  const escape = (value: string) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return {
    prefix: `${stem}_`,
    filenamePattern: new RegExp(`^${escape(path.basename(stem))}_[a-f0-9]{8}${escape(extension)}$`, "i"),
  };
}

async function findLegacyLocalChatFile(key: string): Promise<string | null> {
  const pattern = legacyChatKeyPattern(key);
  if (!pattern) return null;
  const directory = path.dirname(localPath(key));
  try {
    const entries = await readdir(directory);
    const matches = entries.filter((entry) => pattern.filenamePattern.test(entry));
    return matches.length === 1 ? path.join(directory, matches[0]) : null;
  } catch (error) {
    if (error && typeof error === "object" && "code" in error && (error as NodeJS.ErrnoException).code === "ENOENT") return null;
    throw error;
  }
}

async function findLegacyR2ChatKey(config: R2Config, key: string): Promise<string | null> {
  const pattern = legacyChatKeyPattern(key);
  if (!pattern) return null;
  try {
    const result = await clientFor(config).send(new ListObjectsV2Command({ Bucket: config.bucket, Prefix: pattern.prefix, MaxKeys: 25 }));
    const matches = (result.Contents ?? []).flatMap((item) => item.Key && pattern.filenamePattern.test(path.basename(item.Key)) ? [item.Key] : []);
    return matches.length === 1 ? matches[0] : null;
  } catch {
    // Listing permission may not be enabled; current uploads use the exact saved key and do not need this fallback.
    return null;
  }
}

function localPath(key: string): string {
  const normalized = normalizeKey(key);
  const candidate = path.resolve(LOCAL_ROOT, normalized);
  if (candidate !== LOCAL_ROOT && !candidate.startsWith(`${LOCAL_ROOT}${path.sep}`)) throw new Error("Storage key vượt ngoài thư mục private.");
  return candidate;
}

function clientFor(config: R2Config) {
  return new S3Client({ endpoint: config.endpoint, region: config.region || DEFAULT_REGION, forcePathStyle: true, credentials: { accessKeyId: config.accessKeyId, secretAccessKey: config.secretAccessKey } });
}

export async function storageBackend(): Promise<"r2" | "local"> {
  return (await resolveConfig()) ? "r2" : "local";
}

export async function storagePut(relKey: string, data: Buffer | Uint8Array | string, contentType = "application/octet-stream", cacheControl = "private, no-store"): Promise<{ key: string; url: string; backend: "r2" | "local" }> {
  const key = appendHashSuffix(normalizeKey(relKey));
  const config = await resolveConfig();
  const bytes = typeof data === "string" ? Buffer.from(data, "utf8") : Buffer.from(data);
  if (!config) {
    const file = localPath(key);
    await mkdir(path.dirname(file), { recursive: true, mode: 0o700 });
    await writeFile(file, bytes, { mode: 0o600 });
    return { key, url: `/api/private-storage/${encodeURIComponent(key)}`, backend: "local" };
  }
  await clientFor(config).send(new PutObjectCommand({ Bucket: config.bucket, Key: key, Body: bytes, ContentType: contentType, CacheControl: cacheControl }));
  return { key, url: `/api/private-storage/${encodeURIComponent(key)}`, backend: "r2" };
}

/** Store deliberately public movie/TV artwork outside the private chat/backup namespace. */
export async function storagePutPublic(relKey: string, data: Buffer | Uint8Array | string, contentType = "application/octet-stream"): Promise<{ key: string; url: string; backend: "r2" | "local" }> {
  const normalized = normalizeKey(relKey);
  const publicKey = normalized.startsWith("public-assets/") ? normalized : `public-assets/${normalized}`;
  const stored = await storagePut(publicKey, data, contentType, "public, max-age=31536000, immutable");
  const config = await resolveConfig();
  const encodedKey = stored.key.split("/").map(encodeURIComponent).join("/");
  const url = config?.publicBaseUrl
    ? `${config.publicBaseUrl.replace(/\/+$/, "")}/${encodedKey}`
    : `/api/public-storage/${encodedKey}`;
  return { ...stored, url };
}

export async function storageRead(relKey: string): Promise<Buffer> {
  const key = normalizeKey(relKey);
  const config = await resolveConfig();
  if (!config) {
    try { return await readFile(localPath(key)); }
    catch (error) {
      if (!(error && typeof error === "object" && "code" in error && (error as NodeJS.ErrnoException).code === "ENOENT")) throw error;
      const legacyFile = await findLegacyLocalChatFile(key);
      if (legacyFile) return readFile(legacyFile);
      throw error;
    }
  }
  try {
    const response = await clientFor(config).send(new GetObjectCommand({ Bucket: config.bucket, Key: key }));
    if (!response.Body) throw new Error("Storage trả về object rỗng.");
    return Buffer.from(await response.Body.transformToByteArray());
  } catch (remoteError) {
    const legacyKey = await findLegacyR2ChatKey(config, key);
    if (legacyKey) {
      try {
        const response = await clientFor(config).send(new GetObjectCommand({ Bucket: config.bucket, Key: legacyKey }));
        if (response.Body) return Buffer.from(await response.Body.transformToByteArray());
      } catch { /* Continue to the protected local fallback. */ }
    }
    // Files uploaded while R2 was not configured remain readable after migration.
    try { return await readFile(localPath(key)); }
    catch {
      const legacyFile = await findLegacyLocalChatFile(key);
      if (legacyFile) return readFile(legacyFile);
      throw remoteError;
    }
  }
}

export async function storageDelete(relKey: string): Promise<void> {
  const key = normalizeKey(relKey);
  const config = await resolveConfig();
  if (!config) {
    await rm(localPath(key), { force: true });
    return;
  }
  await clientFor(config).send(new DeleteObjectCommand({ Bucket: config.bucket, Key: key }));
  await rm(localPath(key), { force: true });
}

export async function storageGetSignedUrl(relKey: string): Promise<string | null> {
  const key = normalizeKey(relKey);
  const config = await resolveConfig();
  if (!config) return null;
  let actualKey = key;
  try {
    await clientFor(config).send(new HeadObjectCommand({ Bucket: config.bucket, Key: key }));
  } catch (remoteError) {
    const legacyKey = await findLegacyR2ChatKey(config, key);
    if (legacyKey) {
      try {
        await clientFor(config).send(new HeadObjectCommand({ Bucket: config.bucket, Key: legacyKey }));
        actualKey = legacyKey;
      } catch { /* Try local fallback below. */ }
    }
    if (actualKey === key) {
      try { await readFile(localPath(key)); return null; }
      catch {
        const legacyFile = await findLegacyLocalChatFile(key);
        if (legacyFile) return null;
        throw remoteError;
      }
    }
  }
  return getSignedUrl(clientFor(config), new GetObjectCommand({ Bucket: config.bucket, Key: actualKey, ResponseCacheControl: "private, no-store" }), { expiresIn: 300 });
}

export async function testR2Connection(): Promise<{ ok: true; backend: "r2"; key: string; bytes: number }> {
  const config = await resolveConfig();
  if (!config) throw new Error("R2 chưa được cấu hình; đang dùng local private uploads nên không thể test R2.");
  const key = `healthchecks/r2-${Date.now()}-${randomUUID()}.txt`;
  const payload = Buffer.from(`Cinemora R2 connectivity ${new Date().toISOString()}`, "utf8");
  const client = clientFor(config);
  try {
    await client.send(new PutObjectCommand({ Bucket: config.bucket, Key: key, Body: payload, ContentType: "text/plain" }));
    await client.send(new HeadObjectCommand({ Bucket: config.bucket, Key: key }));
    const downloaded = await client.send(new GetObjectCommand({ Bucket: config.bucket, Key: key }));
    const bytes = downloaded.Body ? Buffer.from(await downloaded.Body.transformToByteArray()) : Buffer.alloc(0);
    if (!bytes.equals(payload)) throw new Error("Object test tải xuống không trùng dữ liệu đã upload.");
    return { ok: true, backend: "r2", key, bytes: bytes.length };
  } finally {
    await client.send(new DeleteObjectCommand({ Bucket: config.bucket, Key: key })).catch(() => undefined);
  }
}

export async function getR2PublicSettings(): Promise<R2PublicSettings> {
  const row = await savedSettings();
  const hasSavedR2 = Boolean(row?.endpoint || row?.bucket || row?.accessKeyIdEncrypted || row?.secretAccessKeyEncrypted);
  const env = hasSavedR2 ? null : envConfig();
  const endpoint = clean(row?.endpoint) || env?.endpoint || null;
  const bucket = clean(row?.bucket) || env?.bucket || null;
  const publicBaseUrl = validatePublicBaseUrl(clean(row?.publicBaseUrl) || env?.publicBaseUrl || null);
  const accessConfigured = Boolean(row?.accessKeyIdEncrypted || env?.accessKeyId);
  const secretConfigured = Boolean(row?.secretAccessKeyEncrypted || env?.secretAccessKey);
  const encryptionKeyConfigured = Buffer.byteLength(clean(process.env.R2_SETTINGS_ENCRYPTION_KEY) || "", "utf8") >= 32;
  const storedSecretsNeedKey = Boolean(row?.accessKeyIdEncrypted || row?.secretAccessKeyEncrypted);
  const configured = Boolean(endpoint && bucket && accessConfigured && secretConfigured && (!storedSecretsNeedKey || encryptionKeyConfigured));
  return {
    configured,
    backend: configured ? "r2" : "local",
    endpoint,
    bucket,
    region: clean(row?.region) || env?.region || DEFAULT_REGION,
    publicBaseUrl,
    hasAccessKeyId: accessConfigured,
    hasSecretAccessKey: secretConfigured,
    encryptionKeyConfigured,
    backupEnabled: Boolean(row?.backupEnabled),
    backupFrequency: row?.backupFrequency === "weekly" ? "weekly" : "daily",
    scheduleHourVietnam: Math.min(23, Math.max(0, Number(row?.scheduleHourVietnam ?? ((Number(row?.scheduleHourUtc ?? 2) + 7) % 24)))),
    updatedAt: row?.updatedAt ? new Date(row.updatedAt).toISOString() : null,
  };
}

export async function saveR2Settings(input: SaveR2SettingsInput): Promise<R2PublicSettings> {
  const db = await getDb();
  if (!db) throw new Error("Database is not available; không thể lưu cấu hình R2.");
  const current = await savedSettings();
  const environment = current ? null : envConfig();
  const accessKeyId = clean(input.accessKeyId) || (current?.accessKeyIdEncrypted ? decryptSecret(current.accessKeyIdEncrypted) : environment?.accessKeyId || null);
  const secretAccessKey = clean(input.secretAccessKey) || (current?.secretAccessKeyEncrypted ? decryptSecret(current.secretAccessKeyEncrypted) : environment?.secretAccessKey || null);
  const rawEndpoint = clean(input.endpoint) ?? clean(current?.endpoint) ?? environment?.endpoint ?? null;
  const endpoint = rawEndpoint ? validateR2Endpoint(rawEndpoint) : null;
  const bucket = clean(input.bucket) ?? clean(current?.bucket) ?? environment?.bucket ?? null;
  const hasAnyR2 = Boolean(endpoint || bucket || accessKeyId || secretAccessKey);
  if (hasAnyR2 && (!endpoint || !bucket || !accessKeyId || !secretAccessKey)) {
    throw new Error("Cấu hình R2 chưa đủ: cần endpoint, bucket, access key và secret key.");
  }
  const encryptedAccess = accessKeyId ? encryptSecret(accessKeyId) : null;
  const encryptedSecret = secretAccessKey ? encryptSecret(secretAccessKey) : null;
  const scheduleHourVietnam = Math.min(23, Math.max(0, Math.floor(input.scheduleHourVietnam ?? Number(current?.scheduleHourVietnam ?? ((Number(current?.scheduleHourUtc ?? 2) + 7) % 24)))));
  const scheduleHourUtc = (scheduleHourVietnam + 17) % 24;
  const values = {
    id: SETTINGS_ID,
    endpoint,
    bucket,
    region: clean(input.region) ?? clean(current?.region) ?? environment?.region ?? DEFAULT_REGION,
    accessKeyIdEncrypted: encryptedAccess,
    secretAccessKeyEncrypted: encryptedSecret,
    publicBaseUrl: input.publicBaseUrl !== undefined ? validatePublicBaseUrl(clean(input.publicBaseUrl)) : validatePublicBaseUrl(clean(current?.publicBaseUrl) ?? environment?.publicBaseUrl ?? null),
    backupEnabled: input.backupEnabled ?? Boolean(current?.backupEnabled),
    backupFrequency: input.backupFrequency ?? (current?.backupFrequency === "weekly" ? "weekly" : "daily"),
    scheduleHourUtc,
    scheduleHourVietnam,
  } as const;
  await db.insert(r2Settings).values(values).onDuplicateKeyUpdate({ set: { endpoint: values.endpoint, bucket: values.bucket, region: values.region, accessKeyIdEncrypted: values.accessKeyIdEncrypted, secretAccessKeyEncrypted: values.secretAccessKeyEncrypted, publicBaseUrl: values.publicBaseUrl, backupEnabled: values.backupEnabled, backupFrequency: values.backupFrequency, scheduleHourUtc: values.scheduleHourUtc, scheduleHourVietnam: values.scheduleHourVietnam } });
  return getR2PublicSettings();
}
