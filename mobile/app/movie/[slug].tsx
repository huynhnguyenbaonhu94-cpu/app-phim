import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  ActivityIndicator,
  Modal,
  PanResponder,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { Ionicons } from "@expo/vector-icons";
import { useLocalSearchParams, router } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { VideoView, useVideoPlayer } from "expo-video";
import * as ScreenOrientation from "expo-screen-orientation";
import { absoluteUrl, api, Episode, Movie, MovieServer } from "@/api";
import { C, GlassContainer, Poster, ScreenAtmosphere, styles } from "@/ui";

function formatTime(seconds: number) {
  if (!Number.isFinite(seconds) || seconds < 0) return "00:00";
  const whole = Math.floor(seconds);
  const hours = Math.floor(whole / 3600);
  const minutes = Math.floor((whole % 3600) / 60);
  const secs = whole % 60;
  return hours > 0 ? `${hours}:${String(minutes).padStart(2, "0")}:${String(secs).padStart(2, "0")}` : `${String(minutes).padStart(2, "0")}:${String(secs).padStart(2, "0")}`;
}

type VideoFit = "contain" | "fill" | "cover";
const VIDEO_FIT_LABELS: Record<VideoFit, string> = { contain: "Vừa", fill: "Đầy", cover: "Phủ" };
const PLAYBACK_RATES = [0.5, 0.75, 1, 1.25, 1.5, 2] as const;
type PlaybackRate = typeof PLAYBACK_RATES[number];
const playbackRateLabel = (rate: PlaybackRate) => `${rate}x`;

function SeekBar({
  currentTime,
  duration,
  onSeek,
  onInteraction,
}: {
  currentTime: number;
  duration: number;
  onSeek: (seconds: number) => void;
  onInteraction: () => void;
}) {
  const barRef = useRef<View>(null);
  const leftRef = useRef(0);
  const widthRef = useRef(0);
  const dragTimeRef = useRef<number | null>(null);
  const seekRef = useRef(onSeek);
  const interactionRef = useRef(onInteraction);
  const durationRef = useRef(duration);
  const [dragTime, setDragTime] = useState<number | null>(null);
  seekRef.current = onSeek;
  interactionRef.current = onInteraction;
  durationRef.current = duration;

  const value = dragTime ?? currentTime;
  const ratio = duration > 0 ? Math.max(0, Math.min(1, value / duration)) : 0;
  const updateFromPageX = (pageX: number) => {
    if (widthRef.current <= 0 || durationRef.current <= 0) return;
    const fraction = Math.max(0, Math.min(1, (pageX - leftRef.current) / widthRef.current));
    const nextTime = fraction * durationRef.current;
    dragTimeRef.current = nextTime;
    setDragTime(nextTime);
  };
  const panResponder = useMemo(() => PanResponder.create({
    onStartShouldSetPanResponder: () => durationRef.current > 0,
    onMoveShouldSetPanResponder: () => durationRef.current > 0,
    onPanResponderGrant: (_event, gesture) => {
      interactionRef.current();
      barRef.current?.measureInWindow((x, _y, width) => {
        leftRef.current = x;
        widthRef.current = width;
        updateFromPageX(gesture.x0);
      });
    },
    onPanResponderMove: (_event, gesture) => updateFromPageX(gesture.moveX),
    onPanResponderRelease: (_event, gesture) => {
      updateFromPageX(gesture.moveX);
      const target = dragTimeRef.current;
      dragTimeRef.current = null;
      setDragTime(null);
      if (target !== null) seekRef.current(target);
    },
    onPanResponderTerminate: () => {
      const target = dragTimeRef.current;
      dragTimeRef.current = null;
      setDragTime(null);
      if (target !== null) seekRef.current(target);
    },
  }), []);

  return <View
    ref={barRef}
    onLayout={event => {
      widthRef.current = event.nativeEvent.layout.width;
      barRef.current?.measureInWindow((x, _y, width) => {
        leftRef.current = x;
        widthRef.current = width;
      });
    }}
    style={playerStyles.progressTouch}
    {...panResponder.panHandlers}
  >
    <View pointerEvents="none" style={playerStyles.progressTrack}>
      <View style={[playerStyles.progressFill, { width: `${ratio * 100}%` }]} />
      <View style={[playerStyles.progressThumb, { left: `${ratio * 100}%` }]} />
    </View>
  </View>;
}

function VolumeSlider({ value, onChange, onInteraction }: { value: number; onChange: (value: number) => void; onInteraction: () => void }) {
  const ref = useRef<View>(null);
  const left = useRef(0);
  const width = useRef(0);
  const update = (pageX: number) => {
    if (!width.current) return;
    onChange(Math.max(0, Math.min(1, (pageX - left.current) / width.current)));
    onInteraction();
  };
  const responder = useMemo(() => PanResponder.create({
    onStartShouldSetPanResponder: () => true,
    onMoveShouldSetPanResponder: () => true,
    onPanResponderGrant: event => { ref.current?.measureInWindow((x, _y, w) => { left.current = x; width.current = w; update(event.nativeEvent.pageX); }); },
    onPanResponderMove: event => update(event.nativeEvent.pageX),
    onPanResponderRelease: event => update(event.nativeEvent.pageX),
  }), []);
  return <View ref={ref} onLayout={event => { width.current = event.nativeEvent.layout.width; ref.current?.measureInWindow((x, _y, w) => { left.current = x; width.current = w; }); }} style={playerStyles.volumeSliderTouch} {...responder.panHandlers}>
    <View style={playerStyles.volumeTrack}><View style={[playerStyles.volumeFill, { width: `${value * 100}%` }]} /><View style={[playerStyles.volumeThumb, { left: `${value * 100}%` }]} /></View>
  </View>;
}

