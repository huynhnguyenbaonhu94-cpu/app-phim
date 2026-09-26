/**
 * CinemaPlayer — Cinemora custom video player with HLS.js support
 *
 * Mobile (touch):
 *   - Tap screen (outside controls / center-button) → toggle controls visibility ONLY, never pause
 *   - Tap centre Play button → play
 *   - Tap Pause button (centre or toolbar) → pause
 *
 * Desktop (mouse):
 *   - Move mouse → show controls, auto-hide after 3 s of idle
 *   - Click screen (outside controls) → toggle play/pause
 */

import Hls from "hls.js";
import {
  Check,
  ChevronUp,
  FastForward,
  Film,
  Maximize,
  Minimize,
  Pause,
  Play,
  RefreshCw,
  Rewind,
  SkipForward,
  Sun,
  Volume2,
  VolumeX,
  X,
} from "lucide-react";
import { CINEMORA_LOGO_URL } from "@/const";
import {
  useCallback,
  useEffect,
  useRef,
  useState,
} from "react";
import { createPortal } from "react-dom";

/* ─── types ─────────────────────────────────────────────── */
interface CinemaPlayerProps {
  streamUrl?: string;
  fallbackEmbedUrl?: string;
  title?: string;
  posterUrl?: string;
  nextEpisodeLabel?: string;
  onEnded?: () => void;
  onNextEpisode?: () => void;
  autoNextEnabled?: boolean;
  onAutoNextToggle?: (enabled: boolean) => void;
  /** Seek to this position (seconds) when the player mounts / src changes */
  startAt?: number;
  /** Called periodically with (currentTime, duration) so parent can save progress */
  onProgress?: (currentTime: number, duration: number) => void;
  onAdStateChange?: (active: boolean) => void;
}

/* ─── helpers ────────────────────────────────────────────── */
function fmt(s: number): string {
  if (!isFinite(s) || s < 0) return "0:00";
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = Math.floor(s % 60);
  return h > 0
    ? `${h}:${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}`
    : `${m}:${String(sec).padStart(2, "0")}`;
}

const SPEEDS = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];
const HIDE_DELAY = 3000;
const AD_VIDEO_URL = "/assets/quang-cao.mp4";
const AD_INTERVAL_MIN_SECONDS = 150;
const AD_INTERVAL_MAX_SECONDS = 360;

function randomAdInterval() {
  return AD_INTERVAL_MIN_SECONDS + Math.floor(Math.random() * (AD_INTERVAL_MAX_SECONDS - AD_INTERVAL_MIN_SECONDS + 1));
}

