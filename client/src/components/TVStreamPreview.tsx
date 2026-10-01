import Hls from "hls.js";
import { RefreshCw, X } from "lucide-react";
import { useEffect, useRef, useState } from "react";

type TVStreamPreviewProps = {
  name: string;
  streamUrl: string;
  audioUrl?: string | null;
  posterUrl?: string | null;
  onClose: () => void;
};

function attachSource(element: HTMLMediaElement, url: string, hlsRef: { current: Hls | null }) {
  if (Hls.isSupported() && url.includes(".m3u8")) {
    const hls = new Hls({ lowLatencyMode: false, backBufferLength: 30, maxBufferLength: 20 });
    hls.loadSource(url);
    hls.attachMedia(element);
    hlsRef.current = hls;
  } else {
    element.src = url;
  }
}

function liveEdge(element: HTMLMediaElement) {
  const range = element.seekable.length ? element.seekable.end(element.seekable.length - 1) : NaN;
  return Number.isFinite(range) ? Math.max(0, range - 1) : null;
}

export function TVStreamPreview({ name, streamUrl, audioUrl, posterUrl, onClose }: TVStreamPreviewProps) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const audioRef = useRef<HTMLAudioElement>(null);
  const videoHls = useRef<Hls | null>(null);
  const audioHls = useRef<Hls | null>(null);
  const [syncing, setSyncing] = useState(false);
  const [message, setMessage] = useState("Đang tải nguồn phát…");

  useEffect(() => {
    const video = videoRef.current;
    const audio = audioRef.current;
    if (!video || !audio) return;

    attachSource(video, streamUrl, videoHls);
    if (audioUrl) attachSource(audio, audioUrl, audioHls);

    const playAudio = () => { if (audioUrl) { audio.currentTime = video.currentTime; void audio.play().catch(() => undefined); } };
    const pauseAudio = () => { if (audioUrl) audio.pause(); };
    const seekAudio = () => { if (audioUrl && Number.isFinite(video.currentTime)) audio.currentTime = video.currentTime; };
    const updateVolume = () => { if (audioUrl) { audio.volume = video.volume; audio.muted = video.muted; } };
    const onReady = () => setMessage(audioUrl ? "Đang phát video + audio riêng" : "Đang phát video");
    video.addEventListener("play", playAudio);
    video.addEventListener("pause", pauseAudio);
    video.addEventListener("seeking", seekAudio);
    video.addEventListener("volumechange", updateVolume);
    video.addEventListener("playing", onReady);
    return () => {
      video.removeEventListener("play", playAudio);
      video.removeEventListener("pause", pauseAudio);
      video.removeEventListener("seeking", seekAudio);
      video.removeEventListener("volumechange", updateVolume);
      video.removeEventListener("playing", onReady);
      video.pause(); audio.pause();
      videoHls.current?.destroy(); audioHls.current?.destroy();
      videoHls.current = null; audioHls.current = null;
    };
  }, [streamUrl, audioUrl]);

  async function syncToLiveEdge() {
    const video = videoRef.current;
    const audio = audioRef.current;
    if (!video || !audio) return;
    setSyncing(true);
    setMessage("Đang đưa video và audio về live-edge…");
    const wasPlaying = !video.paused;
    video.pause(); audio.pause();
    const videoEdge = liveEdge(video);
    const audioEdge = audioUrl ? liveEdge(audio) : null;
    if (videoEdge !== null) video.currentTime = videoEdge;
    if (audioUrl && audioEdge !== null) audio.currentTime = audioEdge;
    if (wasPlaying) {
      await video.play().catch(() => undefined);
      if (audioUrl) await audio.play().catch(() => undefined);
    }
    setSyncing(false);
    setMessage(wasPlaying ? "Đã đồng bộ và tiếp tục phát" : "Đã đồng bộ; đang tạm dừng tại live-edge");
  }

  return <div className="tv-preview-backdrop" role="dialog" aria-modal="true" aria-label={`Xem thử ${name}`} onMouseDown={e => { if (e.target === e.currentTarget) onClose(); }}>
    <section className="tv-preview-panel">
      <header className="tv-preview-header">
        <div><span className="eyebrow">XEM THỬ TRỰC TIẾP</span><h2>{name}</h2><p>{message}</p></div>
        <button type="button" className="button button-ghost" onClick={onClose} aria-label="Đóng xem thử"><X size={16} /> Đóng</button>
      </header>
      <div className="tv-preview-video-wrap"><video ref={videoRef} controls playsInline poster={posterUrl || undefined} /></div>
      <audio ref={audioRef} preload="auto" />
      <div className="tv-preview-actions">
        <button type="button" className="button button-primary" onClick={() => void syncToLiveEdge()} disabled={syncing}><RefreshCw size={15} className={syncing ? "tv-preview-spin" : ""} /> {syncing ? "Đang đồng bộ…" : "Đồng bộ live"}</button>
        {audioUrl ? <span className="tv-preview-audio-note">Đang dùng audio riêng</span> : <span className="tv-preview-audio-note">Audio tích hợp trong stream</span>}
      </div>
    </section>
  </div>;
}
