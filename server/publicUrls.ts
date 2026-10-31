const DEFAULT_PUBLIC_ORIGIN = "https://cungcapicloud.id.vn";

/**
 * Convert a stored relative image path to an absolute public URL.
 * Only HTTP(S) URLs are passed through; relative paths always resolve from the
 * site root so `/uploads/...` never accidentally resolves beneath `/api/...`.
 */
export function absoluteMovieArtworkUrl(value: unknown, publicBaseUrl = process.env.PUBLIC_BASE_URL || DEFAULT_PUBLIC_ORIGIN): string | null {
  if (typeof value !== "string") return null;
  const raw = value.trim();
  if (!raw) return null;

  const hasScheme = /^[a-z][a-z0-9+.-]*:/i.test(raw);
  if (hasScheme) {
    try {
      const parsed = new URL(raw);
      return parsed.protocol === "http:" || parsed.protocol === "https:" ? parsed.toString() : null;
    } catch {
      return null;
    }
  }

  if (raw.startsWith("//")) {
    try { return new URL(`https:${raw}`).toString(); }
    catch { return null; }
  }

  try {
    const base = new URL(publicBaseUrl);
    if (base.protocol !== "https:" && base.protocol !== "http:") return null;
    const origin = base.origin;
    const rootRelativePath = raw.startsWith("/") ? raw : `/${raw}`;
    return new URL(rootRelativePath, `${origin}/`).toString();
  } catch {
    return null;
  }
}
