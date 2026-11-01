export type SidecarSubtitle = { id: string; language: string; name: string; url: string };
const MAX_TRACKS = 12;
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
export function buildSubtitledPlaylist(videoRaw: string, inputTracks: SidecarSubtitle[]): string | null {
  const video = safeHttpURL(videoRaw);
  if (!video || !(/\.m3u8(?:$|[?#])/i.test(video) || /\/api\/cinema\/stream\//i.test(video))) return null;
  const tracks = inputTracks.flatMap((track, index) => {
    const url = safeHttpURL(track.url);
    if (!url) return [];
    const rawLanguage = track.language.trim().toLowerCase();
    const aliases: Record<string, string> = { vietnamese: "vi", "tiếng việt": "vi", english: "en", japanese: "ja", korean: "ko", chinese: "zh", french: "fr", spanish: "es", thai: "th", indonesian: "id" };
    const language = aliases[rawLanguage] ?? (/^[a-zA-Z]{2,3}(?:-[a-zA-Z0-9]{2,8})*$/.test(track.language.trim()) ? track.language.trim().toLowerCase() : "und");
    const id = safeText(track.id, `track-${index + 1}`, 64);
    const label = safeText(track.name, language === "und" ? `Phụ đề ${index + 1}` : language, 60);
    // HLS has no separate rendition ID; append the stable source ID to NAME
    // so AVFoundation can distinguish same-language tracks deterministically.
    const name = `${label} [${id}]`;
    return [{ id, language, name, url }];
  }).slice(0, MAX_TRACKS);
  if (!tracks.length) return null;
  const lines = ["#EXTM3U", "#EXT-X-VERSION:4"];
  tracks.forEach((track, index) => {
    lines.push(`#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="${track.name}",DEFAULT=${index === 0 ? "YES" : "NO"},AUTOSELECT=${index === 0 ? "YES" : "NO"},FORCED=NO,LANGUAGE="${track.language}",URI="${track.url}"`);
  });
  lines.push('#EXT-X-STREAM-INF:BANDWIDTH=6000000,SUBTITLES="subs"', video, "");
  return lines.join("\n");
}