function PlayerControls({
  title,
  playing,
  muted,
  volume,
  locked,
  currentTime,
  duration,
  fullscreen,
  onPlayback,
  onSkip,
  onMute,
  onVolumeChange,
  onLockToggle,
  onFullscreen,
  onCloseFullscreen,
  onSeek,
  onInteraction,
  videoFit,
  fitMenuOpen,
  onFitMenuToggle,
  onFitSelect,
  playbackRate,
  speedMenuOpen,
  onSpeedMenuToggle,
  onSpeedSelect,
  episodes,
  servers,
  episodeIndex,
  serverIndex,
  onSelectEpisode,
  onSelectServer,
  pickerOpen,
  onPickerToggle,
}: {
  title: string;
  playing: boolean;
  muted: boolean;
  volume: number;
  locked: boolean;
  currentTime: number;
  duration: number;
  fullscreen: boolean;
  onPlayback: () => void;
  onSkip: (seconds: number) => void;
  onMute: () => void;
  onVolumeChange: (delta: number) => void;
  onLockToggle: () => void;
  onFullscreen: () => void;
  onCloseFullscreen: () => void;
  onSeek: (seconds: number) => void;
  onInteraction: () => void;
  videoFit: VideoFit;
  fitMenuOpen: boolean;
  onFitMenuToggle: () => void;
  onFitSelect: (fit: VideoFit) => void;
  playbackRate: PlaybackRate;
  speedMenuOpen: boolean;
  onSpeedMenuToggle: () => void;
  onSpeedSelect: (rate: PlaybackRate) => void;
  episodes: Episode[];
  servers: MovieServer[];
  episodeIndex: number;
  serverIndex: number;
  onSelectEpisode: (index: number) => void;
  onSelectServer: (index: number) => void;
  pickerOpen: "episodes" | "servers" | null;
  onPickerToggle: (picker: "episodes" | "servers") => void;
}) {
  const [volumeOpen, setVolumeOpen] = useState(false);
  const volumeRef = useRef(volume);
  volumeRef.current = volume;
  const volumeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const revealVolume = () => { setVolumeOpen(true); if (volumeTimer.current) clearTimeout(volumeTimer.current); volumeTimer.current = setTimeout(() => setVolumeOpen(false), 3500); };
  const handleVolumeIcon = () => {
    onInteraction();
    if (volumeOpen) {
      if (volumeTimer.current) clearTimeout(volumeTimer.current);
      setVolumeOpen(false);
    } else {
      revealVolume();
    }
  };
  return <View style={[playerStyles.controls, fullscreen && playerStyles.fullscreenControls]}>
    <View style={playerStyles.topControls}>
      {fullscreen ? <Pressable accessibilityLabel="Thoát toàn màn hình" onPress={onCloseFullscreen} style={playerStyles.iconButton}><Ionicons name="contract-outline" size={20} color={C.text} /></Pressable> : null}
      <View style={[playerStyles.sourceBadge, fullscreen && playerStyles.fullscreenSourceBadge]}><View style={playerStyles.liveDot} /><Text style={playerStyles.sourceText} numberOfLines={1}>{title} · {VIDEO_FIT_LABELS[videoFit]}</Text></View>
      <View style={playerStyles.topActions}>
        {fullscreen ? <View style={playerStyles.fitMenuWrap}>
          <Pressable accessibilityLabel="Tỷ lệ khung hình" onPress={() => { onInteraction(); onFitMenuToggle(); }} style={playerStyles.fitButton}>
            <Ionicons name="resize-outline" size={17} color={C.text} />
            <Text style={playerStyles.fitButtonText}>{VIDEO_FIT_LABELS[videoFit]}</Text>
          </Pressable>
          {fitMenuOpen && <View style={playerStyles.fitMenu}>
            {(Object.keys(VIDEO_FIT_LABELS) as VideoFit[]).map(fit => <Pressable key={fit} accessibilityLabel={`Tỷ lệ ${VIDEO_FIT_LABELS[fit]}`} onPress={() => { onFitSelect(fit); onInteraction(); }} style={[playerStyles.fitOption, fit === videoFit && playerStyles.fitOptionActive]}>
              <Text style={[playerStyles.fitOptionText, fit === videoFit && playerStyles.fitOptionTextActive]}>{VIDEO_FIT_LABELS[fit]}</Text>
              {fit === videoFit && <Ionicons name="checkmark" size={15} color={C.accent} />}
            </Pressable>)}
          </View>}
        </View> : null}
        {fullscreen ? <View style={playerStyles.fitMenuWrap}>
          <Pressable accessibilityLabel="Tốc độ phát" onPress={() => { onInteraction(); onSpeedMenuToggle(); }} style={playerStyles.speedButton}>
            <Ionicons name="speedometer-outline" size={17} color={C.text} />
            <Text style={playerStyles.fitButtonText}>{playbackRateLabel(playbackRate)}</Text>
          </Pressable>
          {speedMenuOpen && <View style={[playerStyles.fitMenu, playerStyles.speedMenu]}>
            {PLAYBACK_RATES.map(rate => <Pressable key={rate} accessibilityLabel={`Tốc độ ${playbackRateLabel(rate)}`} onPress={() => { onSpeedSelect(rate); onInteraction(); }} style={[playerStyles.fitOption, rate === playbackRate && playerStyles.fitOptionActive]}>
              <Text style={[playerStyles.fitOptionText, rate === playbackRate && playerStyles.fitOptionTextActive]}>{rate === 1 ? "Bình thường · 1x" : playbackRateLabel(rate)}</Text>
              {rate === playbackRate && <Ionicons name="checkmark" size={15} color={C.accent} />}
            </Pressable>)}
          </View>}
        </View> : null}
        {fullscreen ? <Pressable accessibilityLabel="Danh sách tập" onPress={() => { onInteraction(); onPickerToggle("episodes"); }} style={playerStyles.iconButton}><Ionicons name="list-outline" size={18} color={C.text} /></Pressable> : null}
        {fullscreen && servers.length > 1 ? <Pressable accessibilityLabel="Đổi nguồn phát" onPress={() => { onInteraction(); onPickerToggle("servers"); }} style={playerStyles.iconButton}><Ionicons name="layers-outline" size={18} color={C.text} /></Pressable> : null}
        {fullscreen ? <Pressable accessibilityLabel={locked ? "Mở khóa điều khiển" : "Khóa điều khiển"} onPress={onLockToggle} style={playerStyles.iconButton}><Ionicons name={locked ? "lock-closed" : "lock-open-outline"} size={17} color={C.text} /></Pressable> : null}
        {!fullscreen ? <Pressable accessibilityLabel="Toàn màn hình" onPress={onFullscreen} style={playerStyles.iconButton}><Ionicons name="expand-outline" size={18} color={C.text} /></Pressable> : <View style={playerStyles.fullscreenSpacer} />}
      </View>
    </View>

    <View style={[playerStyles.centerControls, fullscreen && playerStyles.fullscreenCenterControls]}>
      <Pressable accessibilityLabel="Lùi 10 giây" onPress={() => { onInteraction(); onSkip(-10); }} style={playerStyles.skipButton}>
        <Ionicons name="play-back" size={20} color={C.text} />
        <Text style={playerStyles.skipLabel}>10</Text>
      </Pressable>
      <Pressable accessibilityLabel={playing ? "Tạm dừng" : "Phát"} onPress={() => { onInteraction(); onPlayback(); }} style={[playerStyles.playButton, fullscreen && playerStyles.playButtonLarge]}><Ionicons name={playing ? "pause" : "play"} size={fullscreen ? 33 : 28} color="#11150a" style={!playing ? { marginLeft: 3 } : undefined} /></Pressable>
      <Pressable accessibilityLabel="Tiến 10 giây" onPress={() => { onInteraction(); onSkip(10); }} style={playerStyles.skipButton}>
        <Ionicons name="play-forward" size={20} color={C.text} />
        <Text style={playerStyles.skipLabel}>10</Text>
      </Pressable>
    </View>
    <View style={[playerStyles.adjustmentControls, fullscreen && playerStyles.fullscreenAdjustmentControls]}>
      {volumeOpen && <View style={playerStyles.volumePopover}>
        <Text style={playerStyles.volumePercent}>{Math.round(volume * 100)}%</Text>
        <VolumeSlider value={volume} onChange={value => { onVolumeChange(value - volumeRef.current); }} onInteraction={revealVolume} />
        <Pressable accessibilityRole="button" accessibilityLabel={muted || volume === 0 ? "Bật âm thanh" : "Tắt âm thanh"} hitSlop={6} onPress={onMute} style={playerStyles.popoverMuteButton}>
          <Ionicons name={muted || volume === 0 ? "volume-mute" : "volume-high"} size={18} color={C.text} />
        </Pressable>
      </View>}
      <Pressable accessibilityRole="button" accessibilityLabel={volumeOpen ? "Ẩn thanh âm lượng" : "Hiện thanh âm lượng"} accessibilityHint="Chạm để mở hoặc đóng thanh chỉnh âm lượng" onPress={handleVolumeIcon} style={playerStyles.volumeButton}><Ionicons name={muted || volume === 0 ? "volume-mute" : volume < 0.5 ? "volume-low" : "volume-high"} size={22} color={C.text} /></Pressable>
    </View>
    <View style={playerStyles.bottomControls}>
      <Text style={[playerStyles.timeText, fullscreen && playerStyles.fullscreenTime]}>{formatTime(currentTime)}</Text>
      <SeekBar currentTime={currentTime} duration={duration} onSeek={onSeek} onInteraction={onInteraction} />
      <Text style={[playerStyles.timeText, fullscreen && playerStyles.fullscreenTime]}>{duration > 0 ? formatTime(duration) : "--:--"}</Text>
    </View>
  </View>;
}


function EpisodePicker({
  kind,
  episodes,
  servers,
  episodeIndex,
  serverIndex,
  onSelectEpisode,
  onSelectServer,
  onClose,
}: {
  kind: "episodes" | "servers";
  episodes: Episode[];
  servers: MovieServer[];
  episodeIndex: number;
  serverIndex: number;
  onSelectEpisode: (index: number) => void;
  onSelectServer: (index: number) => void;
  onClose: () => void;
}) {
  const isEpisodes = kind === "episodes";
  const selectedName = isEpisodes
    ? (episodes[episodeIndex]?.name || `Tập ${episodeIndex + 1}`)
    : (servers[serverIndex]?.name || `Nguồn ${serverIndex + 1}`);
  const count = isEpisodes ? episodes.length : servers.length;
  return <View style={playerStyles.pickerLayer}>
    <Pressable accessibilityLabel="Đóng danh sách" onPress={onClose} style={playerStyles.pickerBackdrop} />
    <View style={playerStyles.pickerPanel}>
      <View style={playerStyles.pickerGrabber} />
      <View style={playerStyles.pickerHeader}>
        <View style={playerStyles.pickerHeadingCopy}>
          <Text style={playerStyles.pickerKicker}>CINEMORA  ·  {isEpisodes ? "TẬP PHIM" : "CHẤT LƯỢNG PHÁT"}</Text>
          <Text style={playerStyles.pickerTitle}>{isEpisodes ? "Danh sách tập" : "Chọn nguồn phát"}</Text>
          <Text style={playerStyles.pickerSubtitle}>{count} lựa chọn  ·  Đang chọn: {selectedName}</Text>
        </View>
        <Pressable accessibilityRole="button" accessibilityLabel="Đóng danh sách" hitSlop={8} onPress={onClose} style={playerStyles.pickerClose}>
          <Ionicons name="close" size={21} color={C.text} />
        </Pressable>
      </View>
      <ScrollView style={playerStyles.pickerScroll} contentContainerStyle={playerStyles.pickerGrid} showsVerticalScrollIndicator nestedScrollEnabled>
        {isEpisodes
          ? episodes.map((item, index) => {
              const active = index === episodeIndex;
              return <Pressable key={`${item.slug || item.name || "episode"}-${index}`} accessibilityRole="button" accessibilityState={{ selected: active }} onPress={() => onSelectEpisode(index)} style={[playerStyles.pickerItem, active && playerStyles.pickerItemActive]}>
                <Text style={[playerStyles.pickerItemIndex, active && playerStyles.pickerItemIndexActive]}>{String(index + 1).padStart(2, "0")}</Text>
                <Text style={[playerStyles.pickerItemText, active && playerStyles.pickerItemTextActive]} numberOfLines={2}>{item.name || `Tập ${index + 1}`}</Text>
                {active && <Ionicons name="checkmark-circle" size={19} color="#11150a" />}
              </Pressable>;
            })
          : servers.map((item, index) => {
              const active = index === serverIndex;
              return <Pressable key={`${item.name || "server"}-${index}`} accessibilityRole="button" accessibilityState={{ selected: active }} onPress={() => onSelectServer(index)} style={[playerStyles.pickerItem, active && playerStyles.pickerItemActive]}>
                <View style={[playerStyles.serverSourceIcon, active && playerStyles.serverSourceIconActive]}><Ionicons name={item.isAi ? "sparkles-outline" : "play"} size={15} color={active ? "#11150a" : C.accent} /></View>
                <View style={playerStyles.pickerItemCopy}><Text style={[playerStyles.pickerItemText, active && playerStyles.pickerItemTextActive]} numberOfLines={2}>{item.name || `Nguồn ${index + 1}`}</Text><Text style={[playerStyles.pickerItemHint, active && playerStyles.pickerItemHintActive]}>{active ? "ĐANG PHÁT" : "CHẠM ĐỂ CHỌN"}</Text></View>
                {active && <Ionicons name="checkmark-circle" size={19} color="#11150a" />}
              </Pressable>;
            })}
      </ScrollView>
      <Text style={playerStyles.pickerFootnote}>Chạm một lựa chọn để chuyển phát. Danh sách sẽ giữ mở.</Text>
    </View>
  </View>;
}

