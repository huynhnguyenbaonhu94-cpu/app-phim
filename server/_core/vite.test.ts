import express from "express";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { Server } from "node:http";
import { serveStatic } from "./vite";

describe("production SPA static serving", () => {
  let buildDirectory = "";
  let server: Server | null = null;
  let origin = "";

  const adminRoutes = [
    "/admin",
    "/admin/tv",
    "/admin/accounts",
    "/admin/special-chat",
    "/admin/r2-settings",
    "/admin/movie-requests",
    "/admin/movies",
    "/admin/movies/custom/new",
    "/admin/movies/custom/42",
    "/admin/movies/sources",
  ];

  beforeAll(async () => {
    buildDirectory = await mkdtemp(path.join(os.tmpdir(), "cinemora-static-test-"));
    await mkdir(path.join(buildDirectory, "assets"), { recursive: true });
    await writeFile(path.join(buildDirectory, "index.html"), "<!doctype html><title>CURRENT SPA SHELL</title>");
    await writeFile(path.join(buildDirectory, "assets", "index-a1b2c3d4.css"), "body { color: white; }");

    // Simulate an older overlay deployment that left a generated route folder behind.
    const stalePage = path.join(buildDirectory, "admin", "r2-settings");
    await mkdir(stalePage, { recursive: true });
    await writeFile(path.join(stalePage, "index.html"), "STALE NESTED ADMIN SHELL");

    const app = express();
    serveStatic(app, buildDirectory);
    await new Promise<void>((resolve, reject) => {
      const listeningServer = app.listen(0, "127.0.0.1", () => resolve());
      server = listeningServer;
      listeningServer.on("error", reject);
    });
    const address = server?.address();
    if (!address || typeof address === "string") throw new Error("Test server did not bind to a TCP port");
    origin = `http://127.0.0.1:${address.port}`;
  });

  afterAll(async () => {
    const listeningServer = server;
    if (listeningServer) await new Promise<void>((resolve, reject) => listeningServer.close(error => error ? reject(error) : resolve()));
    if (buildDirectory) await rm(buildDirectory, { recursive: true, force: true });
  });

  it.each(["/", ...adminRoutes])("serves the one current HTML shell at %s", async route => {
    const response = await fetch(`${origin}${route}`, { headers: { Accept: "text/html,application/xhtml+xml" } });
    expect(response.status).toBe(200);
    expect(await response.text()).toContain("CURRENT SPA SHELL");
    expect(response.headers.get("cache-control")).toContain("no-store");
  });

  it("does not serve a stale nested admin index.html", async () => {
    const response = await fetch(`${origin}/admin/r2-settings`, { headers: { Accept: "text/html" } });
    const body = await response.text();
    expect(body).not.toContain("STALE NESTED ADMIN SHELL");
    expect(body).toContain("CURRENT SPA SHELL");
  });

  it("caches content-hashed assets immutably", async () => {
    const response = await fetch(`${origin}/assets/index-a1b2c3d4.css`);
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toContain("immutable");
  });

  it("returns a real 404 for missing assets instead of the SPA shell", async () => {
    const response = await fetch(`${origin}/assets/missing.css`, { headers: { Accept: "text/css,*/*;q=0.1" } });
    expect(response.status).toBe(404);
    expect(await response.text()).toBe("Asset not found");
  });

  it("does not return HTML for non-browser unknown routes", async () => {
    const response = await fetch(`${origin}/admin/r2-settings`, { headers: { Accept: "application/json" } });
    expect(response.status).toBe(404);
    expect(await response.text()).not.toContain("CURRENT SPA SHELL");
  });
});
