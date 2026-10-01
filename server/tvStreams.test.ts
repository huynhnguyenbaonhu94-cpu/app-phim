import { describe, expect, it } from "vitest";
import { validateOptionalUrl, validateStreamUrl } from "./tvStreams";

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