function Player({ source, title, onEnded, episodes, servers, episodeIndex, serverIndex, onSelectEpisode, onSelectServer }: { source: string; title: string; onEnded?: () => void; episodes: Episode[]; servers: MovieServer[]; episodeIndex: number; serverIndex: number; onSelectEpisode: (index: number) => void; onSelectServer: (index: number) => void }) {
  const [status, setStatus] = useState<"loading" | "ready" | "error">("loading");
  const [message, setMessage] = useState("");
  const [playing, setPlaying] = useState(false);
  const [muted, setMuted] = useState(false);
  const [volume, setVolume] = useState(1);
  const [locked, setLocked] = useState(false);
  const [lockVisible, setLockVisible] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  // Keep controls hidden until the source has actually started playing.
  const [controlsVisible, setControlsVisible] = useState(false);
  const [fullscreen, setFullscreen] = useState(false);
  const [videoFit, setVideoFit] = useState<VideoFit>("contain");
  const [fitMenuOpen, setFitMenuOpen] = useState(false);
  const [playbackRate, setPlaybackRate] = useState<PlaybackRate>(1);
  const [speedMenuOpen, setSpeedMenuOpen] = useState(false);
  const [pickerOpen, setPickerOpen] = useState<"episodes" | "servers" | null>(null);
  const pendingSeek = useRef<{ target: number; from: number; expiresAt: number; resume: boolean } | null>(null);
  const hideTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const lockHideTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const seekResumeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const seekRecoveryToken = useRef(0);
  const loadWatchdogRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const sourceRequestRef = useRef(0);
  const endedRef = useRef(false);
  const onEndedRef = useRef(onEnded);
  const volumeRef = useRef(volume);
  const lastAudibleVolumeRef = useRef(1);
  const gestureWidthRef = useRef(0);
  const gestureStartRef = useRef<{ x: number; y: number; time: number } | null>(null);
  const lastTapRef = useRef<{ x: number; time: number } | null>(null);
  const lockedRef = useRef(locked);
  const fullscreenRef = useRef(fullscreen);
  const toggleControlsRef = useRef<() => void>(() => undefined);
  const onInteractionRef = useRef<() => void>(() => undefined);
  const onSkipRef = useRef<(seconds: number) => void>(() => undefined);
  const controlsVisibleRef = useRef(controlsVisible);
  const retryingRef = useRef(false);
  const revealControlsRef = useRef<() => void>(() => undefined);
  const showLockRef = useRef<() => void>(() => undefined);
  const enterFullscreenRef = useRef<() => void>(() => undefined);
  onEndedRef.current = onEnded;
  volumeRef.current = volume;
  lockedRef.current = locked;
  fullscreenRef.current = fullscreen;
  controlsVisibleRef.current = controlsVisible;

  const player = useVideoPlayer({ uri: source, contentType: "hls" }, currentPlayer => {
    currentPlayer.timeUpdateEventInterval = 0.75;
    currentPlayer.bufferOptions = {
      // Keep the post-seek startup responsive. A very large preferred buffer
      // makes iOS wait noticeably before resuming after a jump.
      preferredForwardBufferDuration: 4,
      waitsToMinimizeStalling: false,
      minBufferForPlayback: 0.2,
    };
  });

  useEffect(() => {
    endedRef.current = false;
    retryingRef.current = false;
    if (loadWatchdogRef.current) clearTimeout(loadWatchdogRef.current);
    if (seekResumeTimer.current) clearTimeout(seekResumeTimer.current);
    pendingSeek.current = null;
    seekRecoveryToken.current += 1;
    const requestId = ++sourceRequestRef.current;
    setStatus("loading");
    setMessage("");
    setPlaying(false);
    setCurrentTime(0);
    setDuration(0);
    player.playbackRate = 1;
    setPlaybackRate(1);
    setSpeedMenuOpen(false);
    setControlsVisible(fullscreenRef.current);

    const statusSubscription = player.addListener("statusChange", event => {
      if (retryingRef.current && event.status !== "readyToPlay") return;
      if (event.status === "readyToPlay") {
        if (loadWatchdogRef.current) clearTimeout(loadWatchdogRef.current);
        setStatus("ready");
        setDuration(Number.isFinite(player.duration) ? player.duration : 0);
        if (!fullscreenRef.current) setControlsVisible(true);
      } else if (event.status === "error") {
        if (loadWatchdogRef.current) clearTimeout(loadWatchdogRef.current);
        setStatus("error");
        setMessage(event.error?.message || "Nguồn phim không thể phát trên thiết bị này.");
      }
    });
    const timeSubscription = player.addListener("timeUpdate", event => {
      const pending = pendingSeek.current;
      if (pending && Date.now() < pending.expiresAt) {
        if (Math.abs(event.currentTime - pending.target) > 2.5) return;
        pendingSeek.current = null;
        if (pending.resume && !player.playing && player.status === "readyToPlay") player.play();
      }
      setCurrentTime(event.currentTime);
      const nextDuration = Number.isFinite(player.duration) ? player.duration : 0;
      setDuration(nextDuration);
      if (nextDuration > 0 && event.currentTime >= nextDuration - 0.5 && !endedRef.current) {
        endedRef.current = true;
        onEndedRef.current?.();
      }
    });
    const playingSubscription = player.addListener("playingChange", event => {
      if (!retryingRef.current) setPlaying(event.isPlaying);
    });
    const mutedSubscription = player.addListener("mutedChange", event => setMuted(event.muted));
    if (player.status === "readyToPlay") {
      if (loadWatchdogRef.current) clearTimeout(loadWatchdogRef.current);
      setStatus("ready");
      setDuration(Number.isFinite(player.duration) ? player.duration : 0);
      if (!fullscreenRef.current) setControlsVisible(true);
    } else if (player.status === "error") {
      if (loadWatchdogRef.current) clearTimeout(loadWatchdogRef.current);
      setStatus("error");
      setMessage("Nguồn phim không thể phát trên thiết bị này.");
    } else {
      loadWatchdogRef.current = setTimeout(() => {
        if (sourceRequestRef.current !== requestId) return;
        sourceRequestRef.current += 1;
        setStatus("error");
        setMessage("Nguồn phát phản hồi quá lâu. Hãy thử lại hoặc chọn nguồn khác.");
      }, 18_000);
    }
    return () => {
      statusSubscription.remove();
      timeSubscription.remove();
      playingSubscription.remove();
      mutedSubscription.remove();
      if (loadWatchdogRef.current) clearTimeout(loadWatchdogRef.current);
    };
  }, [player]);

  // HLS sources are not always playable when useVideoPlayer's setup callback
  // runs. Start only after the native player reports readyToPlay.
  useEffect(() => {
    if (status !== "ready" || player.playing) return;
    const autoplayTimer = setTimeout(() => {
      if (!player.playing && player.status === "readyToPlay") player.play();
    }, 0);
    return () => clearTimeout(autoplayTimer);
  }, [player, status]);

  const clearHideTimer = useCallback(() => {
    if (hideTimer.current) clearTimeout(hideTimer.current);
    hideTimer.current = null;
  }, []);
  const clearLockHideTimer = useCallback(() => {
    if (lockHideTimer.current) clearTimeout(lockHideTimer.current);
    lockHideTimer.current = null;
  }, []);
  const showLockIndicator = useCallback(() => {
    if (!lockedRef.current || !fullscreenRef.current) return;
    setLockVisible(true);
    clearLockHideTimer();
    lockHideTimer.current = setTimeout(() => setLockVisible(false), 3_500);
  }, [clearLockHideTimer]);
  showLockRef.current = showLockIndicator;
  const resetHideTimer = useCallback(() => {
    clearHideTimer();
    // Controls must auto-hide in both inline and fullscreen playback. The
    // previous fullscreen-only guard left the inline toolbar permanently
    // visible and also prevented a newly revealed toolbar from re-arming.
    if (locked || pickerOpen || !playing || status !== "ready" || !controlsVisible) return;
    if (playing && status === "ready" && controlsVisible) {
      hideTimer.current = setTimeout(() => setControlsVisible(false), 2_800);
    }
  }, [clearHideTimer, controlsVisible, locked, pickerOpen, playing, status]);
  const revealControls = useCallback(() => {
    setControlsVisible(true);
    clearHideTimer();
    if (!locked && !pickerOpen && playing && status === "ready") {
      // Do not call resetHideTimer here: its closure still sees the previous
      // controlsVisible=false during this render, so it would return early.
      hideTimer.current = setTimeout(() => setControlsVisible(false), 2_800);
    }
  }, [clearHideTimer, locked, pickerOpen, playing, status]);
  const toggleControls = useCallback(() => {
    if (controlsVisible) {
      clearHideTimer();
      setControlsVisible(false);
    } else {
      setControlsVisible(true);
      // setState is asynchronous; explicitly arm the timer so the first tap
      // that reveals the toolbar does not leave it stuck on screen.
      if (!locked && playing && status === "ready") {
        clearHideTimer();
        hideTimer.current = setTimeout(() => setControlsVisible(false), 2_800);
      }
    }
  }, [clearHideTimer, controlsVisible, locked, playing, status]);
  toggleControlsRef.current = toggleControls;
  onInteractionRef.current = revealControls;
  revealControlsRef.current = revealControls;

  useEffect(() => {
    resetHideTimer();
    return clearHideTimer;
  }, [clearHideTimer, resetHideTimer]);

  useEffect(() => () => {
    clearHideTimer();
    clearLockHideTimer();
    if (seekResumeTimer.current) clearTimeout(seekResumeTimer.current);
    if (loadWatchdogRef.current) clearTimeout(loadWatchdogRef.current);
    void ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.PORTRAIT_UP).catch(() => undefined);
  }, [clearHideTimer, clearLockHideTimer]);

  const retry = useCallback(() => {
    const requestId = ++sourceRequestRef.current;
    retryingRef.current = true;
    if (loadWatchdogRef.current) clearTimeout(loadWatchdogRef.current);
    setStatus("loading");
    setMessage("");
    setPlaying(false);
    setControlsVisible(false);
    loadWatchdogRef.current = setTimeout(() => {
      if (sourceRequestRef.current !== requestId) return;
      sourceRequestRef.current += 1;
      retryingRef.current = false;
      setStatus("error");
      setMessage("Nguồn phát phản hồi quá lâu. Hãy thử lại hoặc chọn nguồn khác.");
    }, 18_000);
    void player.replaceAsync({ uri: source, contentType: "hls" }).then(() => {
      if (sourceRequestRef.current !== requestId) return;
      retryingRef.current = false;
      if (player.status === "readyToPlay") {
        if (loadWatchdogRef.current) clearTimeout(loadWatchdogRef.current);
        setStatus("ready");
        setDuration(Number.isFinite(player.duration) ? player.duration : 0);
      } else if (player.status === "error") {
        if (loadWatchdogRef.current) clearTimeout(loadWatchdogRef.current);
        setStatus("error");
        setMessage("Nguồn phim không thể phát trên thiết bị này.");
      }
    }).catch(error => {
      if (sourceRequestRef.current !== requestId) return;
      retryingRef.current = false;
      if (loadWatchdogRef.current) clearTimeout(loadWatchdogRef.current);
      setStatus("error");
      setMessage(error instanceof Error ? error.message : "Không thể tải lại nguồn phát.");
    });
  }, [player, source]);

  const togglePlayback = useCallback(() => {
    if (player.playing) {
      seekRecoveryToken.current += 1;
      pendingSeek.current = null;
      if (seekResumeTimer.current) clearTimeout(seekResumeTimer.current);
      player.pause();
    } else player.play();
  }, [player]);

  const recoverAfterSeek = useCallback(() => {
    if (seekResumeTimer.current) clearTimeout(seekResumeTimer.current);
    const recoveryToken = ++seekRecoveryToken.current;
    if (player.status === "readyToPlay") player.play();
    let previousTime = player.currentTime;
    let stagnantChecks = 0;
    let checksLeft = 28;
    const check = () => {
      const nextTime = player.currentTime;
      const advanced = Math.abs(nextTime - previousTime) >= 0.08;
      previousTime = nextTime;
      if (advanced) {
        seekResumeTimer.current = null;
        return;
      }
      if (player.playing) stagnantChecks += 1;
      else stagnantChecks = 0;
      // AVPlayer can remain logically playing while its HLS item is stalled.
      // A short pause/play cycle is the same recovery users were doing by hand.
      if (stagnantChecks >= 3 && player.status === "readyToPlay") {
        player.pause();
        setTimeout(() => { if (seekRecoveryToken.current === recoveryToken && player.status === "readyToPlay") player.play(); }, 55);
        stagnantChecks = 0;
      } else if (player.status === "readyToPlay") {
        player.play();
      }
      checksLeft -= 1;
      if (checksLeft <= 0) {
        seekResumeTimer.current = null;
        return;
      }
      seekResumeTimer.current = setTimeout(check, 140);
    };
    seekResumeTimer.current = setTimeout(check, 120);
  }, [player]);

  const seekTo = useCallback((requestedTime: number) => {
    if (!duration || player.status !== "readyToPlay") return;
    const target = Math.max(0, Math.min(duration, requestedTime));
    const currentPosition = pendingSeek.current?.target ?? player.currentTime;
    if (Math.abs(target - currentPosition) < 0.35) return;
    const shouldResume = playing || player.playing;
    pendingSeek.current = { target, from: currentPosition, expiresAt: Date.now() + 10_000, resume: shouldResume };
    setCurrentTime(target);
    // Use the native relative seek path. Assigning currentTime requests a
    // frame-accurate decode on iOS and is noticeably slower for HLS. seekBy is
    // intended for player controls and lets AVPlayer use the nearest efficient
    // segment, which keeps playback responsive after a jump.
    player.seekBy(target - currentPosition);
    if (shouldResume) {
      recoverAfterSeek();
    }
  }, [duration, player, playing, recoverAfterSeek]);

  const skip = useCallback((seconds: number) => {
    if (!duration || player.status !== "readyToPlay") return;
    if (seekResumeTimer.current) clearTimeout(seekResumeTimer.current);
    // Button skips must be relative to AVPlayer's real native position. Using
    // the optimistic pending target here can apply a reverse/forward jump on
    // top of a position that AVPlayer has not reached yet, leaving HLS paused.
    const nativePosition = player.currentTime;
    const target = Math.max(0, Math.min(duration, nativePosition + seconds));
    const effectiveDelta = target - nativePosition;
    if (Math.abs(effectiveDelta) < 0.05) return;
    const shouldResume = playing || player.playing;
    pendingSeek.current = { target, from: nativePosition, expiresAt: Date.now() + 10_000, resume: shouldResume };
    setCurrentTime(target);
    player.seekBy(effectiveDelta);
    if (shouldResume) {
      recoverAfterSeek();
    }
  }, [duration, player, playing, recoverAfterSeek]);
  onSkipRef.current = skip;
  const toggleMute = useCallback(() => {
    const silent = player.muted || player.volume <= 0.001;
    if (silent) {
      const restoreVolume = Math.max(0.05, Math.min(1, lastAudibleVolumeRef.current || 1));
      if (player.volume <= 0.001) {
        player.volume = restoreVolume;
        setVolume(restoreVolume);
        volumeRef.current = restoreVolume;
      }
      player.muted = false;
      setMuted(false);
      return;
    }
    if (player.volume > 0) lastAudibleVolumeRef.current = player.volume;
    player.muted = true;
    setMuted(true);
  }, [player]);
  const changeVolume = useCallback((delta: number) => {
    const next = Math.max(0, Math.min(1, Number((volumeRef.current + delta).toFixed(2))));
    setVolume(next);
    volumeRef.current = next;
    player.volume = next;
    if (next > 0) {
      lastAudibleVolumeRef.current = next;
      if (player.muted) {
        player.muted = false;
        setMuted(false);
      }
    }
  }, [player]);
  const toggleLock = useCallback(() => {
    if (lockedRef.current) {
      clearLockHideTimer();
      setLocked(false);
      setLockVisible(false);
      setControlsVisible(true);
    } else {
      setLocked(true);
      setControlsVisible(false);
      setLockVisible(true);
      clearLockHideTimer();
      lockHideTimer.current = setTimeout(() => setLockVisible(false), 3_500);
    }
  }, [clearLockHideTimer]);

  const changePlaybackRate = useCallback((rate: PlaybackRate) => {
    player.playbackRate = rate;
    setPlaybackRate(rate);
    setSpeedMenuOpen(false);
  }, [player]);

  const gestureResponder = useMemo(() => PanResponder.create({
    onStartShouldSetPanResponder: () => true,
    onMoveShouldSetPanResponder: () => true,
    onPanResponderGrant: (_event, gesture) => {
      gestureStartRef.current = { x: gesture.x0, y: gesture.y0, time: Date.now() };
    },
    onPanResponderMove: (_event, gesture) => {
      const start = gestureStartRef.current;
      if (!start || gestureWidthRef.current <= 0 || start.x < gestureWidthRef.current - 92) return;
      const deltaY = start.y - gesture.moveY;
      if (Math.abs(deltaY) >= 12) changeVolume(deltaY > 0 ? 0.02 : -0.02);
    },
    onPanResponderRelease: (_event, gesture) => {
      const start = gestureStartRef.current;
      gestureStartRef.current = null;
      if (!start) return;
      const moved = Math.abs(gesture.moveX - start.x) > 14 || Math.abs(gesture.moveY - start.y) > 14;
      if (start.x >= gestureWidthRef.current - 92 && moved) return;
      if (moved) return;
      if (!fullscreenRef.current) {
        enterFullscreenRef.current();
        return;
      }
      if (lockedRef.current) {
        showLockRef.current();
        return;
      }
      const now = Date.now();
      const previous = lastTapRef.current;
      if (previous && now - previous.time < 300 && Math.abs(previous.x - start.x) < 110) {
        lastTapRef.current = null;
        onInteractionRef.current();
        onSkipRef.current(start.x > gestureWidthRef.current / 2 ? 10 : -10);
      } else {
        lastTapRef.current = { x: start.x, time: now };
        const wasVisible = controlsVisibleRef.current;
        if (!wasVisible) revealControlsRef.current();
        setTimeout(() => {
          if (lastTapRef.current?.time === now) {
            lastTapRef.current = null;
            if (!lockedRef.current && wasVisible) toggleControlsRef.current();
          }
        }, 310);
      }
    },
    onPanResponderTerminate: () => { gestureStartRef.current = null; },
  }), [changeVolume]);

  const enterFullscreen = useCallback(async () => {
    clearHideTimer();
    setControlsVisible(true);
    try { await ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.LANDSCAPE); } catch { /* orientation lock may be unavailable on some devices */ }
    setFullscreen(true);
    setFitMenuOpen(false);
    setSpeedMenuOpen(false);
    resetHideTimer();
  }, [clearHideTimer, resetHideTimer]);
  enterFullscreenRef.current = enterFullscreen;

  const exitFullscreen = useCallback(async () => {
    clearHideTimer();
    setPickerOpen(null);
    setFullscreen(false);
    setFitMenuOpen(false);
    setSpeedMenuOpen(false);
    setControlsVisible(true);
    try { await ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.PORTRAIT_UP); } catch { /* keep the current orientation if the platform refuses */ }
    resetHideTimer();
  }, [clearHideTimer, resetHideTimer]);

  const videoView = () => <VideoView
    player={player}
    style={StyleSheet.absoluteFill}
    nativeControls={false}
    contentFit={videoFit}
    surfaceType="textureView"
    fullscreenOptions={{ enable: false }}
    allowsVideoFrameAnalysis={false}
  />;

  const renderLayer = (large: boolean) => <View style={[playerStyles.videoStage, large && playerStyles.fullscreenStage]}>
    {videoView()}
    <View
      style={StyleSheet.absoluteFill}
      onLayout={event => { gestureWidthRef.current = event.nativeEvent.layout.width; }}
      // The same tap layer is needed inline as well as fullscreen: when the
      // toolbar auto-hides, the next tap must be able to reveal it again.
      {...gestureResponder.panHandlers}
    />
    {!controlsVisible && !locked && status === "ready" && <Pressable
      accessibilityLabel="Hiện điều khiển trình phát"
      onPress={() => revealControlsRef.current()}
      style={StyleSheet.absoluteFill}
    />}
    {locked && large && !lockVisible && <Pressable
      accessibilityLabel="Hiện nút mở khóa"
      onPress={() => showLockRef.current()}
      style={StyleSheet.absoluteFill}
    />}
    {status === "loading" && <View pointerEvents="none" style={playerStyles.centerStatus}><ActivityIndicator color={C.accent} size="large" /><Text style={playerStyles.statusText}>{fullscreenRef.current ? "Đang chuyển tập / nguồn…" : "Đang tải nguồn phát…"}</Text></View>}
    {status === "error" ? <View style={playerStyles.errorLayer}>
      {large && fullscreen && <Pressable accessibilityRole="button" accessibilityLabel="Trở lại trình phát" onPress={() => { void exitFullscreen(); }} style={playerStyles.errorBackButton}><Ionicons name="arrow-back" size={18} color={C.text} /><Text style={playerStyles.errorBackText}>Trở lại</Text></Pressable>}
      <Ionicons name="cloud-offline-outline" color={C.text} size={28} />
      <Text style={playerStyles.errorTitle}>Không thể phát video</Text>
      <Text style={playerStyles.statusText} numberOfLines={2}>{message}</Text>
      <Pressable onPress={retry} style={playerStyles.retryButton}><Text style={playerStyles.retryText}>Thử lại</Text></Pressable>
    </View> : controlsVisible && !locked ? <PlayerControls
      title={title}
      playing={playing}
      muted={muted}
      volume={volume}
      locked={locked}
      currentTime={currentTime}
      duration={duration}
      fullscreen={large}
      onPlayback={togglePlayback}
      onSkip={skip}
      onMute={toggleMute}
      onVolumeChange={changeVolume}
      onLockToggle={toggleLock}
      onFullscreen={enterFullscreen}
      onCloseFullscreen={exitFullscreen}
      onSeek={seekTo}
      onInteraction={revealControls}
      videoFit={videoFit}
      fitMenuOpen={fitMenuOpen}
      onFitMenuToggle={() => setFitMenuOpen(open => !open)}
      onFitSelect={fit => { setVideoFit(fit); setFitMenuOpen(false); }}
      playbackRate={playbackRate}
      speedMenuOpen={speedMenuOpen}
      onSpeedMenuToggle={() => { setFitMenuOpen(false); setSpeedMenuOpen(open => !open); }}
      onSpeedSelect={changePlaybackRate}
      episodes={episodes}
      servers={servers}
      episodeIndex={episodeIndex}
      serverIndex={serverIndex}
      onSelectEpisode={onSelectEpisode}
      onSelectServer={onSelectServer}
      pickerOpen={pickerOpen}
      onPickerToggle={picker => { setPickerOpen(current => current === picker ? null : picker); }}
    /> : locked && large && lockVisible ? <Pressable accessibilityLabel="Mở khóa điều khiển" onPress={toggleLock} style={playerStyles.lockBadge}><Ionicons name="lock-closed" size={17} color={C.text} /></Pressable> : null}
    {large && fullscreen && pickerOpen && <EpisodePicker
      kind={pickerOpen}
      episodes={episodes}
      servers={servers}
      episodeIndex={episodeIndex}
      serverIndex={serverIndex}
      onSelectEpisode={onSelectEpisode}
      onSelectServer={onSelectServer}
      onClose={() => setPickerOpen(null)}
    />}
  </View>;

  return <View style={playerStyles.shell}>
    <StatusBar hidden={fullscreen} style="light" animated />
    {!fullscreen && renderLayer(false)}
    {fullscreen && <Modal
      visible
      transparent={false}
      animationType="fade"
      presentationStyle="fullScreen"
      supportedOrientations={["landscape", "landscape-left", "landscape-right", "portrait"]}
      statusBarTranslucent
      navigationBarTranslucent
      onRequestClose={() => { void exitFullscreen(); }}
    >
      <View style={playerStyles.fullscreenRoot}>{renderLayer(true)}</View>
    </Modal>}
    {!fullscreen && <View style={playerStyles.statusBar}>
      <View style={[playerStyles.statusDot, { backgroundColor: status === "error" ? C.danger : status === "ready" ? C.accent : "#f3c969" }]} />
      <Text style={playerStyles.statusTitle} numberOfLines={1}>{title}</Text>
      <Text style={playerStyles.statusLabel}>{status === "ready" ? "ĐANG PHÁT" : status === "error" ? "NGUỒN LỖI" : "ĐANG TẢI"}</Text>
    </View>}
  </View>;
}

