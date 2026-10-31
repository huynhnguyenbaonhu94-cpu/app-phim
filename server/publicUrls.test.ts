import { describe, expect, it } from "vitest";
import { absoluteMovieArtworkUrl } from "./publicUrls";

describe("absoluteMovieArtworkUrl", () => {
  it("prefixes root-relative uploads paths with the public domain", () => {
    expect(absoluteMovieArtworkUrl("/uploads/movie-images/poster.jpg", "https://cungcapicloud.id.vn"))
      .toBe("https://cungcapicloud.id.vn/uploads/movie-images/poster.jpg");
  });

  it("resolves relative upload paths from the site root", () => {
    expect(absoluteMovieArtworkUrl("uploads/movie-images/poster.jpg", "https://cungcapicloud.id.vn/app"))
      .toBe("https://cungcapicloud.id.vn/uploads/movie-images/poster.jpg");
  });

  it("preserves existing HTTPS CDN URLs", () => {
    expect(absoluteMovieArtworkUrl("https://cdn.example.com/poster.jpg", "https://cungcapicloud.id.vn"))
      .toBe("https://cdn.example.com/poster.jpg");
  });

  it("converts protocol-relative URLs to HTTPS", () => {
    expect(absoluteMovieArtworkUrl("//cdn.example.com/poster.jpg", "https://cungcapicloud.id.vn"))
      .toBe("https://cdn.example.com/poster.jpg");
  });

  it("returns null for unsafe protocols and empty values", () => {
    expect(absoluteMovieArtworkUrl("javascript:alert(1)", "https://cungcapicloud.id.vn")).toBeNull();
    expect(absoluteMovieArtworkUrl("  ", "https://cungcapicloud.id.vn")).toBeNull();
  });
});
