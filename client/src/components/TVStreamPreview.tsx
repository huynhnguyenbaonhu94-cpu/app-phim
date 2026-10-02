import Hls from "hls.js";
import { AlertTriangle, Play, RefreshCw, X } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";

type TVStreamPreviewProps = {
  name: string;
  streamUrl: string;
  audioUrl?: string | null;
  posterUrl?: string | null;
  onClose: () => void;
};

type HlsSlot = { current: Hls | null };

function isHlsUrl(url: string) {
  return /\.m3u8(?:$|[?#])/i.test(url);
}

function proxiedTvUrl(url: string) {
  try {
    const parsed = new URL(url, window.location.origin);
    if (parsed.protocol === "https:" && (parsed.hostname === "d4.dhcn.vn" || parsed.hostname === "media.dhcn.vn")) {
      return `/api/tv/proxy?url=${encodeURIComponent(parsed.toString())}`;
    }
  } catch { /* Keep the original URL for non-DHCN sources. */ }
  return url;
}

function seekableLiveEdge(element: HTMLMediaElement) {
  if (!element.seekable.length) return null;
  const end = element.seekable.end(element.seekable.length - 1);
  return Number.isFinite(end) ? Math.max(0, end - 1) : null;
}

function destroyHls(slot: HlsSlot) {
  slot.current?.destroy();
  slot.current = null;
}

export function TVStreamPreview({ name, streamUrl, audioUrl, posterUrl, onClose }: TVStreamPreviewProps) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const audioRef = useRef<HTMLAudioElement>(null);
  const videoHls = useRef<Hls | null>(null);
  const audioHls = useRef<Hls | null>(null);
  const reconnectTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const syncTimer = useRef<ReturnType<typeof setInterval> | null>(null);
  const lastAudioSeekAt = useRef(0);
  const audioSeekInProgress = useRef(false);
  const [syncing, setSyncing] = useState(false);
  const [playing, setPlaying] = useState(false);
  const [ready, setReady] = useState(false);
  const [message, setMessage] = useState("Đang tải nguồn phát…");
  const [error, setError] = useState<string | null>(null);
  const [retryNonce, setRetryNonce] = useState(0);

  const startPlayback = useCallback(async () => {
    const video = videoRef.current;
    const audio = audioRef.current;
    if (!video || !audio) return false;
    setError(null);
    // A video-only HLS must be muted when a separate audio track is used.
    // This also allows the video element to start reliably in browser policies.
    video.muted = Boolean(audioUrl);
    try {
      await video.play();
      if (audioUrl) await audio.play();
      setPlaying(true);
      setMessage(audioUrl ? "Đang phát video + audio riêng" : "Đang phát video");
      return true;
    } catch {
      setPlaying(false);
      setMessage("Nguồn đã sẵn sàng — bấm Phát để bắt đầu video và audio");
      return false;
    }
  }, [audioUrl]);

  const attach = useCallback((element: HTMLMediaElement, url: string, slot: HlsSlot, label: "video" | "audio") => {
    destroyHls(slot);
    element.removeAttribute("src");
    element.load();
    if (isHlsUrl(url) && Hls.isSupported()) {
      const hls = new Hls({
        enableWorker: false,
        lowLatencyMode: false,
        startPosition: -1,
        backBufferLength: 30,
        maxBufferLength: 30,
        maxMaxBufferLength: 90,
        capLevelToPlayerSize: true,
        startFragPrefetch: true,
        manifestLoadingTimeOut: 15_000,
        levelLoadingTimeOut: 15_000,
        fragLoadingTimeOut: 20_000,
      });
      slot.current = hls;
      hls.on(Hls.Events.ERROR, (_event, data) => {
        if (!data.fatal) return;
        if (data.type === Hls.ErrorTypes.NETWORK_ERROR) {
          setMessage(`${label === "video" ? "Video" : "Audio"} mất mạng — đang kết nối lại…`);
          hls.startLoad(-1);
        } else if (data.type === Hls.ErrorTypes.MEDIA_ERROR) {
          setMessage(`${label === "video" ? "Video" : "Audio"} gặp lỗi giải mã — đang khôi phục…`);
          hls.recoverMediaError();
        } else {
          setError(`${label === "video" ? "Video" : "Audio"} không phát được nguồn HLS.`);
        }
      });
      hls.on(Hls.Events.MANIFEST_PARSED, () => {
        if (label === "video") setReady(true);
        if (label === "audio") setMessage("Đã tải audio riêng; đang chờ video");
        void startPlayback();
      });
      hls.loadSource(url);
      hls.attachMedia(element);
      return;
    }

    // Safari/iOS can play HLS natively. Keep this path for native HLS and mp4/mp3 URLs.
    element.src = url;
    element.load();
    const onReady = () => {
      if (label === "video") setReady(true);
      void startPlayback();
    };
    element.addEventListener("canplay", onReady, { once: true });
  }, [startPlayback]);

  useEffect(() => {
    const video = videoRef.current;
    const audio = audioRef.current;
    if (!video || !audio) return;
    let disposed = false;
    setReady(false);
    setPlaying(false);
    setError(null);
    setMessage("Đang tải nguồn phát…");
    video.muted = Boolean(audioUrl);
    video.volume = audioUrl ? 0 : 1;
    audio.volume = 1;
    audio.muted = false;
    video.playsInline = true;

    const onVideoPlaying = () => { if (!disposed) { setReady(true); setPlaying(true); } };
    const onVideoPause = () => { if (!disposed && !video.ended) { audio.pause(); setPlaying(false); } };
    const onVideoWaiting = () => { if (!disposed) setMessage("Video đang buffer…"); };
    const onVideoError = () => { if (!disposed) setError("Video không phát được. Hãy kiểm tra URL, codec hoặc quyền CORS."); };
    const onVolume = () => { if (audioUrl) { audio.volume = video.volume || 1; audio.muted = video.muted; } };
    video.addEventListener("playing", onVideoPlaying);
    video.addEventListener("pause", onVideoPause);
    video.addEventListener("waiting", onVideoWaiting);
    video.addEventListener("error", onVideoError);
    video.addEventListener("volumechange", onVolume);

    attach(video, proxiedTvUrl(streamUrl), videoHls, "video");
    if (audioUrl) attach(audio, proxiedTvUrl(audioUrl), audioHls, "audio");

    syncTimer.current = setInterval(() => {
      if (!audioUrl || video.paused || audio.paused || audio.readyState < 2) return;
      const videoEdge = seekableLiveEdge(video);
      const audioEdge = seekableLiveEdge(audio);
      if (videoEdge === null || audioEdge === null) return;
      const videoLag = videoEdge - video.currentTime;
      const audioLag = audioEdge - audio.currentTime;
      const difference = audioLag - videoLag;
      // Independent live playlists have slightly different segment clocks.
      // Do not seek every tick: repeated seeks make AAC replay a fragment and
      // sound like looping/crackling. Only correct a large drift with a cooldown.
      const now = Date.now();
      if (Math.abs(difference) > 2.5 && now - lastAudioSeekAt.current > 5_000 && !audioSeekInProgress.current) {
        audioSeekInProgress.current = true;
        lastAudioSeekAt.current = now;
        audio.currentTime = Math.max(0, audioEdge - Math.max(0, videoLag));
        window.setTimeout(() => { audioSeekInProgress.current = false; }, 900);
      }
      if (videoLag > 12 || audioLag > 12) {
        video.currentTime = videoEdge;
        if (now - lastAudioSeekAt.current > 1_000) {
          audio.currentTime = audioEdge;
          lastAudioSeekAt.current = now;
        }
      }
    }, 1000);

    return () => {
      disposed = true;
      video.removeEventListener("playing", onVideoPlaying);
      video.removeEventListener("pause", onVideoPause);
      video.removeEventListener("waiting", onVideoWaiting);
      video.removeEventListener("error", onVideoError);
      video.removeEventListener("volumechange", onVolume);
      if (syncTimer.current) clearInterval(syncTimer.current);
      if (reconnectTimer.current) clearTimeout(reconnectTimer.current);
      video.pause(); audio.pause();
      destroyHls(videoHls); destroyHls(audioHls);
      video.removeAttribute("src"); audio.removeAttribute("src");
      video.load(); audio.load();
    };
  }, [audioUrl, attach, streamUrl, retryNonce]);

  function retrySources() {
    setError(null);
    setReady(false);
    setMessage("Đang kết nối lại video và audio…");
    setRetryNonce(value => value + 1);
  }

  async function syncToLiveEdge() {
    const video = videoRef.current;
    const audio = audioRef.current;
    if (!video || !audio) return;
    setSyncing(true);
    setError(null);
    setMessage("Đang đưa video và audio về live-edge…");
    const wasPlaying = !video.paused;
    video.pause(); audio.pause();
    const videoEdge = seekableLiveEdge(video);
    const audioEdge = audioUrl ? seekableLiveEdge(audio) : null;
    if (videoEdge !== null) video.currentTime = videoEdge;
    if (audioUrl && audioEdge !== null) audio.currentTime = audioEdge;
    if (wasPlaying) await startPlayback();
    else setPlaying(false);
    setSyncing(false);
    setMessage(wasPlaying ? "Đã đồng bộ và tiếp tục phát" : "Đã đồng bộ; bấm Phát để xem");
  }

  return <div className="tv-preview-backdrop" role="dialog" aria-modal="true" aria-label={`Xem thử ${name}`} onMouseDown={e => { if (e.target === e.currentTarget) onClose(); }}>
    <section className="tv-preview-panel">
      <header className="tv-preview-header">
        <div><span className="eyebrow">XEM THỬ TRỰC TIẾP</span><h2>{name}</h2><p>{message}</p></div>
        <button type="button" className="button button-ghost" onClick={onClose} aria-label="Đóng xem thử"><X size={16} /> Đóng</button>
      </header>
      <div className={`tv-preview-video-wrap ${error ? "has-error" : ""}`}>
        <video ref={videoRef} controls playsInline poster={posterUrl || undefined} />
        {!playing && ready && <button type="button" className="tv-preview-play-overlay" onClick={() => void startPlayback()}><Play size={22} fill="currentColor" /> Phát stream</button>}
        {error && <div className="tv-preview-error"><AlertTriangle size={18} /><span>{error}</span><button type="button" className="button button-ghost" onClick={retrySources}>Kết nối lại</button></div>}
      </div>
      <audio ref={audioRef} preload="auto" />
      <div className="tv-preview-actions">
        <button type="button" className="button button-primary" onClick={() => void syncToLiveEdge()} disabled={syncing || !ready}><RefreshCw size={15} className={syncing ? "tv-preview-spin" : ""} /> {syncing ? "Đang đồng bộ…" : "Đồng bộ live"}</button>
        {audioUrl ? <span className="tv-preview-audio-note">Đang dùng audio riêng, video đã tắt audio tích hợp</span> : <span className="tv-preview-audio-note">Audio tích hợp trong stream</span>}
      </div>
    </section>
  </div>;
}
