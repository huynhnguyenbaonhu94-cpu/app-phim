import express, { type Express, type Response } from "express";
import fs from "fs";
import { type Server } from "http";
import path from "path";

function setHtmlNoCacheHeaders(res: Response) {
  res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate");
  res.setHeader("Pragma", "no-cache");
  res.setHeader("Expires", "0");
}

export async function setupVite(app: Express, server: Server) {
  // Dynamic imports: chỉ load vite khi chạy development
  const { createServer: createViteServer } = await import("vite");
  const { nanoid } = await import("nanoid");
  const { default: viteConfig } = await import("../../vite.config");

  const vite = await createViteServer({
    ...viteConfig,
    configFile: false,
    server: {
      middlewareMode: true,
      hmr: { server },
      allowedHosts: true as const,
    },
    appType: "custom",
  });

  app.use(vite.middlewares);
  app.use("*", async (req, res, next) => {
    const url = req.originalUrl;
    try {
      const clientTemplate = path.resolve(
        import.meta.dirname,
        "../..",
        "client",
        "index.html",
      );
      let template = await fs.promises.readFile(clientTemplate, "utf-8");
      template = template.replace(
        `src="/src/main.tsx"`,
        `src="/src/main.tsx?v=${nanoid()}"`,
      );
      const page = await vite.transformIndexHtml(url, template);
      res.status(200).set({
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "no-store, no-cache, must-revalidate, proxy-revalidate",
        Pragma: "no-cache",
        Expires: "0",
      }).end(page);
    } catch (error) {
      vite.ssrFixStacktrace(error as Error);
      next(error);
    }
  });
}

/**
 * Serves one canonical SPA shell for every browser route. `express.static`
 * otherwise treats `/admin/r2-settings` as a directory and may serve a stale
 * nested `admin/r2-settings/index.html` left behind by an overlay deployment.
 * That stale shell can reference hashed CSS/JS bundles that no longer exist.
 */
export function serveStatic(app: Express, buildDirectory = path.resolve(import.meta.dirname, "public")) {
  const distPath = path.resolve(buildDirectory);
  const indexPath = path.join(distPath, "index.html");

  if (!fs.existsSync(indexPath)) {
    console.error(`[Frontend] Build shell missing: ${indexPath}. Restore the complete dist/public directory before serving the website.`);
  }

  app.use(express.static(distPath, {
    index: false,
    redirect: false,
    fallthrough: true,
    setHeaders: (res, filePath) => {
      if (path.extname(filePath).toLowerCase() === ".html") {
        setHtmlNoCacheHeaders(res);
        return;
      }

      const relativePath = path.relative(distPath, filePath).split(path.sep).join("/");
      const fileName = path.basename(filePath);
      const fingerprintedBundle = /-[A-Za-z0-9_-]{8,}\.(?:css|js|woff2|svg|png|webp|avif)$/i.test(fileName);
      if (relativePath.startsWith("assets/") && fingerprintedBundle) {
        res.setHeader("Cache-Control", "public, max-age=31536000, immutable");
      }
    },
  }));

  app.get("*", (req, res, next) => {
    const requestPath = new URL(req.originalUrl, "http://localhost").pathname;
    const isAssetRequest = requestPath.startsWith("/assets/") || path.extname(requestPath) !== "";

    // A missing CSS/JS/image must be a real 404, never the SPA HTML shell.
    if (isAssetRequest) {
      setHtmlNoCacheHeaders(res);
      return res.status(404).type("text/plain").send("Asset not found");
    }

    const acceptsHtml = (req.get("accept") || "").toLowerCase().includes("text/html");
    if (requestPath !== "/" && !acceptsHtml) return res.status(404).end();

    setHtmlNoCacheHeaders(res);
    if (!fs.existsSync(indexPath)) {
      return res.status(503).type("text/plain").send("Website frontend is not built. Restore dist/public and restart the application.");
    }

    return res.sendFile(indexPath, (error) => {
      if (error && !res.headersSent) next(error);
    });
  });
}
