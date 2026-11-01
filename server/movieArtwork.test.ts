import { describe, expect, it } from "vitest";
import { isAllowedMovieArtworkSource } from "./movieArtwork";

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
});
