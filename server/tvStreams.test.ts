import { describe, expect, it, vi } from "vitest";
import { checkStreamHealth, validateOptionalUrl, validateStreamUrl } from "./tvStreams";

describe("TV stream audio URL validation", () => {
  it("accepts an optional HTTP(S) audio source and empty values", () => {
    expect(validateOptionalUrl(" https://cdn.example.com/live/audio.m3u8 ", "URL audio")).toBe("https://cdn.example.com/live/audio.m3u8");
    expect(validateOptionalUrl("", "URL audio")).toBeNull();
    expect(validateStreamUrl("https://cdn.example.com/live/video.m3u8")).toBe("https://cdn.example.com/live/video.m3u8");
  });

  it("rejects non-HTTP audio URLs", () => {
    expect(() => validateOptionalUrl("ftp://cdn.example.com/audio.mp3", "URL audio")).toThrow("URL audio không hợp lệ");
  });
});

describe("TV stream health probing", () => {
  it("retries without Range when a CDN rejects the range probe", async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response("", { status: 416 }))
      .mockResolvedValueOnce(new Response("#EXTM3U", { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);
    await expect(checkStreamHealth("https://cdn.example.com/live.m3u8")).resolves.toMatchObject({ status: "online" });
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(fetchMock.mock.calls[0][1].headers.range).toBe("bytes=0-2047");
    expect(fetchMock.mock.calls[1][1].headers.range).toBeUndefined();
    vi.unstubAllGlobals();
  });

  it("does not mark a stream offline when the server cannot verify the CDN", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("connect ECONNREFUSED")));
    await expect(checkStreamHealth("https://cdn.example.com/live.m3u8")).resolves.toMatchObject({ status: "unknown" });
    vi.unstubAllGlobals();
  });

  it("keeps a playable stream visible when a CDN edge temporarily returns 403", async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response("Forbidden", { status: 403 }))
      .mockResolvedValueOnce(new Response("Forbidden", { status: 403 }));
    vi.stubGlobal("fetch", fetchMock);
    await expect(checkStreamHealth("https://cdn.example.com/live.m3u8")).resolves.toMatchObject({ status: "unknown" });
    expect(fetchMock).toHaveBeenCalledTimes(2);
    vi.unstubAllGlobals();
  });
});
