import "dotenv/config";
import express from "express";
import { createServer } from "http";
import net from "net";
import path from "node:path";
import { createExpressMiddleware } from "@trpc/server/adapters/express";
import { registerOAuthRoutes } from "./oauth";
import { registerStorageProxy } from "./storageProxy";
import { appRouter } from "../routers";
import { getEmbedSource, getImageSource, getStreamSource, registerStreamSource, registerStreamSourceFromPlaylist } from "../cinema";
import { createContext } from "./context";
import { serveStatic, setupVite } from "./vite";
import { currentTvStreamsVersion, listTvStreams, refreshAllTvStreamsHealth, subscribeTvStreams } from "../tvStreams";
import { refreshAllTvVideosHealth } from "../tvVideos";
import { initializeDatabase } from "../db";

const tvProxyHosts = new Set(["d4.dhcn.vn", "media.dhcn.vn"]);
const tvProxyOrigin = "https://baothanhhoa.vn";

function getAllowedTvSource(raw: string | undefined) {
  if (!raw) return null;
  try {
    const url = new URL(raw);
    if (url.protocol !== "https:" || !tvProxyHosts.has(url.hostname)) return null;
    return url;
  } catch {
    return null;
  }
}

function tvProxyUrl(source: URL) {
  return `/api/tv/proxy?url=${encodeURIComponent(source.toString())}`;
}

function rewriteTvPlaylist(playlist: string, source: URL) {
  return playlist.split("\n").map((line) => {
    const withUris = line.replace(/URI="([^"]+)"/g, (_match, uri: string) => {
      const absolute = new URL(uri, source).toString();
      const resolved = getAllowedTvSource(absolute);
      return `URI="${resolved ? tvProxyUrl(resolved) : absolute}"`;
    });
    const trimmed = withUris.trim();
    if (!trimmed || trimmed.startsWith("#")) return withUris;
    const absolute = new URL(trimmed, source).toString();
    const resolved = getAllowedTvSource(absolute);
    return resolved ? tvProxyUrl(resolved) : trimmed;
  }).join("\n");
}

function isPortAvailable(port: number): Promise<boolean> {
  return new Promise(resolve => {
    const server = net.createServer();
    server.listen(port, () => {
      server.close(() => resolve(true));
    });
    server.on("error", () => resolve(false));
  });
}

function wait(ms: number) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function fetchImageWithRetry(source: string) {
  let lastError: unknown;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10_000);
    try {
      const response = await fetch(source, {
        headers: { accept: "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", "user-agent": "Cinemora/1.0" },
        signal: controller.signal,
      });
      if (!response.ok || !response.body) throw new Error(`Image upstream ${response.status}`);
      const bytes = Buffer.from(await response.arrayBuffer());
      if (!bytes.length) throw new Error("Image upstream returned an empty body");
      return { contentType: response.headers.get("content-type") || "image/jpeg", bytes };
    } catch (error) {
      lastError = error;
      if (attempt < 2) await wait(180 * (attempt + 1));
    } finally {
      clearTimeout(timeout);
    }
  }
  throw lastError;
}

async function findAvailablePort(startPort: number = 3000): Promise<number> {
  for (let port = startPort; port < startPort + 20; port++) {
    if (await isPortAvailable(port)) {
      return port;
    }
  }
  throw new Error(`No available port found starting from ${startPort}`);
}

