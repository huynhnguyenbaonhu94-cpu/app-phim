/**
 * Storage facade used by chat, posters and generated media.
 * The backend now prefers Cloudflare R2 (S3-compatible) and safely falls back
 * to a private filesystem directory when R2 is not configured. No Forge token
 * is required for uploads.
 */
import { storagePut as put, storagePutPublic as putPublic, storageRead, storageDelete, storageGetSignedUrl, storageBackend } from "./r2Storage";
import type { Express } from "express";
import { authenticateLocalRequest } from "./localAuth";

export { storageRead, storageDelete, storageGetSignedUrl, storageBackend };

export async function storagePut(
  relKey: string,
  data: Buffer | Uint8Array | string,
  contentType = "application/octet-stream",
): Promise<{ key: string; url: string; backend: "r2" | "local" }> {
  return put(relKey, data, contentType);
}

export async function storagePutPublic(
  relKey: string,
  data: Buffer | Uint8Array | string,
  contentType = "application/octet-stream",
): Promise<{ key: string; url: string; backend: "r2" | "local" }> {
  return putPublic(relKey, data, contentType);
}

export async function storageGet(relKey: string): Promise<{ key: string; url: string }> {
  const backend = await storageBackend();
  return {
    key: relKey.replace(/^\/+/, ""),
    url: backend === "local" ? `/api/private-storage/${encodeURIComponent(relKey.replace(/^\/+/, ""))}` : `/api/private-storage/${encodeURIComponent(relKey.replace(/^\/+/, ""))}`,
  };
}

/** Authenticated-only fallback for non-chat backend uploads (never a public static mount). */
export function registerPrivateStorageRoute(app: Express) {
  app.get("/api/private-storage/*", async (req, res) => {
    const viewer = await authenticateLocalRequest(req);
    if (!viewer) return res.status(401).send("Unauthorized");
    const key = (req.params as Record<string, string>)[0];
    if (!key) return res.status(400).send("Missing storage key");
    const parts = key.split("/");
    if (parts[0] === "special-chat") {
      const ownerId = Number(parts[1]);
      if (!Number.isInteger(ownerId) || ownerId <= 0 || (viewer.role !== "admin" && viewer.id !== ownerId)) return res.status(404).send("Not found");
    } else if (parts[0] === "generated") {
      if (viewer.role !== "admin") return res.status(404).send("Not found");
    } else {
      return res.status(404).send("Not found");
    }
    try {
      res.setHeader("Cache-Control", "private, no-store");
      const extension = key.split(".").pop()?.toLowerCase();
      const contentType = ({ png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", webp: "image/webp", gif: "image/gif", mp4: "video/mp4", mov: "video/quicktime", webm: "video/webm" } as Record<string, string>)[extension || ""] || "application/octet-stream";
      res.setHeader("Content-Type", contentType);
      res.setHeader("X-Content-Type-Options", "nosniff");
      return res.send(await storageRead(key));
    } catch {
      return res.status(404).send("Not found");
    }
  });
}

/** Public movie/TV artwork only. Private chat and backup keys are never readable here. */
export function registerPublicStorageRoute(app: Express) {
  app.get("/api/public-storage/*", async (req, res) => {
    const key = (req.params as Record<string, string>)[0];
    if (!key || !key.startsWith("public-assets/")) return res.status(404).send("Not found");
    const extension = key.split(".").pop()?.toLowerCase();
    const contentType = ({
      jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png", webp: "image/webp", gif: "image/gif", vtt: "text/vtt; charset=utf-8",
    } as Record<string, string>)[extension || ""] || "application/octet-stream";
    try {
      res.setHeader("Cache-Control", "public, max-age=86400, stale-while-revalidate=604800");
      res.setHeader("Content-Type", contentType);
      res.setHeader("X-Content-Type-Options", "nosniff");
      return res.status(200).send(await storageRead(key));
    } catch {
      return res.status(404).send("Not found");
    }
  });
}
