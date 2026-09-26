import { describe, expect, it } from "vitest";
import { appRouter } from "./routers";
import { getStreamSource, MAX_CINEMA_PAGE, registerStreamSource } from "./cinema";
import type { TrpcContext } from "./_core/context";

function caller() {
  return appRouter.createCaller({
    user: undefined,
    req: {} as TrpcContext["req"],
    res: {} as TrpcContext["res"],
  });
}

describe("cinema proxy guardrails", () => {
  it("rejects page numbers beyond the supported catalog range", async () => {
    await expect(caller().cinema.home({ page: MAX_CINEMA_PAGE + 1 })).rejects.toMatchObject({ code: "BAD_REQUEST" });
  });

  it("rejects a detail slug containing URL traversal characters", async () => {
    await expect(caller().cinema.detail({ slug: "../secrets" })).rejects.toMatchObject({ code: "BAD_REQUEST" });
  });

  it("rejects a search keyword shorter than two characters", async () => {
    await expect(caller().cinema.search({ keyword: "a" })).rejects.toMatchObject({ code: "BAD_REQUEST" });
  });

  it("creates stream proxy tokens for the supported HLS CDN hosts", () => {
    expect(registerStreamSource("https://evil.example/video/index.m3u8")).toBeNull();
    const proxy = registerStreamSource("https://a.kvp726.com/20260919/WRv88Vl3/index.m3u8");
    expect(proxy).toMatch(/^\/api\/cinema\/stream\/[a-f0-9-]+$/);
    expect(getStreamSource(proxy!.split("/").pop()!)).toContain("kvp726.com");

    const kkphim = registerStreamSource("https://v7.kkphimplayer7.com/20260911/eFhwyRD9/index.m3u8");
    expect(kkphim).toMatch(/^\/api\/cinema\/stream\/[a-f0-9-]+$/);
    expect(getStreamSource(kkphim!.split("/").pop()!)).toContain("kkphimplayer7.com");

    const kkphim6 = registerStreamSource("https://s6.kkphimplayer6.com/20260911/eFhwyRD9/index.m3u8");
    expect(kkphim6).toMatch(/^\/api\/cinema\/stream\/[a-f0-9-]+$/);
    expect(getStreamSource(kkphim6!.split("/").pop()!)).toContain("kkphimplayer6.com");

    const cdnPlayer = registerStreamSource("https://s6.cdn-player.com/20260123/t2a4G3hc/index.m3u8");
    expect(cdnPlayer).toMatch(/^\/api\/cinema\/stream\/[a-f0-9-]+$/);
    expect(getStreamSource(cdnPlayer!.split("/").pop()!)).toContain("cdn-player.com");

    const phim1280 = registerStreamSource("https://s3.phim1280.tv/20241118/V0Q6I8l3/index.m3u8");
    expect(phim1280).toMatch(/^\/api\/cinema\/stream\/[a-f0-9-]+$/);
    expect(getStreamSource(phim1280!.split("/").pop()!)).toContain("phim1280.tv");
  });
});