const playerStyles = StyleSheet.create({
  shell: { marginHorizontal: -18, marginTop: 8, marginBottom: 20, backgroundColor: "#050609", borderBottomWidth: 1, borderBottomColor: C.line },
  videoStage: { aspectRatio: 16 / 9, backgroundColor: "#030405", position: "relative", justifyContent: "center", overflow: "hidden" },
  fullscreenRoot: { flex: 1, backgroundColor: "#000", justifyContent: "center" },
  fullscreenStage: { width: "100%", height: "100%", aspectRatio: undefined },
  centerStatus: { ...StyleSheet.absoluteFillObject, zIndex: 2, alignItems: "center", justifyContent: "center", gap: 10, backgroundColor: "rgba(0,0,0,0.42)" },
  statusText: { color: "#c5c9d1", fontSize: 11, marginTop: 4, textAlign: "center", maxWidth: "88%" },
  controls: { ...StyleSheet.absoluteFillObject, zIndex: 3, justifyContent: "space-between", paddingHorizontal: 14, paddingTop: 12, paddingBottom: 12, backgroundColor: "rgba(3,5,8,0.12)" },
  fullscreenControls: { paddingHorizontal: 28, paddingTop: 20, paddingBottom: 20, backgroundColor: "rgba(0,0,0,0.06)" },
  topControls: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 8 },
  topActions: { flexDirection: "row", alignItems: "center", gap: 7, flexShrink: 0 },
  sourceBadge: { flexDirection: "row", alignItems: "center", gap: 7, maxWidth: "70%", paddingHorizontal: 10, paddingVertical: 6, borderRadius: 9, backgroundColor: "rgba(20,25,37,0.62)", borderWidth: 1, borderColor: "rgba(225,232,255,0.18)" },
  fullscreenSourceBadge: { flex: 1, minWidth: 0, maxWidth: "100%", paddingHorizontal: 12, paddingVertical: 7, borderRadius: 11, backgroundColor: "rgba(10,13,18,0.76)" },
  liveDot: { width: 7, height: 7, borderRadius: 4, backgroundColor: C.accent },
  sourceText: { flex: 1, minWidth: 0, color: C.text, fontSize: 11, fontWeight: "700" },
  iconButton: { width: 36, height: 36, borderRadius: 11, alignItems: "center", justifyContent: "center", backgroundColor: "rgba(20,25,37,0.7)", borderWidth: 1, borderColor: "rgba(225,232,255,0.2)" },
  fullscreenSpacer: { width: 38, height: 38 },
  fitMenuWrap: { position: "relative", zIndex: 10 },
  fitButton: { minWidth: 66, height: 38, paddingHorizontal: 10, borderRadius: 13, flexDirection: "row", alignItems: "center", justifyContent: "center", gap: 5, backgroundColor: "rgba(15,18,24,0.88)", borderWidth: 1, borderColor: "rgba(255,255,255,0.14)" },
  speedButton: { minWidth: 62, height: 38, paddingHorizontal: 9, borderRadius: 13, flexDirection: "row", alignItems: "center", justifyContent: "center", gap: 5, backgroundColor: "rgba(15,18,24,0.88)", borderWidth: 1, borderColor: "rgba(255,255,255,0.14)" },
  fitButtonText: { color: C.text, fontSize: 10, fontWeight: "800" },
  fitMenu: { position: "absolute", top: 45, right: 0, minWidth: 126, padding: 5, borderRadius: 14, backgroundColor: "rgba(15,18,24,0.98)", borderWidth: 1, borderColor: "rgba(255,255,255,0.16)", shadowColor: "#000", shadowOpacity: 0.35, shadowRadius: 14, elevation: 8 },
  speedMenu: { minWidth: 156 },
  fitOption: { minHeight: 36, paddingHorizontal: 10, borderRadius: 9, flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 12 },
  fitOptionActive: { backgroundColor: "rgba(210,243,107,0.12)" },
  fitOptionText: { color: "#c5c9d1", fontSize: 11, fontWeight: "700" },
  fitOptionTextActive: { color: C.accent },
  centerControls: { flexDirection: "row", alignItems: "center", justifyContent: "center", gap: 18 },
  fullscreenCenterControls: { gap: 34 },
  skipButton: { width: 46, height: 46, borderRadius: 23, alignItems: "center", justifyContent: "center", position: "relative", backgroundColor: "rgba(10,13,18,0.72)", borderWidth: 1, borderColor: "rgba(255,255,255,0.16)" },
  skipLabel: { color: C.text, fontSize: 8, fontWeight: "900", position: "absolute", top: 24 },
  playButton: { width: 52, height: 52, borderRadius: 26, backgroundColor: C.accent, alignItems: "center", justifyContent: "center", shadowColor: C.accent, shadowOpacity: 0.2, shadowRadius: 10, elevation: 4 },
  playButtonLarge: { width: 66, height: 66, borderRadius: 33, shadowOpacity: 0.25, shadowRadius: 14 },
  adjustmentControls: { position: "absolute", right: 14, bottom: 56, zIndex: 4, alignItems: "flex-end" },
  fullscreenAdjustmentControls: { right: 28, bottom: 62 },
  volumeButton: { width: 44, height: 44, borderRadius: 15, alignItems: "center", justifyContent: "center", backgroundColor: "rgba(10,13,18,0.76)", borderWidth: 1, borderColor: "rgba(255,255,255,0.12)" },
  volumePopover: { minWidth: 212, flexDirection: "row", alignItems: "center", gap: 9, marginBottom: 8, paddingHorizontal: 11, height: 48, borderRadius: 15, backgroundColor: "rgba(20,25,37,0.96)", borderWidth: 1, borderColor: "rgba(225,232,255,0.2)" },
  popoverMuteButton: { width: 34, height: 34, borderRadius: 11, alignItems: "center", justifyContent: "center", backgroundColor: "rgba(255,255,255,0.1)", borderWidth: 1, borderColor: "rgba(255,255,255,0.12)" },
  volumePercent: { color: C.text, fontSize: 10, fontWeight: "800", minWidth: 31, textAlign: "center" },
  volumeSliderTouch: { flex: 1, height: 28, justifyContent: "center" }, volumeTrack: { height: 4, borderRadius: 3, backgroundColor: "rgba(255,255,255,0.26)", position: "relative" }, volumeFill: { height: 4, borderRadius: 3, backgroundColor: C.accent }, volumeThumb: { width: 12, height: 12, borderRadius: 6, backgroundColor: C.accent, position: "absolute", top: -4, marginLeft: -6 },
  pickerLayer: { ...StyleSheet.absoluteFillObject, zIndex: 40, alignItems: "center", justifyContent: "center", paddingHorizontal: 20, paddingVertical: 14 },
  pickerBackdrop: { ...StyleSheet.absoluteFillObject, backgroundColor: "rgba(0,0,0,0.66)" },
  pickerPanel: { width: "100%", maxWidth: 980, maxHeight: "90%", flexShrink: 1, paddingHorizontal: 22, paddingTop: 13, paddingBottom: 14, borderRadius: 26, backgroundColor: "rgba(20,27,42,0.985)", borderWidth: 1, borderColor: "rgba(225,232,255,0.3)", shadowColor: "#000", shadowOpacity: 0.55, shadowRadius: 30, shadowOffset: { width: 0, height: 12 }, elevation: 22 },
  pickerGrabber: { width: 42, height: 4, borderRadius: 4, backgroundColor: "rgba(255,255,255,0.4)", alignSelf: "center", marginBottom: 13 },
  pickerHeader: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 18, marginBottom: 14 },
  pickerHeadingCopy: { flex: 1, minWidth: 0 },
  pickerKicker: { color: C.accent, fontSize: 9, fontWeight: "900", letterSpacing: 1.8, marginBottom: 4 },
  pickerTitle: { color: C.text, fontSize: 23, fontWeight: "900", letterSpacing: -0.3 },
  pickerSubtitle: { color: "#c8cede", fontSize: 11, fontWeight: "600", marginTop: 5 },
  pickerClose: { width: 42, height: 42, borderRadius: 15, alignItems: "center", justifyContent: "center", backgroundColor: "rgba(255,255,255,0.09)", borderWidth: 1, borderColor: "rgba(255,255,255,0.12)" },
  pickerScroll: { flexShrink: 1, minHeight: 62, maxHeight: 330 },
  pickerGrid: { flexDirection: "row", flexWrap: "wrap", gap: 9, paddingBottom: 3 },
  pickerItem: { flexGrow: 1, flexBasis: 150, minWidth: 118, maxWidth: 260, minHeight: 54, flexDirection: "row", alignItems: "center", gap: 10, paddingHorizontal: 13, paddingVertical: 9, borderRadius: 16, backgroundColor: "rgba(255,255,255,0.075)", borderWidth: 1, borderColor: "rgba(255,255,255,0.1)" },
  pickerItemActive: { backgroundColor: "#c5d2ff", borderColor: "#e2e8ff" },
  pickerItemIndex: { color: "#c6ccdc", fontSize: 12, fontWeight: "900", fontVariant: ["tabular-nums"], minWidth: 24 },
  pickerItemIndexActive: { color: "#1b2130" },
  pickerItemText: { flex: 1, minWidth: 0, color: "#f4f5f7", fontSize: 13, lineHeight: 18, fontWeight: "800" },
  pickerItemTextActive: { color: "#111827" },
  pickerItemCopy: { flex: 1, minWidth: 0, gap: 3 },
  pickerItemHint: { color: "#aeb7ca", fontSize: 8, fontWeight: "900", letterSpacing: 0.8 },
  pickerItemHintActive: { color: "#323b52" },
  serverSourceIcon: { width: 34, height: 34, borderRadius: 12, alignItems: "center", justifyContent: "center", backgroundColor: "rgba(197,210,255,0.12)" },
  serverSourceIconActive: { backgroundColor: "rgba(17,24,39,0.12)" },
  pickerFootnote: { color: "#9fa9bd", fontSize: 9, fontWeight: "600", marginTop: 10 },
  bottomControls: { width: "100%", flexDirection: "row", alignItems: "center", gap: 7 },
  timeText: { color: "rgba(244,245,247,0.82)", fontSize: 9, fontVariant: ["tabular-nums"], minWidth: 38, textAlign: "center" },
  fullscreenTime: { fontSize: 11, minWidth: 44 },
  progressTouch: { flex: 1, height: 28, justifyContent: "center" },
  progressTrack: { height: 3, borderRadius: 2, backgroundColor: "rgba(255,255,255,0.28)", position: "relative" },
  progressFill: { height: 3, borderRadius: 2, backgroundColor: C.accent },
  progressThumb: { width: 11, height: 11, borderRadius: 6, backgroundColor: C.accent, position: "absolute", top: -4, marginLeft: -5.5 },
  lockBadge: { position: "absolute", top: 12, right: 12, zIndex: 5, width: 54, height: 54, borderRadius: 27, alignItems: "center", justifyContent: "center", backgroundColor: "rgba(15,18,24,0.9)", borderWidth: 1, borderColor: "rgba(255,255,255,0.28)" },
  errorLayer: { ...StyleSheet.absoluteFillObject, zIndex: 4, alignItems: "center", justifyContent: "center", backgroundColor: "rgba(5,7,10,0.92)", padding: 18 },
  errorBackButton: { position: "absolute", top: 18, left: 18, zIndex: 2, minHeight: 42, flexDirection: "row", alignItems: "center", gap: 7, paddingHorizontal: 13, borderRadius: 14, backgroundColor: "rgba(255,255,255,0.1)", borderWidth: 1, borderColor: "rgba(255,255,255,0.18)" },
  errorBackText: { color: C.text, fontSize: 12, fontWeight: "800" },
  errorTitle: { color: C.text, fontSize: 15, fontWeight: "800", marginTop: 8 },
  retryButton: { marginTop: 10, borderRadius: 13, backgroundColor: C.accent, paddingHorizontal: 15, paddingVertical: 8 },
  retryText: { color: "#11150a", fontSize: 11, fontWeight: "900" },
  statusBar: { paddingHorizontal: 18, paddingVertical: 12, flexDirection: "row", alignItems: "center", gap: 9 },
  statusDot: { width: 8, height: 8, borderRadius: 4 },
  statusTitle: { color: C.text, fontSize: 11, fontWeight: "700", flex: 1 },
  statusLabel: { color: C.muted, fontSize: 9, fontWeight: "800", letterSpacing: 0.6 },
});