function isIOSDevice() {
  return /iPhone|iPad|iPod/i.test(navigator.userAgent) ||
    (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
}

/* ─── SpeedSheet: portal vào #cinema-portal (ngoài #root, tránh stacking context) ── */
function SpeedSheet({
  current,
  onSelect,
  onClose,
}: {
  current: number;
  onSelect: (s: number) => void;
  onClose: () => void;
}) {
  // Portal target: dùng #cinema-portal thay vì document.body để tránh React lifecycle conflict
  const portalEl =
    (typeof document !== "undefined" && document.getElementById("cinema-portal")) ||
    (typeof document !== "undefined" ? document.body : null);

  if (!portalEl) return null;

  const sheet = (
    <div
      className="cp-sheet-backdrop"
      onClick={(e) => { e.stopPropagation(); onClose(); }}
      onTouchEnd={(e) => { e.stopPropagation(); e.preventDefault(); onClose(); }}
    >
      <div
        className="cp-sheet"
        onClick={(e) => e.stopPropagation()}
        onTouchEnd={(e) => e.stopPropagation()}
      >
        <div className="cp-sheet-handle" />
        <div className="cp-sheet-header">
          <span className="cp-sheet-title">Tốc độ phát</span>
          <button
            className="cp-sheet-close"
            onClick={(e) => { e.stopPropagation(); onClose(); }}
            onTouchEnd={(e) => { e.stopPropagation(); e.preventDefault(); onClose(); }}
          >
            <X size={14} />
          </button>
        </div>
        <div className="cp-sheet-options">
          {SPEEDS.map((s) => (
            <button
              key={s}
              className={`cp-sheet-option${s === current ? " is-active" : ""}`}
              onClick={(e) => { e.stopPropagation(); onSelect(s); onClose(); }}
              onTouchEnd={(e) => { e.stopPropagation(); e.preventDefault(); onSelect(s); onClose(); }}
            >
              <span className="cp-sheet-opt-label">{s === 1 ? "Bình thường" : `${s}×`}</span>
              {s === current && <span className="cp-sheet-check">✓</span>}
            </button>
          ))}
        </div>
        <div className="cp-sheet-footer">Tốc độ hiện tại: {current}×</div>
      </div>
    </div>
  );

  return createPortal(sheet, portalEl);
}

/* ─── SpeedDropdown (desktop) ────────────────────────────── */
function SpeedDropdown({
  current,
  onSelect,
  onClose,
}: {
  current: number;
  onSelect: (s: number) => void;
  onClose: () => void;
}) {
  return (
    <div className="cinema-speed-dropdown">
      {SPEEDS.map((s) => (
        <button
          key={s}
          className={`cinema-speed-opt${s === current ? " is-selected" : ""}`}
          onClick={(e) => { e.stopPropagation(); onSelect(s); onClose(); }}
        >
          <span>{s === 1 ? "Bình thường (1×)" : `${s}×`}</span>
          {s === current && <Check size={13} className="cinema-speed-check" />}
        </button>
      ))}
    </div>
  );
}

/* ─── toggleFullscreen: mobile-safe ─────────────────────── */
function requestFullscreenCompat(el: HTMLElement): Promise<void> {
  if (el.requestFullscreen) return el.requestFullscreen();
  // Safari / older iOS
  const elAny = el as any;
  if (elAny.webkitRequestFullscreen) return elAny.webkitRequestFullscreen();
  if (elAny.webkitEnterFullscreen) { elAny.webkitEnterFullscreen(); return Promise.resolve(); }
  return Promise.reject(new Error("Fullscreen not supported"));
}

function exitFullscreenCompat(): Promise<void> {
  if (document.exitFullscreen) return document.exitFullscreen();
  const docAny = document as any;
  if (docAny.webkitExitFullscreen) return docAny.webkitExitFullscreen();
  return Promise.reject(new Error("Exit fullscreen not supported"));
}

function getFullscreenElement(): Element | null {
  return (
    document.fullscreenElement ||
    (document as any).webkitFullscreenElement ||
    null
  );
}

/* ─── Main component ─────────────────────────────────────── */
export function CinemaPlayer({
  streamUrl,
  fallbackEmbedUrl,
  title,
  posterUrl,
  nextEpisodeLabel,
  autoNextEnabled = true,
  onAutoNextToggle,
  onEnded,
  onNextEpisode,
  startAt,
  onProgress,
  onAdStateChange,
}: CinemaPlayerProps) {
  /* ── state ── */
  const [playing, setPlaying]           = useState(false);
  const [currentTime, setCurrentTime]   = useState(0);
  const [duration, setDuration]         = useState(0);
  const [volume, setVolume]             = useState(1);
  const [muted, setMuted]               = useState(false);
  const [volumeOpen, setVolumeOpen]     = useState(false);
  const [speed, setSpeed]               = useState(1);
  const [brightness, setBrightness]     = useState(1);
  const [fullscreen, setFullscreen]     = useState(false);
  const [controlsVisible, setControlsVisible] = useState(true);
  const [buffering, setBuffering]       = useState(true);
  const [sourceReady, setSourceReady]     = useState(false);
  const [error, setError]               = useState<string | null>(null);
  const [adActive, setAdActive]         = useState(false);
  const [adPlaying, setAdPlaying]       = useState(false);
  const [adCurrentTime, setAdCurrentTime] = useState(0);
  const [adDuration, setAdDuration]     = useState(0);
  const [adError, setAdError]           = useState(false);
  const [nativeFullscreenAd, setNativeFullscreenAd] = useState(false);
  const [speedOpen, setSpeedOpen]       = useState(false);
  const [isMobile, setIsMobile]         = useState(false);
  const [autoNextCountdown, setAutoNextCountdown] = useState<number | null>(null);

  /* ── refs ── */
  const videoRef    = useRef<HTMLVideoElement>(null);
  const adVideoRef  = useRef<HTMLVideoElement>(null);
  const hlsRef      = useRef<Hls | null>(null);
  const streamUrlRef = useRef<string | undefined>(streamUrl);
  const wrapRef     = useRef<HTMLDivElement>(null);
  const hideTimer   = useRef<ReturnType<typeof setTimeout> | null>(null);
  const touchStart  = useRef<{ x: number; y: number } | null>(null);
  const pointerStart = useRef<{ x: number; y: number } | null>(null);
  const lastPointerTouchAt = useRef(0);
  const startAtRef  = useRef<number | undefined>(startAt);
  const onProgressRef = useRef(onProgress);
  // true khi user chủ động pause — ngăn auto-play khi load src mới hoặc resume tab
  const userPausedRef = useRef(false);
  const progressTimer = useRef<ReturnType<typeof setInterval> | null>(null);
  const countdownRef  = useRef<ReturnType<typeof setInterval> | null>(null);
  const adActiveRef = useRef(false);
  const nativeFullscreenRef = useRef(false);
  const nativeFullscreenAdRef = useRef(false);
  const nativeAdStartedRef = useRef(false);
  const restoringNativeMovieRef = useRef(false);
  const adLastAllowedTimeRef = useRef(0);
  const adResumeTimeRef = useRef(0);
  const resumeAfterAdRef = useRef(true);
  const nextAdAtRef = useRef(0);
  const initialPlayAttemptedRef = useRef(false);
  const fullscreenBusyRef = useRef(false);
  const seekingRef = useRef(false);
  const resumeAfterSeekRef = useRef(false);

  useEffect(() => { onProgressRef.current = onProgress; }, [onProgress]);
  useEffect(() => { onAdStateChange?.(adActive); }, [adActive, onAdStateChange]);

  /* ── detect touch/mobile ── */
  useEffect(() => {
    const mq = window.matchMedia("(hover: none), (pointer: coarse)");
    setIsMobile(mq.matches);
    const handler = (e: MediaQueryListEvent) => setIsMobile(e.matches);
    mq.addEventListener("change", handler);
    return () => mq.removeEventListener("change", handler);
  }, []);

  /* Keep the visible watermark resilient to casual DOM removal. This is a
     deterrent only; a determined user who controls the browser can still
     disable client-side JavaScript or CSS. */
  useEffect(() => {
    const player = wrapRef.current;
    const brand = player?.querySelector<HTMLElement>(".cinema-player-brand");
    const logo = brand?.querySelector<HTMLImageElement>("img");
    if (!brand || !logo) return;
    logo.draggable = false;
    const observer = new MutationObserver(() => {
      if (brand.isConnected && !brand.contains(logo)) brand.appendChild(logo);
    });
    observer.observe(brand, { childList: true });
    return () => observer.disconnect();
  }, [streamUrl]);

  /* ── auto-hide controls ── */
  const resetHideTimer = useCallback(() => {
    if (hideTimer.current) clearTimeout(hideTimer.current);
    setControlsVisible(true);
    hideTimer.current = setTimeout(() => setControlsVisible(false), HIDE_DELAY);
  }, []);

  useEffect(() => () => { if (hideTimer.current) clearTimeout(hideTimer.current); }, []);

  /* show controls when paused */
  useEffect(() => {
    // Loading is not the same as paused. Keep every player action hidden until
    // the source has either started playing or autoplay has explicitly failed.
    if (!sourceReady || buffering || error) {
      if (hideTimer.current) clearTimeout(hideTimer.current);
      setControlsVisible(false);
      return;
    }
    if (!playing) {
      if (hideTimer.current) clearTimeout(hideTimer.current);
      setControlsVisible(true);
      return;
    }

    // Playback can resume automatically after an ad without any mouse event.
    // Re-arm the idle timer here so controls do not remain stuck on screen.
    resetHideTimer();
  }, [playing, buffering, sourceReady, error, resetHideTimer]);

  /* keep streamUrlRef current for retry callback */
  useEffect(() => { streamUrlRef.current = streamUrl; }, [streamUrl]);

  /* ── onProgress pulse every 5s while playing ── */
  useEffect(() => {
    if (!playing) {
      if (progressTimer.current) { clearInterval(progressTimer.current); progressTimer.current = null; }
      return;
    }
    progressTimer.current = setInterval(() => {
      const v = videoRef.current;
      if (!v) return;
      onProgressRef.current?.(v.currentTime, v.duration || 0);
    }, 5000);
    return () => { if (progressTimer.current) { clearInterval(progressTimer.current); progressTimer.current = null; } };
  }, [playing]);

  /* ── HLS setup ── */
  useEffect(() => {
    const v = videoRef.current;
    if (!v || !streamUrl) return;

    /* reset state on src change */
    setPlaying(false);
    setCurrentTime(0);
    setDuration(0);
    setBuffering(true);
    setSourceReady(false);
    setError(null);
    setAdActive(false);
    setAdPlaying(false);
    setAdCurrentTime(0);
    setAdDuration(0);
    setAdError(false);
    adActiveRef.current = false;
    nativeFullscreenRef.current = false;
    nativeFullscreenAdRef.current = false;
    nativeAdStartedRef.current = false;
    restoringNativeMovieRef.current = false;
    setNativeFullscreenAd(false);
    // Do not expose stale controls while a newly selected episode is loading.
    setControlsVisible(false);
    if (hideTimer.current) clearTimeout(hideTimer.current);
    // Khi đổi tập mới, reset trạng thái pause để tự play
    userPausedRef.current = false;
    initialPlayAttemptedRef.current = false;

    // Store startAt for this load
    startAtRef.current = startAt;
    nextAdAtRef.current = Math.max(0, startAt || 0) + randomAdInterval();

    function destroyHls() {
      if (hlsRef.current) {
        hlsRef.current.destroy();
        hlsRef.current = null;
      }
    }

    let fatalRetries = 0;

    if (Hls.isSupported()) {
      destroyHls();
      const hls = new Hls({
        enableWorker: true,
        lowLatencyMode: false,
        backBufferLength: 60,
        maxBufferLength: 30,
        maxMaxBufferLength: 120,
        fragLoadingTimeOut: 20000,
        manifestLoadingTimeOut: 15000,
        levelLoadingTimeOut: 15000,
      });
      hlsRef.current = hls;

      hls.on(Hls.Events.ERROR, (_evt, data) => {
        if (!data.fatal) return;
        if (data.type === Hls.ErrorTypes.NETWORK_ERROR && fatalRetries < 3) {
          fatalRetries++;
          setTimeout(() => hls.startLoad(), 1000 * fatalRetries);
        } else if (data.type === Hls.ErrorTypes.MEDIA_ERROR && fatalRetries < 2) {
          fatalRetries++;
          hls.recoverMediaError();
        } else {
          setError("Nguồn phim lỗi hoặc không khả dụng.");
          setBuffering(false);
        }
      });

      hls.attachMedia(v);
      hls.on(Hls.Events.MANIFEST_PARSED, () => {
        // Manifest parsing only proves that metadata is available. Waiting for
        // canplay prevents a false "playing" state and a frozen black frame.
      });
      hls.loadSource(streamUrl);

    } else if (
      v.canPlayType("application/vnd.apple.mpegurl") ||
      v.canPlayType("video/mp4")
    ) {
      /* Safari / native fallback */
      destroyHls();
      v.src = streamUrl;
      v.load();
      // Playback is started by the shared canplay handler below.
    } else {
      setError("Trình duyệt không hỗ trợ phát HLS. Hãy dùng Chrome hoặc Firefox.");
      setBuffering(false);
    }

    return destroyHls;
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [streamUrl]);

  /* ── video event listeners ── */
  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;

    const onPlay       = () => {
      if (nativeFullscreenAdRef.current && adActiveRef.current) {
        nativeAdStartedRef.current = true;
        resumeAfterAdRef.current = true;
        setAdPlaying(true);
        setAdError(false);
        return;
      }
      // The `play` event fires before the first decoded frame. Do not mark
      // the UI as playing here; wait for the real `playing` event below.
      if (!adActiveRef.current) setError(null);
    };
    const onPlaying = () => {
      if (nativeFullscreenAdRef.current || adActiveRef.current) return;
      setPlaying(true);
      setSourceReady(true);
      setBuffering(false);
      setControlsVisible(true);
    };
    const onPause      = () => {
      if (restoringNativeMovieRef.current) return;
      if (nativeFullscreenAdRef.current && adActiveRef.current && nativeAdStartedRef.current) resumeAfterAdRef.current = false;
      if (adActiveRef.current) return;
      setPlaying(false);
      // Save progress on pause
      onProgressRef.current?.(v.currentTime, v.duration || 0);
    };
    const onWaiting    = () => {
      if (nativeFullscreenRef.current) setAdPlaying(false);
      else {
        // HLS emits `waiting` during a normal seek. Keep the intended play
        // state instead of forcing a pause that requires pause/play to recover.
        if (v.paused && !seekingRef.current) setPlaying(false);
        setBuffering(true);
      }
    };
    const onCanPlay    = () => {
      if (!nativeFullscreenAdRef.current) {
        const seekTo = startAtRef.current;
        if (seekTo && seekTo > 5 && Math.abs(v.currentTime - seekTo) > 2) {
          v.currentTime = seekTo;
        }
        if (!initialPlayAttemptedRef.current && !userPausedRef.current && !document.hidden) {
          initialPlayAttemptedRef.current = true;
          v.play().catch(() => {
            // Autoplay can be blocked by the browser. In that case stop the
            // spinner and expose a real Play button instead of pretending it
            // is already running.
            setBuffering(false);
            setSourceReady(true);
            setControlsVisible(true);
            setPlaying(false);
          });
        }
      }
    };
    const onMovieSeeking = () => {
      if (adActiveRef.current || nativeFullscreenAdRef.current) return;
      seekingRef.current = true;
      resumeAfterSeekRef.current = !v.paused && !userPausedRef.current;
      setBuffering(false);
    };
    const onMovieSeeked = () => {
      if (adActiveRef.current || nativeFullscreenAdRef.current) return;
      const shouldResume = resumeAfterSeekRef.current && !userPausedRef.current;
      seekingRef.current = false;
      resumeAfterSeekRef.current = false;
      setBuffering(false);
      if (shouldResume && v.paused) v.play().catch(() => setPlaying(false));
    };
    const onTimeUpdate = () => {
      if (restoringNativeMovieRef.current) return;
      if (nativeFullscreenAdRef.current && adActiveRef.current) {
        adLastAllowedTimeRef.current = v.currentTime;
        setAdCurrentTime(v.currentTime);
        setAdPlaying(!v.paused);
        return;
      }
      setCurrentTime(v.currentTime);
      if (!isIOSDevice() && !adActiveRef.current && !v.paused && v.currentTime >= nextAdAtRef.current) {
        const webkitFullscreen = (v as HTMLVideoElement & { webkitDisplayingFullscreen?: boolean }).webkitDisplayingFullscreen;
        const inNativeFullscreen = webkitFullscreen === undefined ? nativeFullscreenRef.current : webkitFullscreen;
        adResumeTimeRef.current = v.currentTime;
        adActiveRef.current = true;
        nativeFullscreenAdRef.current = inNativeFullscreen;
        nativeAdStartedRef.current = false;
        setNativeFullscreenAd(inNativeFullscreen);
        userPausedRef.current = false;
        setPlaying(false);
        setAdCurrentTime(0);
        adLastAllowedTimeRef.current = 0;
        setAdDuration(0);
        setAdError(false);
        setAdPlaying(false);
        setSpeedOpen(false);
        resumeAfterAdRef.current = true;
        setAdActive(true);
        v.pause();
        onProgressRef.current?.(v.currentTime, v.duration || 0);
        if (inNativeFullscreen) {
          hlsRef.current?.destroy();
          hlsRef.current = null;
          nativeAdStartedRef.current = false;
          v.controls = true;
          v.src = AD_VIDEO_URL;
          v.load();
          v.play().then(() => setAdPlaying(true)).catch(() => setAdPlaying(false));
        }
      }
    };
    const onDuration   = () => {
      if (nativeFullscreenAdRef.current) setAdDuration(v.duration || 0);
      else setDuration(v.duration);
    };
    const onError      = () => {
      if (nativeFullscreenAdRef.current && adActiveRef.current) {
        setAdPlaying(false);
        setAdError(true);
        (v as HTMLVideoElement & { webkitExitFullscreen?: () => void }).webkitExitFullscreen?.();
        return;
      }
      setError("Nguồn phim lỗi hoặc không khả dụng.");
      setBuffering(false);
      setSourceReady(false);
    };
    const onEnded2     = () => {
      if (nativeFullscreenAdRef.current && adActiveRef.current) { finishAd(); return; }
      if (adActiveRef.current) return;
      setPlaying(false);
      onProgressRef.current?.(v.duration || 0, v.duration || 0);
      onEnded?.();
    };
    const onSeeking    = () => {
      if (!nativeFullscreenAdRef.current || !adActiveRef.current) return;
      if (v.currentTime > adLastAllowedTimeRef.current + 0.75) v.currentTime = adLastAllowedTimeRef.current;
    };
    const onBeginFullscreen = () => { nativeFullscreenRef.current = true; setFullscreen(true); };
    const onEndFullscreen = () => {
      nativeFullscreenRef.current = false;
      setFullscreen(false);
      if (nativeFullscreenAdRef.current && adActiveRef.current && !restoringNativeMovieRef.current) {
        restoreNativeMovie(adResumeTimeRef.current, false);
      }
    };

    v.addEventListener("play",           onPlay);
    v.addEventListener("playing",        onPlaying);
    v.addEventListener("pause",          onPause);
    v.addEventListener("waiting",        onWaiting);
    v.addEventListener("canplay",        onCanPlay);
    v.addEventListener("seeking",        onMovieSeeking);
    v.addEventListener("seeked",         onMovieSeeked);
    v.addEventListener("timeupdate",     onTimeUpdate);
    v.addEventListener("durationchange", onDuration);
    v.addEventListener("error",          onError);
    v.addEventListener("ended",          onEnded2);
    v.addEventListener("seeking",        onSeeking);
    v.addEventListener("webkitbeginfullscreen", onBeginFullscreen);
    v.addEventListener("webkitendfullscreen", onEndFullscreen);

    return () => {
      v.removeEventListener("play",           onPlay);
      v.removeEventListener("playing",        onPlaying);
      v.removeEventListener("pause",          onPause);
      v.removeEventListener("waiting",        onWaiting);
      v.removeEventListener("canplay",        onCanPlay);
      v.removeEventListener("seeking",        onMovieSeeking);
      v.removeEventListener("seeked",         onMovieSeeked);
      v.removeEventListener("timeupdate",     onTimeUpdate);
      v.removeEventListener("durationchange", onDuration);
      v.removeEventListener("error",          onError);
      v.removeEventListener("ended",          onEnded2);
      v.removeEventListener("seeking",        onSeeking);
      v.removeEventListener("webkitbeginfullscreen", onBeginFullscreen);
      v.removeEventListener("webkitendfullscreen", onEndFullscreen);
    };
  }, [onEnded]);

  /* Inline playback uses a separate ad layer. iPhone native fullscreen instead
     replaces the active video's source, because Safari only renders that node. */
  useEffect(() => {
    if (!adActive) return;
    if (nativeFullscreenAd) return;
    const ad = adVideoRef.current;
    if (!ad) return;
    ad.currentTime = 0;
    ad.playbackRate = 1;
    ad.play().then(() => setAdPlaying(true)).catch(() => setAdPlaying(false));
  }, [adActive, nativeFullscreenAd]);

  function finishAd() {
    const v = videoRef.current;
    if (!adActiveRef.current || !v) return;
    const resumeAt = adResumeTimeRef.current;
    const resumeMovie = resumeAfterAdRef.current && !userPausedRef.current && !document.hidden;
    adActiveRef.current = false;
    setAdActive(false);
    setAdPlaying(false);
    setAdError(false);
    nextAdAtRef.current = resumeAt + randomAdInterval();
    if (nativeFullscreenAdRef.current) {
      restoreNativeMovie(resumeAt, resumeMovie);
      return;
    }
    v.currentTime = resumeAt;
    setCurrentTime(resumeAt);
    if (resumeMovie) {
      v.play().catch(() => setPlaying(false));
    } else {
      setPlaying(false);
      onProgressRef.current?.(resumeAt, v.duration || 0);
    }
  }

  function restoreNativeMovie(resumeAt: number, resumeMovie: boolean) {
    const v = videoRef.current;
    const src = streamUrlRef.current;
    if (!v || !src) return;
    nativeFullscreenAdRef.current = false;
    nativeAdStartedRef.current = false;
    setNativeFullscreenAd(false);
    restoringNativeMovieRef.current = true;
    v.pause();
    v.controls = false;
    v.src = src;
    const onMovieMetadata = () => {
      v.removeEventListener("loadedmetadata", onMovieMetadata);
      v.currentTime = resumeAt;
      setCurrentTime(resumeAt);
      setDuration(v.duration || 0);
      restoringNativeMovieRef.current = false;
      if (resumeMovie && !document.hidden) {
        v.play().catch(() => setPlaying(false));
      } else {
        setPlaying(false);
        onProgressRef.current?.(resumeAt, v.duration || 0);
      }
    };
    v.addEventListener("loadedmetadata", onMovieMetadata);
    v.load();
  }

  function toggleAdPlayback() {
    const ad = nativeFullscreenAdRef.current ? videoRef.current : adVideoRef.current;
    if (!ad || !adActiveRef.current) return;
    if (ad.paused) {
      resumeAfterAdRef.current = true;
      ad.play().then(() => setAdPlaying(true)).catch(() => setAdPlaying(false));
    } else {
      resumeAfterAdRef.current = false;
      ad.pause();
    }
  }

  function retryAd() {
    if (nativeFullscreenAdRef.current) {
      const v = videoRef.current;
      if (!v) return;
      setAdError(false);
      v.currentTime = 0;
      v.load();
      v.play().then(() => setAdPlaying(true)).catch(() => setAdPlaying(false));
      return;
    }
    const ad = adVideoRef.current;
    if (!ad) return;
    setAdError(false);
    ad.currentTime = 0;
    ad.load();
    ad.play().then(() => setAdPlaying(true)).catch(() => setAdPlaying(false));
  }

  /* ── autonext: clear khi tắt hoặc không có tập tiếp ── */
  useEffect(() => {
    if (!autoNextEnabled || !onNextEpisode) {
      if (countdownRef.current) { clearInterval(countdownRef.current); countdownRef.current = null; }
      setAutoNextCountdown(null);
    }
  }, [autoNextEnabled, onNextEpisode]);

  /* ── autonext: bắt event ended để bắt đầu đếm ngược ── */
  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    const handler = () => {
      if (!autoNextEnabled || !onNextEpisode) return;
      setAutoNextCountdown(5);
    };
    v.addEventListener("ended", handler);
    return () => v.removeEventListener("ended", handler);
  }, [autoNextEnabled, onNextEpisode]);

  /* ── autonext: tick đếm ngược mỗi giây (dùng setTimeout để tránh stale closure với setInterval) ── */
  useEffect(() => {
    if (autoNextCountdown === null) return;
    if (autoNextCountdown <= 0) {
      setAutoNextCountdown(null);
      onNextEpisode?.();
      return;
    }
    // Dùng setTimeout thay vì setInterval để tránh multiple-interval bug
    const tid = setTimeout(() => {
      setAutoNextCountdown((c) => (c !== null && c > 0 ? c - 1 : null));
    }, 1000);
    return () => clearTimeout(tid);
  // onNextEpisode được gọi chỉ khi countdown === 0, không cần trong deps
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [autoNextCountdown]);

  /* ── sync speed ── */
  useEffect(() => {
    const v = videoRef.current;
    if (v) v.playbackRate = speed;
  }, [speed]);

  /* ── sync volume/mute ── */
  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    v.volume = volume;
    v.muted  = muted;
  }, [volume, muted]);

  useEffect(() => {
    const ad = adVideoRef.current;
    if (!ad) return;
    ad.volume = volume;
    ad.muted = muted;
  }, [volume, muted, adActive]);

  /* ── fullscreen change (webkit-aware) ── */
  useEffect(() => {
    const handler = () => {
      const isFullscreen = Boolean(getFullscreenElement());
      setFullscreen(isFullscreen);
      // Fullscreen transitions can leave the old timer/hidden layer behind.
      // Always expose the toolbar for a fresh, reliable tap target.
      if (sourceReady && !buffering && !error) resetHideTimer();
    };
    document.addEventListener("fullscreenchange", handler);
    document.addEventListener("webkitfullscreenchange", handler);
    return () => {
      document.removeEventListener("fullscreenchange", handler);
      document.removeEventListener("webkitfullscreenchange", handler);
    };
  }, [sourceReady, buffering, error, resetHideTimer]);

  /* ── visibilitychange: không tự pause khi người xem chuyển tab ──
     Nếu hệ điều hành/browser tự hạn chế video nền thì đó là giới hạn của
     trình duyệt; website không chủ động pause và cũng không tự ghi nhận là
     người dùng đã bấm pause. */

  /* ── keyboard ── */
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      const tag = (document.activeElement as HTMLElement)?.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA") return;
      if (adActiveRef.current) {
        if (e.key === " " || e.key === "k") { e.preventDefault(); toggleAdPlayback(); }
        if (e.key === "ArrowRight" || e.key === "ArrowLeft") e.preventDefault();
        return;
      }
      const v = videoRef.current;
      if (!v) return;

      if (e.key === " " || e.key === "k") {
        e.preventDefault();
        if (v.paused) {
          userPausedRef.current = false;
          v.play();
        } else {
          userPausedRef.current = true;
          v.pause();
        }
        resetHideTimer();
      } else if (e.key === "ArrowRight") {
        e.preventDefault();
        v.currentTime = Math.min(v.duration || 0, v.currentTime + 10);
      } else if (e.key === "ArrowLeft") {
        e.preventDefault();
        v.currentTime = Math.max(0, v.currentTime - 10);
      } else if (e.key === "m" || e.key === "M") {
        setMuted((m) => !m);
      } else if (e.key === "f" || e.key === "F") {
        toggleFullscreen();
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [resetHideTimer]);

  /* ── helpers ── */
  function togglePlay() {
    if (adActiveRef.current) { toggleAdPlayback(); return; }
    const v = videoRef.current;
    if (!v) return;
    if (v.paused) {
      userPausedRef.current = false;
      v.play().catch(() => setError("Không thể phát video"));
    } else {
      userPausedRef.current = true;
      v.pause();
    }
  }

  function toggleFullscreen() {
    const el = wrapRef.current;
    const v = videoRef.current;
    if (!el) return;
    if (fullscreenBusyRef.current) return;
    fullscreenBusyRef.current = true;
    const releaseFullscreenLock = () => {
      window.setTimeout(() => { fullscreenBusyRef.current = false; }, 220);
    };

    if (isIOSDevice() && v) {
      const nativeVideo = v as HTMLVideoElement & {
        webkitEnterFullscreen?: () => void;
        webkitExitFullscreen?: () => void;
        webkitDisplayingFullscreen?: boolean;
      };
      if (fullscreen || nativeFullscreenRef.current || nativeVideo.webkitDisplayingFullscreen) {
        if (getFullscreenElement()) exitFullscreenCompat().catch(() => {});
        else nativeVideo.webkitExitFullscreen?.();
      } else if (nativeVideo.webkitEnterFullscreen) {
        nativeVideo.webkitEnterFullscreen();
      } else if (v.requestFullscreen) {
        v.requestFullscreen().catch(() => {});
      }
      releaseFullscreenLock();
      return;
    }

    if (!getFullscreenElement()) {
      // Update the icon immediately; the fullscreenchange event will reconcile
      // the state if the browser rejects the request.
      setFullscreen(true);
      // On mobile Chrome, try the wrapper first; if it fails try the video element itself
      requestFullscreenCompat(el).catch(() => {
        setFullscreen(false);
        if (v) requestFullscreenCompat(v).then(() => setFullscreen(true)).catch(() => {}).finally(releaseFullscreenLock);
        else releaseFullscreenLock();
      }).then(() => {
        releaseFullscreenLock();
      });
    } else {
      setFullscreen(false);
      exitFullscreenCompat().catch(() => {}).then(releaseFullscreenLock);
    }
  }

  function changeVolume(rawValue: number) {
    const nextVolume = Math.max(0, Math.min(1, rawValue));
    const v = videoRef.current;
    // Apply immediately as well as through React state; this avoids a delayed
    // audio update on mobile Safari while the range thumb is being dragged.
    if (v) {
      v.volume = nextVolume;
      if (nextVolume > 0) v.muted = false;
    }
    setVolume(nextVolume);
    if (nextVolume > 0) setMuted(false);
  }

  const progress = duration > 0 ? (currentTime / duration) * 100 : 0;

  /* ─── Interaction handlers ────────────────────────────── */

  function handleOverlayClick(e: React.MouseEvent) {
    if (e.defaultPrevented) return;
    if (
      (e.target as HTMLElement).closest(
        ".cinema-player-controls, .cinema-player-center-toggle, .cinema-speed-dropdown"
      )
    )
      return;

    if (isMobile) return;

    togglePlay();
    resetHideTimer();
  }

  function handleOverlayTouchStart(e: React.TouchEvent) {
    const t = e.touches[0];
    touchStart.current = { x: t.clientX, y: t.clientY };
  }

  function handleOverlayTouchEnd(e: React.TouchEvent) {
    if (!touchStart.current) return;
    const t = e.changedTouches[0];
    const dx = Math.abs(t.clientX - touchStart.current.x);
    const dy = Math.abs(t.clientY - touchStart.current.y);
    touchStart.current = null;

    if (dx > 12 || dy > 12) return;

    if (
      (e.target as HTMLElement).closest(
        ".cinema-player-controls, .cinema-player-center-toggle, .cinema-speed-dropdown"
      )
    )
      return;

    e.preventDefault();

    if (controlsVisible) {
      setControlsVisible(false);
      if (hideTimer.current) clearTimeout(hideTimer.current);
    } else {
      resetHideTimer();
    }
  }

  function handleOverlayPointerDown(e: React.PointerEvent) {
    if (e.pointerType === "mouse" && e.button !== 0) return;
    pointerStart.current = { x: e.clientX, y: e.clientY };
  }

  function handleOverlayPointerUp(e: React.PointerEvent) {
    const start = pointerStart.current;
    pointerStart.current = null;
    if (!start || (e.pointerType === "mouse" && e.button !== 0)) return;
    if (e.pointerType === "touch") lastPointerTouchAt.current = Date.now();
    if (Math.hypot(e.clientX - start.x, e.clientY - start.y) > 14) return;
    if ((e.target as HTMLElement).closest(".cinema-player-controls, .cinema-player-center-toggle, .cinema-speed-dropdown")) return;

    // A pointer event is delivered reliably in native and browser fullscreen,
    // unlike touchend on some mobile browsers. It only toggles the chrome;
    // playback itself is controlled by the explicit play button.
    e.preventDefault();
    if (controlsVisible) {
      if (hideTimer.current) clearTimeout(hideTimer.current);
      setControlsVisible(false);
    } else {
      resetHideTimer();
    }
  }

  /* ─── Embed fallback ──────────────────────────────────── */
  if (!streamUrl && fallbackEmbedUrl) {
    return (
      <div className="player-shell">
        <div className="player-empty">
          <Film size={28} />
          <strong>Nguồn nhúng không hỗ trợ quảng cáo an toàn</strong>
          <span>Hãy chọn nguồn phát HLS để xem phim có quảng cáo giữa chừng và tiếp tục đúng tiến trình.</span>
        </div>
      </div>
    );
  }

  if (!streamUrl) return null;

  /* ─── Render ──────────────────────────────────────────── */
  return (
    <>
    <div
      ref={wrapRef}
      className={`cinema-player${controlsVisible ? " controls-visible" : " controls-hidden"}${playing ? " is-playing" : ""}${adActive ? " is-ad-playing" : ""}`}
      style={
        posterUrl
          ? ({ "--player-bg": `url(${posterUrl})` } as React.CSSProperties)
          : undefined
      }
      tabIndex={0}
      onMouseMove={() => { if (!isMobile) resetHideTimer(); }}
      onMouseLeave={() => {
        if (!isMobile && playing) {
          if (hideTimer.current) clearTimeout(hideTimer.current);
          setControlsVisible(false);
        }
      }}
      onClick={handleOverlayClick}
      onPointerDown={handleOverlayPointerDown}
      onPointerUp={handleOverlayPointerUp}
    >
      {/* Vignette gradient */}
      <div className="cinema-player-vignette" />

      {/* Video */}
      <video
        ref={videoRef}
        poster={posterUrl}
        style={{ filter: `brightness(${brightness})` }}
        preload="metadata"
        playsInline
        webkit-playsinline="true"
        x5-playsinline="true"
        onClick={(e) => e.stopPropagation()}
        onTouchEnd={(e) => e.stopPropagation()}
      />

      {adActive && !nativeFullscreenAd && (
        <video
          ref={adVideoRef}
          className="cinema-ad-video"
          src={AD_VIDEO_URL}
          playsInline
          webkit-playsinline="true"
          preload="auto"
          controls={false}
          disablePictureInPicture
          controlsList="nodownload noplaybackrate noremoteplayback"
          onTimeUpdate={(e) => setAdCurrentTime(e.currentTarget.currentTime)}
          onDurationChange={(e) => setAdDuration(e.currentTarget.duration || 0)}
          onPause={() => setAdPlaying(false)}
          onPlay={() => { setAdPlaying(true); setAdError(false); }}
          onEnded={finishAd}
          onError={() => { setAdPlaying(false); setAdError(true); }}
          onSeeking={(e) => {
            const ad = e.currentTarget;
            if (Math.abs(ad.currentTime - adCurrentTime) > 1) ad.currentTime = adCurrentTime;
          }}
          onContextMenu={(e) => e.preventDefault()}
          onClick={(e) => e.stopPropagation()}
        />
      )}

      {adActive && !nativeFullscreenAd && (
        <div className="cinema-ad-overlay" aria-live="polite">
          <span className="cinema-ad-badge">QUẢNG CÁO</span>
          <span className="cinema-ad-countdown">{adDuration > 0 ? `Còn ${fmt(Math.max(0, adDuration - adCurrentTime))}` : "Đang tải quảng cáo…"}</span>
          {adError && (
            <div className="cinema-ad-error">
              <strong>Không tải được quảng cáo</strong>
              <button type="button" onClick={(e) => { e.stopPropagation(); retryAd(); }}>Thử lại</button>
            </div>
          )}
        </div>
      )}

      {/* Brand */}
      <div className="cinema-player-brand">
        <img src={CINEMORA_LOGO_URL} alt="Cinemora" />
      </div>

      {/* Title */}
      {title && (
        <div className="cinema-player-title">
          <span>{title}</span>
          <small>{adActive ? "Quảng cáo" : buffering ? "Đang tải nguồn…" : playing ? "Đang phát" : "Đã tạm dừng"}</small>
        </div>
      )}

      {/* Buffering / Error overlay */}
      {(buffering || error) && (
        <div className={`cinema-player-state${error ? " cinema-player-error" : ""}`}>
          {error ? (
            <>
              <Film size={28} />
              <strong>Không thể phát</strong>
              <span>{error}</span>
              <div style={{ display: "flex", gap: 8, marginTop: 8 }}>
                <button
                  className="button button-ghost"
                  style={{ fontSize: 11, minHeight: 33 }}
                  onClick={(e) => {
                    e.stopPropagation();
                    if (hlsRef.current) { hlsRef.current.destroy(); hlsRef.current = null; }
                    setError(null);
                    setBuffering(true);
                    setSourceReady(false);
                    setPlaying(false);
                    userPausedRef.current = false;
                    const v = videoRef.current;
                    const src = streamUrlRef.current;
                    if (!v || !src) return;
                    if (Hls.isSupported()) {
                      const hls = new Hls({ enableWorker: true, backBufferLength: 60 });
                      hlsRef.current = hls;
                      hls.attachMedia(v);
                      hls.on(Hls.Events.MANIFEST_PARSED, () => {
                        // The shared canplay handler starts playback only after
                        // HLS has supplied decodable media data.
                      });
                      hls.on(Hls.Events.ERROR, (_e: any, d: any) => {
                        if (d.fatal) {
                          setError("Nguồn phim lỗi hoặc không khả dụng.");
                          setBuffering(false);
                          setSourceReady(false);
                        }
                      });
                      hls.loadSource(src);
                    } else {
                      v.src = src;
                      v.load();
                    }
                  }}
                >
                  <RefreshCw size={14} /> Thử lại
                </button>
              </div>
            </>
          ) : (
            <RefreshCw size={22} className="spin" />
          )}
        </div>
      )}

      {/* Centre Play/Pause button */}
      {sourceReady && !buffering && !error && <button
        className={`cinema-player-center-toggle${playing && !controlsVisible ? " is-hidden" : ""}`}
        aria-label={playing ? "Dừng" : "Phát"}
        onClick={(e) => { e.stopPropagation(); togglePlay(); resetHideTimer(); }}
        onTouchEnd={(e) => { e.stopPropagation(); e.preventDefault(); togglePlay(); resetHideTimer(); }}
      >
        {adActive ? (adPlaying ? <Pause size={22} fill="currentColor" /> : <Play size={22} fill="currentColor" />) : (playing
          ? <Pause size={22} fill="currentColor" />
          : <Play  size={22} fill="currentColor" />)}
      </button>}

      {/* Controls bar */}
      {sourceReady && !buffering && !error && <div
        className="cinema-player-controls"
        onClick={(e) => e.stopPropagation()}
        onTouchEnd={(e) => e.stopPropagation()}
        onMouseEnter={() => { if (!isMobile && hideTimer.current) clearTimeout(hideTimer.current); }}
        onMouseLeave={() => { if (!isMobile && playing) resetHideTimer(); }}
      >
        {/* Progress */}
        <input
          type="range"
          className="cinema-progress"
          min={0}
          max={(adActive ? adDuration : duration) || 100}
          step={0.5}
          value={adActive ? adCurrentTime : currentTime}
          disabled={adActive}
          onChange={(e) => {
            if (adActiveRef.current) return;
            const v = videoRef.current;
            const t = Number(e.target.value);
            if (v) v.currentTime = t;
            setCurrentTime(t);
          }}
          style={{ "--progress": `${adActive ? (adDuration > 0 ? adCurrentTime / adDuration * 100 : 0) : progress}%` } as React.CSSProperties}
          aria-label="Tiến độ phát"
          onTouchStart={(e) => e.stopPropagation()}
          onTouchEnd={(e) => e.stopPropagation()}
        />

        <div className="cinema-control-row">
          {/* Left group */}
          <div className="cinema-control-group">
            {/* Play/Pause */}
            <button
              aria-label={adActive ? (adPlaying ? "Tạm dừng quảng cáo" : "Phát quảng cáo") : (playing ? "Dừng" : "Phát")}
              onClick={(e) => { e.stopPropagation(); togglePlay(); }}
              onTouchEnd={(e) => { e.stopPropagation(); e.preventDefault(); togglePlay(); }}
            >
              {adActive ? (adPlaying ? <Pause size={16} fill="currentColor" /> : <Play size={16} fill="currentColor" />) : playing
                ? <Pause size={16} fill="currentColor" />
                : <Play  size={16} fill="currentColor" />}
            </button>

            {/* Rewind 10s */}
            {!adActive && <button
              aria-label="Tua lùi 10 giây"
              onClick={(e) => { e.stopPropagation(); const v = videoRef.current; if (v) v.currentTime = Math.max(0, v.currentTime - 10); }}
              onTouchEnd={(e) => { e.stopPropagation(); e.preventDefault(); const v = videoRef.current; if (v) v.currentTime = Math.max(0, v.currentTime - 10); }}
            >
              <Rewind size={15} />
            </button>}

            {/* Forward 10s */}
            {!adActive && <button
              aria-label="Tua tiến 10 giây"
              onClick={(e) => { e.stopPropagation(); const v = videoRef.current; if (v) v.currentTime = Math.min(v.duration || 0, v.currentTime + 10); }}
              onTouchEnd={(e) => { e.stopPropagation(); e.preventDefault(); const v = videoRef.current; if (v) v.currentTime = Math.min(v.duration || 0, v.currentTime + 10); }}
            >
              <FastForward size={15} />
            </button>}

            {/* Volume */}
            <div className={`cinema-vol-inline${volumeOpen ? " is-open" : ""}`}>
              <button
                className={`cinema-vol-icon-btn${muted || volume === 0 ? " is-muted" : ""}`}
                aria-label={isMobile ? (volumeOpen ? (muted ? "Bật tiếng" : "Tắt tiếng") : "Hiện thanh âm lượng") : (muted ? "Bật tiếng" : "Tắt tiếng")}
                onClick={(e) => {
                  e.stopPropagation();
                  if (isMobile) {
                    if (!volumeOpen) setVolumeOpen(true);
                    else { setMuted((m) => !m); setVolumeOpen(false); }
                  } else setMuted((m) => !m);
                }}
              >
                {muted || volume === 0 ? <VolumeX size={16} /> : <Volume2 size={16} />}
              </button>
              <input
                type="range"
                className="cinema-volume"
                min={0} max={1} step={0.02}
                value={muted ? 0 : volume}
                onInput={(e) => changeVolume(Number((e.target as HTMLInputElement).value))}
                onChange={(e) => changeVolume(Number(e.target.value))}
                style={{ "--vol": `${Math.round((muted ? 0 : volume) * 100)}%` } as React.CSSProperties}
                aria-label="Âm lượng"
                onTouchStart={(e) => e.stopPropagation()}
                onTouchMove={(e) => e.stopPropagation()}
                onTouchEnd={(e) => e.stopPropagation()}
                onPointerDown={(e) => e.stopPropagation()}
                onPointerMove={(e) => e.stopPropagation()}
                onPointerUp={(e) => e.stopPropagation()}
              />
              <span className="cinema-vol-pct">{Math.round((muted ? 0 : volume) * 100)}%</span>
            </div>

            {/* Time */}
            <span className="cinema-time">{adActive ? `${fmt(adCurrentTime)} / ${fmt(adDuration)}` : `${fmt(currentTime)} / ${fmt(duration)}`}</span>
          </div>

          {/* Right group */}
          <div className="cinema-control-group">
            {/* Brightness */}
            {!adActive && <div className="cinema-brightness-inline">
              <Sun size={15} aria-hidden="true" />
              <input
                type="range"
                className="cinema-brightness"
                min={0.7}
                max={1.6}
                step={0.05}
                value={brightness}
                onInput={(e) => setBrightness(Number((e.target as HTMLInputElement).value))}
                onChange={(e) => setBrightness(Number(e.target.value))}
                style={{ "--brightness": `${((brightness - 0.7) / 0.9) * 100}%` } as React.CSSProperties}
                aria-label={`Độ sáng ${Math.round(brightness * 100)} phần trăm`}
                onTouchStart={(e) => e.stopPropagation()}
                onTouchMove={(e) => e.stopPropagation()}
                onTouchEnd={(e) => e.stopPropagation()}
                onPointerDown={(e) => e.stopPropagation()}
                onPointerMove={(e) => e.stopPropagation()}
                onPointerUp={(e) => e.stopPropagation()}
              />
              <span>{Math.round(brightness * 100)}%</span>
            </div>}
            {/* Speed */}
            {!adActive && <div className="cinema-speed-wrap">
              <button
                className={`cinema-speed-btn${speedOpen ? " is-open" : ""}`}
                aria-label="Tốc độ phát"
                onClick={(e) => { e.stopPropagation(); setSpeedOpen((o) => !o); }}
                onTouchEnd={(e) => { e.stopPropagation(); e.preventDefault(); setSpeedOpen((o) => !o); }}
              >
                {speed === 1 ? "1×" : `${speed}×`}
                <ChevronUp size={12} className="cinema-speed-chevron" />
              </button>

              {speedOpen && !isMobile && (
                <SpeedDropdown
                  current={speed}
                  onSelect={(s) => { setSpeed(s); if (videoRef.current) videoRef.current.playbackRate = s; }}
                  onClose={() => setSpeedOpen(false)}
                />
              )}
              {speedOpen && isMobile && (
                <SpeedSheet
                  current={speed}
                  onSelect={(s) => { setSpeed(s); if (videoRef.current) videoRef.current.playbackRate = s; }}
                  onClose={() => setSpeedOpen(false)}
                />
              )}
            </div>}

            {/* Next episode */}
            {onNextEpisode && !adActive && (
              <button
                aria-label={nextEpisodeLabel || "Tập tiếp theo"}
                onClick={(e) => { e.stopPropagation(); onNextEpisode(); }}
                onTouchEnd={(e) => { e.stopPropagation(); e.preventDefault(); onNextEpisode(); }}
              >
                <SkipForward size={15} />
              </button>
            )}

            {/* Fullscreen */}
            <button
              aria-label={fullscreen ? "Thoát toàn màn hình" : "Toàn màn hình"}
              onClick={(e) => { e.stopPropagation(); toggleFullscreen(); }}
            >
              {fullscreen ? <Minimize size={15} /> : <Maximize size={15} />}
            </button>
          </div>
        </div>
      </div>}

      {/* AutoNext countdown overlay */}
      {autoNextCountdown !== null && onNextEpisode && (
        <div className="autonext-overlay">
          <div className="autonext-card">
            <SkipForward size={18} />
            <div className="autonext-info">
              <strong>Tự động chuyển tập sau {autoNextCountdown}s</strong>
              <span>{nextEpisodeLabel || "Tập tiếp theo"}</span>
            </div>
            <div className="autonext-actions">
              <button
                className="button button-primary autonext-now"
                onClick={(e) => { e.stopPropagation(); setAutoNextCountdown(null); onNextEpisode(); }}
                onTouchEnd={(e) => { e.stopPropagation(); e.preventDefault(); setAutoNextCountdown(null); onNextEpisode(); }}
              >
                Xem ngay
              </button>
              <button
                className="button button-ghost autonext-cancel"
                onClick={(e) => { e.stopPropagation(); setAutoNextCountdown(null); }}
                onTouchEnd={(e) => { e.stopPropagation(); e.preventDefault(); setAutoNextCountdown(null); }}
              >
                Huỷ
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Click-away to close speed dropdown (desktop) */}
      {speedOpen && !isMobile && (
        <div
          style={{ position: "fixed", inset: 0, zIndex: 7 }}
          onClick={(e) => { e.stopPropagation(); setSpeedOpen(false); }}
        />
      )}
    </div>

    {/* ── Below-player bar: auto-next toggle + next episode info ── */}
    {onNextEpisode && !adActive && (
      <div className="player-meta-bar">
        <div className="player-meta-autonext">
          <button
            className={`autonext-meta-toggle${autoNextEnabled ? " is-on" : ""}`}
            onClick={(e) => { e.stopPropagation(); onAutoNextToggle?.(!autoNextEnabled); }}
          >
            <span className="autonext-meta-pill" />
            <span className="autonext-meta-label">
              Tự động chuyển tập
            </span>
          </button>
          {autoNextEnabled && nextEpisodeLabel && (
            <span className="player-meta-next-label">
              <SkipForward size={12} />
              Tiếp theo: <strong>{nextEpisodeLabel}</strong>
            </span>
          )}
        </div>
        <button
          className="player-meta-skip-btn"
          onClick={(e) => { e.stopPropagation(); onNextEpisode(); }}
        >
          <SkipForward size={14} />
          Tập tiếp theo
        </button>
      </div>
    )}
    </>
  );
}
