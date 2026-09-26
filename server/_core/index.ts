import "dotenv/config";
import express from "express";
import { createServer } from "http";
import net from "net";
import { createExpressMiddleware } from "@trpc/server/adapters/express";
import { registerOAuthRoutes } from "./oauth";
import { registerStorageProxy } from "./storageProxy";
import { appRouter } from "../routers";
import { getEmbedSource, getImageSource, getStreamSource, registerStreamSource } from "../cinema";
import { createContext } from "./context";
import { serveStatic, setupVite } from "./vite";

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
  app.get("/api/cinema/stream/:token", async (req, res) => {
    const source = getStreamSource(req.params.token);
    if (!source) return res.status(404).send("Stream not found");
    try {
      const requestHeaders: Record<string, string> = {
        "user-agent": "Cinemora/1.0",
        accept: "*/*",
        referer: "https://player.phimapi.com/",
        origin: "https://player.phimapi.com",
      };
      if (req.headers.range) requestHeaders.range = req.headers.range;
      const upstream = await fetch(source, { headers: requestHeaders });
      if (!upstream.ok) return res.status(502).send("Stream unavailable");
      const contentType = upstream.headers.get("content-type") || "";
      const isPlaylist = source.includes(".m3u8") || contentType.includes("mpegurl") || contentType.includes("vnd.apple");
      res.setHeader("Access-Control-Allow-Origin", "*");
      res.setHeader("Cache-Control", isPlaylist ? "no-store" : "public, max-age=60");
      if (isPlaylist) {
        const playlist = await upstream.text();
        const rewritten = playlist.split("\n").map((line) => {
          const trimmed = line.trim();
          if (!trimmed) return line;
          const withUris = line.replace(/URI="([^"]+)"/g, (_match, uri: string) => {
            const tokenUrl = registerStreamSource(new URL(uri, source).toString());
            return `URI="${tokenUrl || ""}"`;
          });
          if (trimmed.startsWith("#")) return withUris;
          const tokenUrl = registerStreamSource(new URL(trimmed, source).toString());
          return tokenUrl || "";
        }).join("\n");
        res.setHeader("Content-Type", "application/vnd.apple.mpegurl");
        return res.status(200).send(rewritten);
      }
      res.setHeader("Content-Type", contentType || "video/mp2t");
      const bytes = Buffer.from(await upstream.arrayBuffer());
      return res.status(upstream.status === 206 ? 206 : 200).send(bytes);
    } catch {
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

  server.listen(port, () => {
    console.log(`Server running on http://localhost:${port}/`);
  });
}

startServer().catch(console.error);
