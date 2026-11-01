import { describe, expect, it } from "vitest";
import { buildSubtitledPlaylist } from "./subtitledPlaylist";

describe("subtitled playlist builder", () => {
  it("emits labeled language-specific sidecar tracks", () => {
    const playlist = buildSubtitledPlaylist("https://cdn.example/video.m3u8", [
      { id: "vi-id", language: "vi", name: "Tiếng Việt", url: "https://subs.example/vi.vtt" },
      { id: "en-id", language: "en", name: "English", url: "https://subs.example/en.vtt" },
    ])!;
    expect(playlist).toContain('NAME="Tiếng Việt [vi-id]"');
    expect(playlist).toContain('LANGUAGE="vi"');
    expect(playlist).toContain('NAME="English [en-id]"');
    expect(playlist).toContain('LANGUAGE="en"');
    expect(playlist.match(/#EXT-X-MEDIA/g)).toHaveLength(2);
  });
  it("limits to twelve valid tracks and rejects unsafe schemes", () => {
    const playlist = buildSubtitledPlaylist("https://cdn.example/video.m3u8", Array.from({ length: 14 }, (_, i) => ({ id: `id-${i}`, language: "en", name: `English ${i}`, url: i === 0 ? "javascript:alert(1)" : `https://subs.example/${i}.vtt` })))!;
    expect(playlist.match(/#EXT-X-MEDIA/g)).toHaveLength(12);
    expect(playlist).not.toContain("javascript:");
  });
  it("returns null instead of producing an invalid playlist", () => {
    expect(buildSubtitledPlaylist("file:///video.m3u8", [{ id: "x", language: "en", name: "English", url: "https://subs.example/x.vtt" }])).toBeNull();
    expect(buildSubtitledPlaylist("https://cdn.example/video.mp4", [{ id: "x", language: "en", name: "English", url: "https://subs.example/x.vtt" }])).toBeNull();
    expect(buildSubtitledPlaylist("https://cdn.example/video.m3u8", [{ id: "x", language: "en", name: "English", url: "javascript:bad" }])).toBeNull();
  });
  it("sanitizes metadata that would break quoted HLS attributes", () => {
    const playlist = buildSubtitledPlaylist("https://cdn.example/video.m3u8", [{ id: "x", language: "<bad>", name: 'bad",\nINJECT=YES', url: "https://subs.example/x.vtt" }])!;
    expect(playlist).not.toContain("INJECT=YES");
    expect(playlist).toContain('LANGUAGE="und"');
  });
});
