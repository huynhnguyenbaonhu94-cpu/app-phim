export type SidecarSubtitle = { id: string; language: string; name: string; url: string };
const MAX_TRACKS = 12;
const SUBTITLE_GROUP_ID = "cinemora-sidecar";
const SUBTITLE_MEDIA_PATH = "/api/cinema/subtitle-media.m3u8";
const WHOLE_ASSET_SEGMENT_SECONDS = 86_400;

const safeText = (value: string, fallback: string, max: number) => {
  const cleaned = value.replace(/[\u0000-\u001f\u007f"\\,=]/g, " ").replace(/\s+/g, " ").trim().slice(0, max);
  return cleaned || fallback;
};

function safeHttpURL(raw: string): string | null {
  try {
    const url = new URL(raw);
    return (url.protocol === "https:" || url.protocol === "http:") && !!url.hostname ? url.toString() : null;
  } catch { return null; }
}

function normalizedTracks(inputTracks: SidecarSubtitle[]): Array<SidecarSubtitle & { safeURL: string; languageTag: string; label: string }> {
  const aliases: Record<string, string> = {
    vietnamese: "vi", "tiếng việt": "vi", english: "en", japanese: "ja", korean: "ko",
    chinese: "zh", french: "fr", spanish: "es", thai: "th", indonesian: "id",
  };
  return inputTracks.flatMap((track, index) => {
    const safeURL = safeHttpURL(track.url);
    if (!safeURL) return [];
    const rawLanguage = track.language.trim().toLowerCase();
    const languageTag = aliases[rawLanguage] ?? (/^[a-zA-Z]{2,3}(?:-[a-zA-Z0-9]{2,8})*$/.test(track.language.trim()) ? track.language.trim().toLowerCase() : "und");
    const id = safeText(track.id, `track-${index + 1}`, 64);
    const label = safeText(track.name, languageTag === "und" ? `Phụ đề ${index + 1}` : languageTag, 60);
    return [{ ...track, id, safeURL, languageTag, label }];
  }).slice(0, MAX_TRACKS);
}

function subtitleRenditionTags(inputTracks: SidecarSubtitle[], origin: string): string[] {
  return normalizedTracks(inputTracks).map((track, index) => {
    const mediaPlaylistURL = `${origin}${SUBTITLE_MEDIA_PATH}?url=${encodeURIComponent(track.safeURL)}`;
    // Keep a stable source ID in NAME because HLS doesn't define a separate
    // rendition ID; AVFoundation can then distinguish same-language tracks.
    const name = `${track.label} [${track.id}]`;
    return `#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="${SUBTITLE_GROUP_ID}",NAME="${name}",DEFAULT=${index === 0 ? "YES" : "NO"},AUTOSELECT=${index === 0 ? "YES" : "NO"},FORCED=NO,LANGUAGE="${track.languageTag}",URI="${mediaPlaylistURL}"`;
  });
}

/**
 * A standalone .vtt URL is a WebVTT segment, not the Media Playlist required by
 * EXT-X-MEDIA:TYPE=SUBTITLES. This route returns the playlist that references it.
 * A single long VOD segment covers the full subtitle timeline; RFC 8216 defines
 * a zero-to-zero timestamp map when a WebVTT segment doesn't contain one.
 */
export function buildSubtitleMediaPlaylist(subtitleRaw: string, rewriteURL: (url: string) => string = (url) => url): string | null {
  const subtitleURL = safeHttpURL(subtitleRaw);
  if (!subtitleURL) return null;
  let segmentURL: string;
  try {
    segmentURL = rewriteURL(subtitleURL);
    if (!safeHttpURL(segmentURL)) return null;
  } catch { return null; }
  return [
    "#EXTM3U",
    "#EXT-X-VERSION:3",
    "#EXT-X-PLAYLIST-TYPE:VOD",
    `#EXT-X-TARGETDURATION:${WHOLE_ASSET_SEGMENT_SECONDS}`,
    "#EXT-X-MEDIA-SEQUENCE:0",
    `#EXTINF:${WHOLE_ASSET_SEGMENT_SECONDS}.000,`,
    segmentURL,
    "#EXT-X-ENDLIST",
    "",
  ].join("\n");
}

/**
 * If the supplied video URL is itself a multivariant/master playlist, attach the
 * sidecar renditions to each actual variant instead of nesting one master inside
 * another (HLS requires EXT-X-STREAM-INF URIs to identify Media Playlists).
 */
export function attachSidecarSubtitlesToMaster(
  sourcePlaylist: string,
  inputTracks: SidecarSubtitle[],
  origin: string,
  sourceURL: string,
  rewriteURL: (url: string) => string,
): string | null {
  if (!/#EXT-X-STREAM-INF:/m.test(sourcePlaylist)) return null;
  const tags = subtitleRenditionTags(inputTracks, origin);
  if (!tags.length) return null;

  const lines = sourcePlaylist.split(/\r?\n/);
  const rewritten = lines.map((line) => {
    const trimmed = line.trim();
    if (!trimmed) return line;
    if (trimmed.startsWith("#")) {
      let output = line.replace(/URI="([^"]+)"/g, (_match, uri: string) => {
        try { return `URI="${rewriteURL(new URL(uri, sourceURL).toString())}"`; }
        catch { return `URI="${uri}"`; }
      });
      if (trimmed.startsWith("#EXT-X-STREAM-INF:")) {
        const colon = output.indexOf(":");
        const prefix = output.slice(0, colon + 1);
        const attributes = output.slice(colon + 1);
        const subtitleAttribute = `SUBTITLES="${SUBTITLE_GROUP_ID}"`;
        if (/(^|,)\s*SUBTITLES="[^"]*"/.test(attributes)) {
          output = `${prefix}${attributes.replace(/(^|,)\s*SUBTITLES="[^"]*"/, (_match, separator: string) => `${separator}${subtitleAttribute}`)}`;
        } else {
          output = `${output},${subtitleAttribute}`;
        }
      }
      return output;
    }
    try { return rewriteURL(new URL(trimmed, sourceURL).toString()); }
    catch { return line; }
  });

  const output: string[] = [];
  let inserted = false;
  for (const line of rewritten) {
    const trimmed = line.trim();
    if (trimmed.startsWith("#EXT-X-VERSION:")) {
      const version = Number(trimmed.slice(trimmed.indexOf(":") + 1));
      output.push(Number.isFinite(version) && version >= 3 ? line : "#EXT-X-VERSION:3");
      continue;
    }
    if (!inserted && trimmed.startsWith("#EXT-X-STREAM-INF:")) {
      output.push(...tags);
      inserted = true;
    }
    output.push(line);
  }
  return inserted ? output.join("\n") : null;
}

export function buildSubtitledPlaylist(videoRaw: string, inputTracks: SidecarSubtitle[], origin = ""): string | null {
  const video = safeHttpURL(videoRaw);
  if (!video || !(/\.m3u8(?:$|[?#])/i.test(video) || /\/api\/cinema\/stream\//i.test(video))) return null;
  const tracks = normalizedTracks(inputTracks);
  if (!tracks.length) return null;
  const lines = ["#EXTM3U", "#EXT-X-VERSION:4", ...subtitleRenditionTags(tracks, origin)];
  lines.push(`#EXT-X-STREAM-INF:BANDWIDTH=6000000,SUBTITLES="${SUBTITLE_GROUP_ID}"`, video, "");
  return lines.join("\n");
}