function getEpisodeGroups(movie: Movie): MovieServer[] {
  const serverGroups = (movie.servers || []).filter(server => (server.episodes || []).length > 0);
  if (serverGroups.length) return serverGroups;
  const fallbackEpisodes = (movie.episodes || []).flatMap((item: any) => item.server_data || item.episodes || item.serverData || [item]).filter(Boolean);
  return fallbackEpisodes.length ? [{ name: "Nguồn phim", episodes: fallbackEpisodes }] : [];
}

function getStream(episode?: Episode) {
  return episode?.streamUrl || episode?.link_m3u8 || episode?.link;
}

function formatDate(value?: string | null) {
  if (!value) return "Đang cập nhật";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "Đang cập nhật" : date.toLocaleDateString("vi-VN");
}

function displayValue(value: unknown) {
  if (Array.isArray(value)) return value.length ? value.join(", ") : "Đang cập nhật";
  if (typeof value === "number") return Number.isFinite(value) ? value.toLocaleString("vi-VN") : "Đang cập nhật";
  return typeof value === "string" && value.trim() ? value : "Đang cập nhật";
}

function MovieMetadata({ movie }: { movie: Movie }) {
  const categories = movie.categories?.map(item => item.name).filter(Boolean).join(", ");
  const countries = (movie.countries || movie.country)?.map(item => item.name).filter(Boolean).join(", ");
  const episode = movie.episodeTotal ? `${displayValue(movie.episodeCurrent)} / ${movie.episodeTotal}` : displayValue(movie.episodeCurrent);
  const rows: Array<[string, unknown]> = [
    ["Diễn viên", movie.actors], ["Đạo diễn", movie.directors], ["Thể loại", categories], ["Quốc gia", countries],
    ["Đánh giá", movie.rating ? `${movie.rating} / 10` : "Chưa có đánh giá"], ["Lượt xem", movie.views], ["Cập nhật", formatDate(movie.updatedAt)],
    ["Tập hiện tại", episode], ["Ngày tạo", formatDate(movie.createdAt)], ["TMDB", movie.tmdbId], ["IMDb", movie.imdbId],
  ];
  return <GlassContainer style={detailStyles.metadataSection}>
    <View style={detailStyles.sectionHeader}><View><Text style={detailStyles.sectionKicker}>THÔNG TIN PHIM</Text><Text style={detailStyles.sectionTitle}>Chi tiết phim</Text></View><Ionicons name="server-outline" size={18} color={C.accent} /></View>
    <View style={detailStyles.metadataGrid}>{rows.map(([label, value]) => <View key={label} style={detailStyles.metadataRow}><Text style={detailStyles.metadataLabel}>{label}</Text><Text style={detailStyles.metadataValue}>{displayValue(value)}</Text></View>)}</View>
  </GlassContainer>;
}

