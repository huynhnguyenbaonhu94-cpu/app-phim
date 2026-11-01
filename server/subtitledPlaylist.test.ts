import { describe, expect, it } from "vitest";
import { attachSidecarSubtitlesToMaster, buildSubtitleMediaPlaylist, buildSubtitledPlaylist } from "./subtitledPlaylist";

const tracks = [
  { id: "vi-id", language: "vi", name: "Tiếng Việt", url: "https://subs.example/vi.vtt" },
  { id: "en-id", language: "en", name: "English", url: "https://subs.example/en.vtt" },
];

describe("subtitled playlist builder", () => {
  it("references valid HLS subtitle media playlists rather than raw VTT files", () => {
    const playlist = buildSubtitledPlaylist("https://cdn.example/video.m3u8", tracks, "https://app.example")!;
    expect(playlist).toContain('NAME="Tiếng Việt [vi-id]"');
    expect(playlist).toContain('LANGUAGE="vi"');
    expect(playlist).toContain('NAME="English [en-id]"');
    expect(playlist).toContain('LANGUAGE="en"');
    expect(playlist).toContain('URI="https://app.example/api/cinema/subtitle-media.m3u8?url=https%3A%2F%2Fsubs.example%2Fvi.vtt"');
    expect(playlist).not.toContain('URI="https://subs.example/vi.vtt"');
    expect(playlist.match(/#EXT-X-MEDIA/g)).toHaveLength(2);
  });

  it("wraps a standalone WebVTT segment in a VOD subtitle media playlist", () => {
    const playlist = buildSubtitleMediaPlaylist("https://subs.example/movie.vtt")!;
    expect(playlist).toContain("#EXTM3U");
    expect(playlist).toContain("#EXT-X-PLAYLIST-TYPE:VOD");
    expect(playlist).toContain("#EXTINF:86400.000,");
    expect(playlist).toContain("https://subs.example/movie.vtt");
    expect(playlist).toContain("#EXT-X-ENDLIST");
    expect(buildSubtitleMediaPlaylist("file:///private/movie.vtt")).toBeNull();
  });

  it("rewrites the VTT segment to an absolute proxy URL and rejects malformed rewrites", () => {
    const playlist = buildSubtitleMediaPlaylist("https://subs.example/movie.vtt?sig=secret", (url) => `https://app.example/api/cinema/stream/${encodeURIComponent(url)}`)!;
    expect(playlist).toContain("https://app.example/api/cinema/stream/https%3A%2F%2Fsubs.example%2Fmovie.vtt%3Fsig%3Dsecret");
    expect(buildSubtitleMediaPlaylist("https://subs.example/movie.vtt", () => "//relative/path")).toBeNull();
  });

  it("attaches sidecar subtitle group to every actual variant in an upstream master", () => {
    const upstream = [
      "#EXTM3U",
      "#EXT-X-VERSION:3",
      '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Main",DEFAULT=YES,AUTOSELECT=YES,URI="audio/en.m3u8"',
      '#EXT-X-STREAM-INF:BANDWIDTH=1200000,AUDIO="audio",SUBTITLES="provider-subs"',
      "video/720.m3u8",
      '#EXT-X-STREAM-INF:BANDWIDTH=3500000,AUDIO="audio"',
      "video/1080.m3u8",
    ].join("\n");
    const playlist = attachSidecarSubtitlesToMaster(
      upstream,
      [tracks[0]],
      "https://app.example",
      "https://cdn.example/master.m3u8",
      (url) => `https://app.example/api/cinema/stream/${encodeURIComponent(url)}`,
    )!;
    expect(playlist.match(/SUBTITLES="cinemora-sidecar"/g)).toHaveLength(2);
    expect(playlist).not.toContain('SUBTITLES="provider-subs"');
    expect(playlist).toContain("https://app.example/api/cinema/stream/https%3A%2F%2Fcdn.example%2Fvideo%2F720.m3u8");
    expect(playlist).toContain("https://app.example/api/cinema/stream/https%3A%2F%2Fcdn.example%2Fvideo%2F1080.m3u8");
    expect(playlist).toContain("https://app.example/api/cinema/stream/https%3A%2F%2Fcdn.example%2Faudio%2Fen.m3u8");
  });

  it("upgrades old master playlist versions and returns null for a media playlist", () => {
    const master = "#EXTM3U\n#EXT-X-VERSION:1\n#EXT-X-STREAM-INF:BANDWIDTH=1000\na.m3u8";
    const result = attachSidecarSubtitlesToMaster(master, [tracks[0]], "https://app.example", "https://cdn.example/master.m3u8", (url) => url)!;
    expect(result).toContain("#EXT-X-VERSION:3");
    expect(attachSidecarSubtitlesToMaster("#EXTM3U\n#EXTINF:4,\nseg.ts", [tracks[0]], "https://app.example", "https://cdn.example/playlist.m3u8", (url) => url)).toBeNull();
  });

  it("limits valid renditions and rejects unsafe video/subtitle URLs", () => {
    const input = Array.from({ length: 14 }, (_, i) => ({ id: `id-${i}`, language: "en", name: `English ${i}`, url: i === 0 ? "javascript:alert(1)" : `https://subs.example/${i}.vtt` }));
    const playlist = buildSubtitledPlaylist("https://cdn.example/video.m3u8", input)!;
    expect(playlist.match(/#EXT-X-MEDIA/g)).toHaveLength(12);
    expect(playlist).not.toContain("javascript:");
    expect(buildSubtitledPlaylist("file:///video.m3u8", [tracks[0]])).toBeNull();
    expect(buildSubtitledPlaylist("https://cdn.example/video.mp4", [tracks[0]])).toBeNull();
  });

  it("sanitizes metadata that would break quoted HLS attributes", () => {
    const playlist = buildSubtitledPlaylist("https://cdn.example/video.m3u8", [{ id: "x", language: "<bad>", name: 'bad",\nINJECT=YES', url: "https://subs.example/x.vtt" }])!;
    expect(playlist).not.toContain("INJECT=YES");
    expect(playlist).toContain('LANGUAGE="und"');
  });
});