async function startServer() {
  try {
    await initializeDatabase();
    console.log("[Database] Migration and default admin check completed.");
  } catch (error) {
    console.error("[Database] Startup initialization failed:", error instanceof Error ? error.message : error);
  }
  const app = express();
  const server = createServer(app);
  const mobileAppOrigins = new Set(
    (process.env.MOBILE_APP_ORIGINS || "capacitor://localhost,http://localhost,https://localhost")
      .split(",")
      .map(origin => origin.trim())
      .filter(Boolean)
  );
  app.disable("x-powered-by");
  app.use((req, res, next) => {
    const origin = req.get("Origin");
    if (origin && mobileAppOrigins.has(origin)) {
      res.setHeader("Access-Control-Allow-Origin", origin);
      res.setHeader("Access-Control-Allow-Credentials", "true");
      res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
      res.setHeader("Access-Control-Allow-Headers", req.get("Access-Control-Request-Headers") || "Content-Type, Authorization");
      res.vary("Origin");
    }
    if (req.method === "OPTIONS") {
      if (origin && !mobileAppOrigins.has(origin)) return res.sendStatus(403);
      return res.sendStatus(204);
    }
    next();
  });
  app.use((_req, res, next) => {
    res.setHeader("X-Content-Type-Options", "nosniff");
    res.setHeader("Referrer-Policy", "no-referrer");
    res.setHeader("Permissions-Policy", 'camera=(), microphone=(), geolocation=(), fullscreen=(self "https://player.phimapi.com")');
    next();
  });
  // Configure body parser with larger size limit for file uploads
  app.use(express.json({ limit: "50mb" }));
  app.use(express.urlencoded({ limit: "50mb", extended: true }));
  app.use("/uploads", express.static(path.resolve(process.cwd(), "uploads"), { maxAge: "7d", fallthrough: true }));
  app.get("/api/tv/events", async (req, res) => {
    res.status(200);
    res.setHeader("Content-Type", "text/event-stream; charset=utf-8");
    res.setHeader("Cache-Control", "no-cache, no-transform");
    res.setHeader("Connection", "keep-alive");
    res.setHeader("X-Accel-Buffering", "no");
    res.flushHeaders();
    const sendSnapshot = async () => {
      if (res.writableEnded) return;
      const streams = await listTvStreams(false);
      res.write(`event: snapshot\ndata: ${JSON.stringify({ version: currentTvStreamsVersion(), streams })}\n\n`);
    };
    await sendSnapshot();
    const unsubscribe = subscribeTvStreams(() => { void sendSnapshot(); });
    const heartbeat = setInterval(() => res.write(`: heartbeat ${Date.now()}\n\n`), 25_000);
    req.on("close", () => { clearInterval(heartbeat); unsubscribe(); });
  });
  // DHCN requires the baothanhhoa.vn Origin even for the playlist request.
  // Browsers cannot set Origin/Referer from JavaScript, so proxy allowlisted
  // HLS resources and rewrite every playlist URI through this route.
  app.get("/api/tv/proxy", async (req, res) => {
    const source = getAllowedTvSource(typeof req.query.url === "string" ? req.query.url : undefined);
    if (!source) return res.status(400).send("TV source không hợp lệ");
    try {
      const headers: Record<string, string> = {
        accept: "*/*",
        origin: tvProxyOrigin,
        referer: `${tvProxyOrigin}/`,
        "user-agent": "Mozilla/5.0 (compatible; Cinemora-TV/1.0)",
      };
      if (typeof req.headers.range === "string") headers.range = req.headers.range;
      const upstream = await fetch(source, { headers, redirect: "follow" });
      if (!upstream.ok) return res.status(upstream.status === 404 ? 404 : 502).send("TV source unavailable");
      const contentType = upstream.headers.get("content-type") || "";
      const isPlaylist = source.pathname.endsWith(".m3u8") || contentType.includes("mpegurl") || contentType.includes("vnd.apple");
      res.setHeader("Access-Control-Allow-Origin", "*");
      res.setHeader("Cache-Control", "no-store, no-cache");
      if (isPlaylist) {
        res.setHeader("Content-Type", "application/vnd.apple.mpegurl");
        return res.status(200).send(rewriteTvPlaylist(await upstream.text(), source));
      }
      res.setHeader("Content-Type", contentType || (source.pathname.endsWith(".ts") ? "video/mp2t" : "application/octet-stream"));
      if (upstream.status === 206) res.status(206);
      return res.send(Buffer.from(await upstream.arrayBuffer()));
    } catch (error) {
      console.warn("[TV] HLS proxy failed", error instanceof Error ? error.message : error);
      return res.status(502).send("TV source unavailable");
    }
  });
  // HTML phải luôn được kiểm tra phiên bản mới; các bundle Vite đã có hash
  // trong tên file nên có thể cache dài hạn an toàn.
  app.use((req, res, next) => {
    if (req.path === "/" || req.path.endsWith(".html")) {
      res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate");
      res.setHeader("Pragma", "no-cache");
      res.setHeader("Expires", "0");
    }
    next();
  });
  registerStorageProxy(app);
  registerOAuthRoutes(app);
  app.get("/api/cinema/image/:token", async (req, res) => {
    const source = getImageSource(req.params.token);
    if (!source) return res.status(404).send("Not found");
    try {
      const image = await fetchImageWithRetry(source);
      res.setHeader("Cache-Control", "public, max-age=7200, stale-while-revalidate=86400"); // match 2h token TTL
      res.setHeader("Content-Type", image.contentType);
      return res.status(200).send(image.bytes);
    } catch (error) {
      console.warn("[cinema] image proxy failed after retries", error instanceof Error ? error.message : "unknown");
      return res.status(502).send("Image unavailable");
    }
  });
/**
 * Các CDN HLS (kkphimplayer, kvp726…) thường chặn theo Referer/Origin và có thể
 * chặn cả User-Agent. Trình duyệt không tự đặt được các header này, nên máy chủ
 * thử lần lượt vài hồ sơ rồi ghi nhớ hồ sơ chạy được cho từng host.
 */
const STREAM_HEADER_PROFILES: Array<{ label: string; referer?: string; origin?: string; selfOrigin?: boolean }> = [
  { label: "khong-referer" },
  { label: "phimapi", referer: "https://player.phimapi.com/", origin: "https://player.phimapi.com" },
  { label: "kkphim", referer: "https://kkphim.com/", origin: "https://kkphim.com" },
  { label: "phim1280", referer: "https://phim1280.tv/", origin: "https://phim1280.tv" },
  { label: "cung-host", selfOrigin: true },
];
const streamProfileCache = new Map<string, number>();
const STREAM_USER_AGENT =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";

async function fetchStreamUpstream(url: string, range?: string): Promise<Response | null> {
  const parsed = new URL(url);
  const cached = streamProfileCache.get(parsed.hostname);
  const order: number[] = [];
  if (typeof cached === "number") order.push(cached);
  STREAM_HEADER_PROFILES.forEach((_profile, index) => { if (!order.includes(index)) order.push(index); });
  let lastResponse: Response | null = null;
  for (const index of order) {
    const profile = STREAM_HEADER_PROFILES[index];
    const headers: Record<string, string> = { "user-agent": STREAM_USER_AGENT, accept: "*/*" };
    if (profile.selfOrigin) {
      headers.referer = `${parsed.origin}/`;
      headers.origin = parsed.origin;
    } else if (profile.referer) {
      headers.referer = profile.referer;
      if (profile.origin) headers.origin = profile.origin;
    }
    if (range) headers.range = range;
    try {
      const response = await fetch(url, { headers });
      if (response.ok) {
        streamProfileCache.set(parsed.hostname, index);
        return response;
      }
      lastResponse = response;
      console.warn(`[Cinema] ${parsed.hostname} trả ${response.status} với hồ sơ "${profile.label}".`);
    } catch (error) {
      console.warn(`[Cinema] Không gọi được ${parsed.hostname} với "${profile.label}":`, error instanceof Error ? error.message : error);
    }
  }
  return lastResponse;
}

  app.get("/api/cinema/stream/:token", async (req, res) => {
    const source = getStreamSource(req.params.token);
    if (!source) return res.status(404).send("Stream not found");
    try {
      const upstream = await fetchStreamUpstream(source, typeof req.headers.range === "string" ? req.headers.range : undefined);
      if (!upstream || !upstream.ok) return res.status(502).send("Stream unavailable");
      const contentType = upstream.headers.get("content-type") || "";
      const isPlaylist = source.includes(".m3u8") || contentType.includes("mpegurl") || contentType.includes("vnd.apple");
      res.setHeader("Access-Control-Allow-Origin", "*");
      res.setHeader("Access-Control-Expose-Headers", "Content-Length, Content-Range, Accept-Ranges");
      res.setHeader("Cache-Control", isPlaylist ? "no-store" : "public, max-age=60");
      if (isPlaylist) {
        const playlist = await upstream.text();
        const rewritten = playlist.split("\n").map((line) => {
          const trimmed = line.trim();
          if (!trimmed) return line;
          // URI="..." gồm cả EXT-X-KEY và EXT-X-MAP. Nếu tạo token thất bại thì
          // phải giữ nguyên link gốc — trả về chuỗi rỗng sẽ làm hỏng cả playlist.
          const withUris = line.replace(/URI="([^"]+)"/g, (_match, uri: string) => {
            const absolute = new URL(uri, source).toString();
            return `URI="${registerStreamSourceFromPlaylist(absolute) || absolute}"`;
          });
          if (trimmed.startsWith("#")) return withUris;
          const absolute = new URL(trimmed, source).toString();
          return registerStreamSourceFromPlaylist(absolute) || absolute;
        }).join("\n");
        res.setHeader("Content-Type", "application/vnd.apple.mpegurl");
        return res.status(200).send(rewritten);
      }
      const acceptRanges = upstream.headers.get("accept-ranges");
      if (acceptRanges) res.setHeader("Accept-Ranges", acceptRanges);
      const contentRange = upstream.headers.get("content-range");
      if (contentRange) res.setHeader("Content-Range", contentRange);
      res.setHeader("Content-Type", contentType || "video/mp2t");
      const bytes = Buffer.from(await upstream.arrayBuffer());
      return res.status(upstream.status === 206 ? 206 : 200).send(bytes);
    } catch (error) {
      console.warn("[Cinema] Proxy luồng phim lỗi:", error instanceof Error ? error.message : error);
      return res.status(502).send("Stream unavailable");
    }
  });
  app.get("/api/cinema/player/:token", (req, res) => {
    const source = getEmbedSource(req.params.token);
    if (!source) return res.status(404).send("Not found");
    return res.redirect(302, source);
  });
  // tRPC API
  app.use(
    "/api/trpc",
    createExpressMiddleware({
      router: appRouter,
      createContext,
    })
  );
  // Cho biết bản build đang chạy có những tính năng nào. Dùng để kiểm tra nhanh
  // sau khi triển khai: mở /api/health và xem hasBadgeProcedure, hasWatchComments.
  app.get("/api/health", (_req, res) => {
    let procedures: string[] = [];
    try {
      const def = (appRouter as unknown as { _def?: { procedures?: Record<string, unknown> } })._def;
      procedures = Object.keys(def?.procedures ?? {});
    } catch {
      procedures = [];
    }
    res.setHeader("Cache-Control", "no-store");
    res.json({
      ok: true,
      node: process.version,
      uptimeSeconds: Math.round(process.uptime()),
      procedureCount: procedures.length,
      hasBadgeProcedure: procedures.includes("adminAccounts.setBadge"),
      hasWatchComments: procedures.includes("cinema.watchComments"),
      hasPinComment: procedures.includes("cinema.pinComment"),
      hasAvatarProcedures: procedures.includes("account.setAvatar") && procedures.includes("account.clearAvatar"),
    });
  });
  // Mọi đường dẫn /api không khớp phải trả JSON. Nếu để rơi xuống catch-all bên
  // dưới, máy chủ sẽ trả index.html và trình duyệt báo lỗi khó hiểu:
  // "Unexpected token '<', "<!DOCTYPE "... is not valid JSON".
  app.use("/api", (_req, res) => {
    res.setHeader("Cache-Control", "no-store");
    res.status(404).json({
      error: "Không tìm thấy API này. Bản build đang chạy có thể chưa được cập nhật — hãy build lại và Restart ứng dụng.",
    });
  });
  // development mode uses Vite, production mode uses static files
  if (process.env.NODE_ENV === "development") {
    await setupVite(app, server);
  } else {
    serveStatic(app);
  }

  const preferredPort = parseInt(process.env.PORT || "3000");
  const port = await findAvailablePort(preferredPort);

  if (port !== preferredPort) {
    console.log(`Port ${preferredPort} is busy, using port ${port} instead`);
  }

  let healthCheckRunning = false;
  const runTvHealthCheck = async () => {
    if (healthCheckRunning) return;
    healthCheckRunning = true;
    try {
      await refreshAllTvStreamsHealth();
    } catch (error) {
      console.warn("[TV] Health check failed:", error instanceof Error ? error.message : error);
    } finally {
      healthCheckRunning = false;
    }
  };
  void runTvHealthCheck();
  const tvHealthTimer = setInterval(() => { void runTvHealthCheck(); }, 30_000);
  tvHealthTimer.unref?.();
  let videoHealthCheckRunning = false;
  const runTvVideoHealthCheck = async () => {
    if (videoHealthCheckRunning) return;
    videoHealthCheckRunning = true;
    try { await refreshAllTvVideosHealth(); }
    catch (error) { console.warn("[TV] Video health check failed:", error instanceof Error ? error.message : error); }
    finally { videoHealthCheckRunning = false; }
  };
  void runTvVideoHealthCheck();
  const tvVideoHealthTimer = setInterval(() => { void runTvVideoHealthCheck(); }, 60_000);
  tvVideoHealthTimer.unref?.();

  server.listen(port, () => {
    console.log(`Server running on http://localhost:${port}/`);
  });
}

startServer().catch(console.error);
