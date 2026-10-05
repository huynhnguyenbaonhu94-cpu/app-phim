import type { Express } from "express";
import { ENV } from "./env";

export function registerStorageProxy(app: Express) {
  app.get("/manus-storage/*", async (req, res) => {
    const key = (req.params as Record<string, string>)[0];
    if (!key) {
      res.status(400).send("Missing storage key");
      return;
    }

    if (!ENV.forgeApiUrl || !ENV.forgeApiKey) {
      res.status(500).send("Storage proxy not configured");
      return;
    }

    try {
      const forgeUrl = new URL(
        "v1/storage/presign/get",
        ENV.forgeApiUrl.replace(/\/+$/, "") + "/",
      );
      forgeUrl.searchParams.set("path", key);

      let forgeResp: Response | undefined;
      const retryDelays = [0, 300, 900, 1800];
      for (const delay of retryDelays) {
        if (delay) await new Promise((resolve) => setTimeout(resolve, delay));
        try {
          forgeResp = await fetch(forgeUrl, {
            headers: { Authorization: `Bearer ${ENV.forgeApiKey}` },
            signal: AbortSignal.timeout(15_000),
          });
          if (forgeResp.ok || forgeResp.status < 500) break;
        } catch (error) {
          if (delay === retryDelays[retryDelays.length - 1]) throw error;
        }
      }

      const response = forgeResp;
      if (!response || !response.ok) {
        const body = response ? await response.text().catch(() => "") : "no response";
        console.error(`[StorageProxy] forge error: ${response?.status ?? "network"} ${body}`);
        res.status(502).send("Storage backend error");
        return;
      }

      if (!response) {
        res.status(502).send("Storage backend unavailable");
        return;
      }
      const { url } = (await response.json()) as { url: string };
      if (!url) {
        res.status(502).send("Empty signed URL from backend");
        return;
      }

      res.set("Cache-Control", "no-store");
      res.redirect(307, url);
    } catch (err) {
      console.error("[StorageProxy] failed:", err);
      res.status(502).send("Storage proxy error");
    }
  });
}