export default function Detail() {
  const { slug } = useLocalSearchParams<{ slug: string }>();
  const [movie, setMovie] = useState<Movie>();
  const [serverIndex, setServerIndex] = useState(0);
  const [episodeIndex, setEpisodeIndex] = useState(0);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!slug) return;
    setMovie(undefined);
    setServerIndex(0);
    setEpisodeIndex(0);
    setError("");
    api.detail(slug).then(result => setMovie(result)).catch(() => setError("Không thể tải chi tiết phim."));
  }, [slug]);

  const servers = useMemo(() => movie ? getEpisodeGroups(movie) : [], [movie]);
  const server = servers[serverIndex];
  const episodes = server?.episodes || [];
  const episode = episodes[episodeIndex];
  const stream = absoluteUrl(getStream(episode));
  const playNextEpisode = useCallback(() => {
    if (episodeIndex < episodes.length - 1) setEpisodeIndex(index => index + 1);
  }, [episodeIndex, episodes.length]);

  useEffect(() => {
    if (serverIndex >= servers.length && servers.length > 0) setServerIndex(0);
    if (episodeIndex >= episodes.length && episodes.length > 0) setEpisodeIndex(0);
  }, [episodeIndex, episodes.length, serverIndex, servers.length]);

  const selectServer = useCallback((index: number) => {
    setServerIndex(index);
    setEpisodeIndex(0);
  }, []);

  if (error) return <View style={[styles.screen, { justifyContent: "center", alignItems: "center" }]}><Text style={styles.error}>{error}</Text><Pressable onPress={() => router.back()} style={detailStyles.backButton}><Ionicons name="arrow-back" color={C.text} size={18} /><Text style={detailStyles.backText}>Quay lại</Text></Pressable></View>;
  if (!movie) return <View style={[styles.screen, { justifyContent: "center" }]}><ActivityIndicator color={C.accent} size="large" /></View>;

  const meta = [movie.quality || "HD", movie.year, movie.time, movie.lang].filter(Boolean).join("  ·  ");

  return <View style={[styles.screen, { overflow: "hidden" }]}><ScreenAtmosphere /><ScrollView style={{ flex: 1, backgroundColor: "transparent" }} contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
    {stream ? <Player source={stream} onEnded={playNextEpisode} title={`${movie.name} · ${episode?.name || "Tập phim"}`} episodes={episodes} servers={servers} episodeIndex={episodeIndex} serverIndex={serverIndex} onSelectEpisode={setEpisodeIndex} onSelectServer={selectServer} /> : <View style={detailStyles.noStream}>
      <Ionicons name="play-circle-outline" size={30} color={C.muted} />
      <Text style={detailStyles.noStreamTitle}>Chưa có nguồn phát</Text>
      <Text style={detailStyles.noStreamText}>Hãy chọn tập khác hoặc quay lại sau.</Text>
    </View>}

    <GlassContainer style={detailStyles.movieInfo}>
      <Poster movie={movie} large />
      <View style={detailStyles.movieCopy}>
        <View style={detailStyles.qualityPill}><Text style={detailStyles.qualityText}>{movie.quality || "HD"}</Text></View>
        <Text style={detailStyles.movieTitle}>{movie.name}</Text>
        {!!movie.originName && <Text style={detailStyles.originName} numberOfLines={2}>{movie.originName}</Text>}
        <Text style={detailStyles.metaText}>{meta}</Text>
        {!!movie.rating && <View style={detailStyles.ratingRow}><Ionicons name="star" size={14} color={C.accent} /><Text style={detailStyles.ratingText}>{movie.rating.toFixed(1)} / 10</Text></View>}
      </View>
    </GlassContainer>

    {servers.length > 0 && <View style={detailStyles.section}>
      <View style={detailStyles.sectionHeader}><View><Text style={detailStyles.sectionKicker}>NGUỒN PHÁT</Text><Text style={detailStyles.sectionTitle}>Chọn nguồn</Text></View><Text style={detailStyles.episodeCount}>{servers.length} nguồn</Text></View>
      <View style={detailStyles.serverGrid}>{servers.map((item, index) => <Pressable key={`${item.name || "server"}-${index}`} onPress={() => selectServer(index)} style={[detailStyles.serverButton, serverIndex === index && detailStyles.serverButtonSelected]}>
        <Ionicons name={item.isAi ? "sparkles-outline" : "play-circle-outline"} size={15} color={serverIndex === index ? "#11150a" : C.accent} />
        <Text style={[detailStyles.serverText, serverIndex === index && detailStyles.serverTextSelected]} numberOfLines={1}>{item.name || `Nguồn ${index + 1}`}</Text>
      </Pressable>)}</View>
      <View style={detailStyles.episodeHeading}><Text style={detailStyles.sectionKicker}>TIẾP TỤC THƯỞNG THỨC</Text><Text style={detailStyles.episodeCount}>{episodes.length} tập</Text></View>
      <Text style={detailStyles.selectedEpisode}>Đang chọn: <Text style={{ color: C.text, fontWeight: "700" }}>{episode?.name || `Tập ${episodeIndex + 1}`}</Text></Text>
      <View style={detailStyles.episodeGrid}>{episodes.map((item, index) => {
        const selected = episodeIndex === index;
        return <Pressable key={String(item.slug || index)} onPress={() => setEpisodeIndex(index)} style={[detailStyles.episodeButton, selected && detailStyles.episodeButtonSelected]}>
          <Text style={[detailStyles.episodeText, selected && detailStyles.episodeTextSelected]} numberOfLines={1}>{item.name || `Tập ${index + 1}`}</Text>
        </Pressable>;
      })}</View>
    </View>}

    <MovieMetadata movie={movie} />

    <View style={detailStyles.section}>
      <Text style={detailStyles.sectionKicker}>VỀ BỘ PHIM</Text>
      <Text style={detailStyles.sectionTitle}>Nội dung</Text>
      <Text style={detailStyles.description}>{movie.description || movie.content || "Thông tin phim đang được cập nhật."}</Text>
      {!!movie.categories?.length && <View style={detailStyles.tags}>{movie.categories.map(category => <View key={category.name} style={detailStyles.categoryTag}><Text style={detailStyles.categoryText}>{category.name}</Text></View>)}</View>}
    </View>
  </ScrollView></View>;
}

