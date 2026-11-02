import { afterEach, describe, expect, it, vi } from "vitest";
import { fetchMovieArtwork, isAllowedMovieArtworkSource } from "./movieArtwork";

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("movie artwork mirror source validation", () => {
  it("accepts HTTPS artwork from the configured movie image hosts", () => {
    expect(isAllowedMovieArtworkSource("https://phimimg.com/poster.jpg")).toBe(true);
    expect(isAllowedMovieArtworkSource("https://images.phimimg.com/poster.webp")).toBe(true);
    expect(isAllowedMovieArtworkSource("https://image.tmdb.org/t/p/w500/poster.jpg")).toBe(true);
  });

  it("rejects non-HTTPS, untrusted, credentialed, and nonstandard-port sources", () => {
    expect(isAllowedMovieArtworkSource("http://phimimg.com/poster.jpg")).toBe(false);
    expect(isAllowedMovieArtworkSource("https://phimimg.com.evil.example/poster.jpg")).toBe(false);
    expect(isAllowedMovieArtworkSource("https://evil.example/phimimg.com/poster.jpg")).toBe(false);
    expect(isAllowedMovieArtworkSource("https://user:pass@phimimg.com/poster.jpg")).toBe(false);
    expect(isAllowedMovieArtworkSource("https://phimimg.com:8443/poster.jpg")).toBe(false);
  });

  it("retries a transient aborted origin request before returning the image", async () => {
    const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0x00]);
    const fetchMock = vi.fn()
      .mockRejectedValueOnce(new Error("This operation was aborted"))
      .mockResolvedValueOnce(new Response(jpeg, { headers: { "content-type": "image/jpeg" } }));
    vi.stubGlobal("fetch", fetchMock);

    const image = await fetchMovieArtwork("https://phimimg.com/poster.jpg");

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(image.type.contentType).toBe("image/jpeg");
    expect(image.bytes).toEqual(jpeg);
  });

  it("detects a real raster format from bytes when the origin MIME is inaccurate", async () => {
    const webp = Buffer.from("RIFF0000WEBP", "ascii");
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(
      new Response(webp, { headers: { "content-type": "image/jpeg" } }),
    ));

    const image = await fetchMovieArtwork("https://phimimg.com/poster.webp");

    expect(image.type.contentType).toBe("image/webp");
    expect(image.type.extension).toBe("webp");
  });

  it("does not waste retries on a permanent 404 source", async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response(null, { status: 404 }));
    vi.stubGlobal("fetch", fetchMock);

    await expect(fetchMovieArtwork("https://phimimg.com/missing.jpg")).rejects.toThrow("404");
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});