const detailStyles = StyleSheet.create({
  header: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", marginBottom: 9 },
  backButton: { minHeight: 36, flexDirection: "row", alignItems: "center", gap: 4, paddingHorizontal: 11, borderRadius: 13, backgroundColor: C.surface, borderWidth: 1, borderColor: C.line },
  backText: { color: C.text, fontSize: 10, fontWeight: "900", letterSpacing: 0.8 },
  headerLabel: { color: C.muted, fontSize: 9, fontWeight: "800", letterSpacing: 1.3 },
  noStream: { marginHorizontal: -18, marginTop: 8, marginBottom: 18, aspectRatio: 16 / 9, backgroundColor: C.surface, alignItems: "center", justifyContent: "center", borderBottomWidth: 1, borderColor: C.line },
  noStreamTitle: { color: C.text, fontSize: 14, fontWeight: "800", marginTop: 8 },
  noStreamText: { color: C.muted, fontSize: 11, marginTop: 5 },
  movieInfo: { flexDirection: "row", gap: 18, padding: 16, borderRadius: 24, backgroundColor: C.surface, borderWidth: 1, borderColor: "rgba(255,255,255,0.07)", shadowColor: "#000", shadowOpacity: 0.22, shadowRadius: 18, shadowOffset: { width: 0, height: 8 }, elevation: 4 },
  movieCopy: { flex: 1, justifyContent: "center", alignItems: "flex-start" },
  qualityPill: { paddingHorizontal: 8, paddingVertical: 5, borderRadius: 8, backgroundColor: "rgba(210,243,107,0.13)", borderWidth: 1, borderColor: "rgba(210,243,107,0.25)" },
  qualityText: { color: C.accent, fontSize: 9, fontWeight: "900", letterSpacing: 1.2 },
  movieTitle: { color: C.text, fontSize: 22, lineHeight: 25, fontWeight: "900", marginTop: 9 },
  originName: { color: C.muted, fontSize: 12, marginTop: 5, lineHeight: 18 },
  metaText: { color: C.muted, fontSize: 10, marginTop: 9, lineHeight: 16 },
  ratingRow: { flexDirection: "row", alignItems: "center", gap: 5, marginTop: 8 },
  ratingText: { color: C.text, fontSize: 11, fontWeight: "700" },
  section: { marginTop: 36 },
  sectionHeader: { flexDirection: "row", alignItems: "flex-end", justifyContent: "space-between" },
  sectionKicker: { color: C.accent, fontSize: 9, fontWeight: "900", letterSpacing: 1.3 },
  sectionTitle: { color: C.text, fontSize: 21, fontWeight: "900", marginTop: 4 },
  episodeCount: { color: C.muted, fontSize: 9, fontWeight: "800", letterSpacing: 0.8 },
  serverGrid: { flexDirection: "row", flexWrap: "wrap", gap: 9, marginTop: 14 },
  serverButton: { minHeight: 42, flexDirection: "row", alignItems: "center", gap: 7, paddingHorizontal: 12, borderRadius: 13, backgroundColor: C.surface2, borderWidth: 1, borderColor: C.line, maxWidth: "100%" },
  serverButtonSelected: { backgroundColor: C.accent, borderColor: C.accent },
  serverText: { color: C.text, fontSize: 11, fontWeight: "800", maxWidth: 180 },
  serverTextSelected: { color: "#11150a" },
  episodeHeading: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", marginTop: 23 },
  selectedEpisode: { color: C.muted, fontSize: 11, marginTop: 8 },
  episodeGrid: { flexDirection: "row", flexWrap: "wrap", gap: 9, marginTop: 13 },
  episodeButton: { minWidth: 66, maxWidth: "48%", minHeight: 43, paddingHorizontal: 13, borderRadius: 14, backgroundColor: C.surface2, borderWidth: 1, borderColor: C.line, alignItems: "center", justifyContent: "center" },
  episodeButtonSelected: { backgroundColor: C.accent, borderColor: C.accent },
  episodeText: { color: C.text, fontSize: 11, fontWeight: "700" },
  episodeTextSelected: { color: "#11150a", fontWeight: "900" },
  metadataSection: { marginTop: 36, padding: 18, borderRadius: 22, borderWidth: 1, borderColor: "rgba(255,255,255,0.08)", backgroundColor: C.surface, shadowColor: "#000", shadowOpacity: 0.18, shadowRadius: 16, shadowOffset: { width: 0, height: 8 }, elevation: 3 },
  metadataGrid: { marginTop: 14, gap: 11 },
  metadataRow: { paddingBottom: 10, borderBottomWidth: 1, borderBottomColor: "rgba(39,44,53,0.72)" },
  metadataLabel: { color: C.muted, fontSize: 10, fontWeight: "800", marginBottom: 4 },
  metadataValue: { color: C.text, fontSize: 12, lineHeight: 18 },
  description: { color: C.muted, fontSize: 14, lineHeight: 23, marginTop: 12 },
  tags: { flexDirection: "row", flexWrap: "wrap", gap: 7, marginTop: 14, marginBottom: 8 },
  categoryTag: { borderRadius: 10, borderWidth: 1, borderColor: C.line, backgroundColor: C.surface, paddingHorizontal: 10, paddingVertical: 6 },
  categoryText: { color: C.muted, fontSize: 10, fontWeight: "700" },
});
