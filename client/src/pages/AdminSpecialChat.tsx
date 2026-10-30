import { useEffect, useMemo, useRef, useState } from "react";
import { AlertCircle, Maximize2, MessageCircle, Paperclip, Pause, Play, RefreshCw, Send, ShieldCheck, Volume2, VolumeX, X, ZoomIn, ZoomOut } from "lucide-react";
import { Link } from "wouter";
import { PageShell, SectionHeading } from "@/components/CinemaChrome";
import { AuthDialog } from "@/components/AuthDialog";
import { useAuth } from "@/_core/hooks/useAuth";
import { trpc } from "@/lib/trpc";
import { toast } from "sonner";

function formatDate(value: string | Date | null | undefined) {
  if (!value) return "—";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "—" : date.toLocaleString("vi-VN");
}
const MEDIA_LIMITS: Record<string, number> = { "image/jpeg": 8, "image/png": 8, "image/webp": 8, "image/gif": 8, "video/mp4": 32, "video/quicktime": 32, "video/webm": 32 };
async function readMedia(file: File) {
  const base64 = await new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result || ""));
    reader.onerror = () => reject(new Error("Không đọc được tệp media."));
    reader.readAsDataURL(file);
  });
  return { base64, filename: file.name, mimeType: file.type };
}

function AdminChatAttachment({ url, mimeType }: { url: string; mimeType: string | null }) {
  const [failed, setFailed] = useState(false);
  const [attempt, setAttempt] = useState(0);
  const [viewerOpen, setViewerOpen] = useState(false);
  const [zoom, setZoom] = useState(1);
  const [previewSize, setPreviewSize] = useState<{ width: number; height: number } | null>(null);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);
  const [isMuted, setIsMuted] = useState(false);
  const videoRef = useRef<HTMLVideoElement>(null);
  const viewerRef = useRef<HTMLElement>(null);
  const isVideo = mimeType?.startsWith("video/") ?? false;
  const source = attempt ? `${url}${url.includes("?") ? "&" : "?"}retry=${attempt}` : url;
  useEffect(() => { setPreviewSize(null); }, [source]);
  useEffect(() => {
    if (!viewerOpen) return;
    const closeOnEscape = (event: KeyboardEvent) => { if (event.key === "Escape") setViewerOpen(false); };
    window.addEventListener("keydown", closeOnEscape);
    return () => window.removeEventListener("keydown", closeOnEscape);
  }, [viewerOpen]);
  function retry() { setFailed(false); setAttempt(value => value + 1); }
  function closeViewer() { videoRef.current?.pause(); setViewerOpen(false); setZoom(1); }
  function seekBy(delta: number) {
    const video = videoRef.current;
    if (!video) return;
    video.currentTime = Math.max(0, Math.min(video.duration || duration, video.currentTime + delta));
  }
  function togglePlay() {
    const video = videoRef.current;
    if (!video) return;
    if (video.paused) void video.play().catch(() => setFailed(true));
    else video.pause();
  }
  function toggleMute() {
    const video = videoRef.current;
    if (!video) return;
    video.muted = !video.muted;
    setIsMuted(video.muted);
  }
  function toggleFullscreen() {
    const viewer = viewerRef.current;
    if (!viewer) return;
    if (document.fullscreenElement === viewer) void document.exitFullscreen();
    else if (viewer.requestFullscreen) void viewer.requestFullscreen();
  }
  if (failed) return <button type="button" className="admin-chat-media-fallback" onClick={retry}><RefreshCw size={15} /> Không tải được tệp · thử lại</button>;
  return <>
    {isVideo ? <button type="button" className={`admin-chat-video-preview${previewSize ? " has-dimensions" : ""}`} style={previewSize ? { width: `${previewSize.width}px`, aspectRatio: `${previewSize.width} / ${previewSize.height}` } : undefined} onClick={() => { setViewerOpen(true); setIsPlaying(true); }} aria-label="Mở trình phát video">
      <video key={source} muted preload="metadata" playsInline src={source} onLoadedMetadata={event => { const { videoWidth, videoHeight } = event.currentTarget; if (videoWidth > 0 && videoHeight > 0) { const scale = Math.min(320 / videoWidth, 320 / videoHeight, 1); setPreviewSize({ width: videoWidth * scale, height: videoHeight * scale }); } }} onError={() => setFailed(true)} />
      <span className="admin-chat-video-play"><Play size={21} fill="currentColor" /></span><span className="admin-chat-video-caption">Mở video</span>
    </button> : <button type="button" className="admin-chat-image-preview" onClick={() => { setViewerOpen(true); setZoom(1); }} aria-label="Phóng to ảnh">
      <img key={source} loading="lazy" src={source} alt="Media từ cuộc trò chuyện" onError={() => setFailed(true)} />
    </button>}
    {viewerOpen && <div className="admin-chat-viewer-backdrop" role="presentation" onMouseDown={event => { if (event.target === event.currentTarget) closeViewer(); }}>
      <section ref={viewerRef} className="admin-chat-viewer" role="dialog" aria-modal="true" aria-label={isVideo ? "Trình phát video trong tin nhắn" : "Ảnh trong tin nhắn"}>
        <header className="admin-chat-viewer-head"><strong>{isVideo ? "Video trong tin nhắn" : "Ảnh trong tin nhắn"}</strong><button type="button" onClick={closeViewer} aria-label="Đóng"><X size={20} /></button></header>
        {isVideo ? <>
          <div className="admin-chat-video-stage"><video ref={videoRef} key={source} src={source} autoPlay loop playsInline preload="metadata"
            onLoadedMetadata={event => { setDuration(event.currentTarget.duration || 0); }}
            onTimeUpdate={event => { setCurrentTime(event.currentTarget.currentTime); setDuration(event.currentTarget.duration || 0); }}
            onPlay={() => setIsPlaying(true)} onPause={() => setIsPlaying(false)} onError={() => setFailed(true)} />
          </div>
          <div className="admin-chat-video-tools">
            <div className="admin-chat-video-seek"><span>{formatClock(currentTime)}</span><input aria-label="Thanh tiến trình video" type="range" min="0" max={Math.max(duration, 0.1)} step="0.1" value={Math.min(currentTime, duration || 0)} onChange={event => { const next = Number(event.target.value); setCurrentTime(next); if (videoRef.current) videoRef.current.currentTime = next; }} /><span>{formatClock(duration)}</span></div>
            <div className="admin-chat-video-buttons"><button type="button" onClick={() => seekBy(-10)} aria-label="Tua lùi 10 giây">−10 giây</button><button type="button" className="is-primary" onClick={togglePlay} aria-label={isPlaying ? "Tạm dừng" : "Phát"}>{isPlaying ? <Pause size={17} fill="currentColor" /> : <Play size={17} fill="currentColor" />}</button><button type="button" onClick={() => seekBy(10)} aria-label="Tua tới 10 giây">+10 giây</button><button type="button" className="is-utility" onClick={toggleMute} aria-label={isMuted ? "Bật âm thanh" : "Tắt âm thanh"} title={isMuted ? "Bật âm thanh" : "Tắt âm thanh"}>{isMuted ? <VolumeX size={16} /> : <Volume2 size={16} />}</button><button type="button" className="is-utility" onClick={toggleFullscreen} aria-label="Toàn màn hình" title="Toàn màn hình"><Maximize2 size={16} /></button></div>
          </div>
        </> : <>
          <div className="admin-chat-image-stage" onWheel={event => { event.preventDefault(); setZoom(value => Math.max(0.5, Math.min(4, value + (event.deltaY < 0 ? 0.15 : -0.15)))); }}><img key={source} src={source} alt="Ảnh cuộc trò chuyện" onError={() => setFailed(true)} style={{ transform: `scale(${zoom})` }} /></div>
          <div className="admin-chat-image-tools"><button type="button" onClick={() => setZoom(value => Math.max(0.5, value - 0.2))} aria-label="Thu nhỏ"><ZoomOut size={17} /></button><input aria-label="Mức thu phóng ảnh" type="range" min="0.5" max="4" step="0.1" value={zoom} onChange={event => setZoom(Number(event.target.value))} /><strong>{Math.round(zoom * 100)}%</strong><button type="button" onClick={() => setZoom(value => Math.min(4, value + 0.2))} aria-label="Phóng to"><ZoomIn size={17} /></button><button type="button" onClick={() => setZoom(1)}>Vừa khung</button></div>
        </>}
      </section>
    </div>}
  </>;
}

function formatClock(seconds: number) {
  if (!Number.isFinite(seconds) || seconds < 0) return "00:00";
  const total = Math.floor(seconds);
  return `${String(Math.floor(total / 60)).padStart(2, "0")}:${String(total % 60).padStart(2, "0")}`;
}

export default function AdminSpecialChat() {
  const { user, loading } = useAuth();
  const [authOpen, setAuthOpen] = useState(false);
  const [selectedUserId, setSelectedUserId] = useState<number | null>(null);
  const [draft, setDraft] = useState("");
  const [mediaStatus, setMediaStatus] = useState("");
  const [mediaError, setMediaError] = useState("");
  const [pendingAttachment, setPendingAttachment] = useState<{ attachmentId: number; userId: number; filename: string; text: string | null; clientRequestId: string } | null>(null);
  const [soundEnabled, setSoundEnabled] = useState(() => window.localStorage.getItem("cinemora-admin-chat-sound") !== "false");
  const bottomRef = useRef<HTMLDivElement>(null);
  const textRequestRef = useRef<{ text: string; id: string } | null>(null);
  const incomingMessageIdsRef = useRef<Map<number, number> | null>(null);
  const audioContextRef = useRef<AudioContext | null>(null);
  const conversations = trpc.adminSpecialChat.conversations.useQuery(undefined, { enabled: user?.role === "admin", refetchInterval: 3_000, retry: false });
  const messages = trpc.adminSpecialChat.messages.useQuery({ userId: selectedUserId || 0 }, { enabled: user?.role === "admin" && selectedUserId !== null, refetchInterval: 3_000, retry: false });
  const sendMessage = trpc.adminSpecialChat.sendMessage.useMutation({ onSuccess: async () => { setDraft(""); await Promise.all([messages.refetch(), conversations.refetch()]); }, onError: error => toast.error("Không gửi được tin nhắn", { description: error.message }) });
  const uploadMedia = trpc.adminSpecialChat.uploadMedia.useMutation();
  const markRead = trpc.adminSpecialChat.markRead.useMutation();
  const selected = useMemo(() => (conversations.data ?? []).find(item => item.userId === selectedUserId) ?? null, [conversations.data, selectedUserId]);
  useEffect(() => {
    if (selectedUserId === null && conversations.data?.[0]) setSelectedUserId(conversations.data[0].userId);
  }, [conversations.data, selectedUserId]);
  useEffect(() => { bottomRef.current?.scrollIntoView({ behavior: "smooth" }); }, [messages.data?.length, selectedUserId]);
  function ensureAudioContext() {
    if (!audioContextRef.current) {
      const AudioContextClass = window.AudioContext;
      if (AudioContextClass) audioContextRef.current = new AudioContextClass();
    }
    return audioContextRef.current;
  }
  function playNotification() {
    if (!soundEnabled) return;
    const context = ensureAudioContext();
    if (!context) return;
    const playTone = () => {
      const now = context.currentTime;
      [880, 1174].forEach((frequency, index) => {
        const start = now + index * 0.12;
        const oscillator = context.createOscillator();
        const gain = context.createGain();
        oscillator.type = "sine";
        oscillator.frequency.setValueAtTime(frequency, start);
        gain.gain.setValueAtTime(0.0001, start);
        gain.gain.exponentialRampToValueAtTime(0.11, start + 0.018);
        gain.gain.exponentialRampToValueAtTime(0.0001, start + 0.16);
        oscillator.connect(gain); gain.connect(context.destination);
        oscillator.start(start); oscillator.stop(start + 0.17);
      });
    };
    if (context.state === "running") playTone();
    else void context.resume().then(playTone).catch(() => undefined);
  }
  function toggleNotificationSound() {
    const enabled = !soundEnabled;
    setSoundEnabled(enabled);
    window.localStorage.setItem("cinemora-admin-chat-sound", String(enabled));
    if (enabled) {
      const context = ensureAudioContext();
      if (context) void context.resume().catch(() => undefined);
    }
  }
  useEffect(() => {
    if (!soundEnabled) return;
    const unlock = () => {
      const context = ensureAudioContext();
      if (context?.state === "suspended") void context.resume().catch(() => undefined);
    };
    window.addEventListener("pointerdown", unlock);
    window.addEventListener("keydown", unlock);
    return () => {
      window.removeEventListener("pointerdown", unlock);
      window.removeEventListener("keydown", unlock);
    };
  }, [soundEnabled]);
  useEffect(() => {
    if (!soundEnabled || !conversations.data) return;
    const current = new Map(conversations.data.map(item => [item.userId, item.latestUserMessageId]));
    const previous = incomingMessageIdsRef.current;
    if (previous) {
      const hasIncoming = conversations.data.some(item => item.latestUserMessageId > (previous.get(item.userId) ?? 0));
      if (hasIncoming) playNotification();
    }
    incomingMessageIdsRef.current = current;
  }, [conversations.data, soundEnabled]);
  const latestLoadedMessage = messages.data?.length ? messages.data[messages.data.length - 1] : null;
  useEffect(() => {
    if (!selectedUserId || !messages.data || messages.data.some(message => message.userId !== selectedUserId)) return;
    const seenMessageId = messages.data.length ? messages.data[messages.data.length - 1].id : 0;
    if (seenMessageId > 0) markRead.mutate({ userId: selectedUserId, seenMessageId }, { onSuccess: () => { void conversations.refetch(); } });
  }, [selectedUserId, latestLoadedMessage?.id]);

  if (loading) return <PageShell><main className="content-wrap inner-page"><p>Đang kiểm tra quyền truy cập…</p></main></PageShell>;
  if (!user) return <PageShell><main className="content-wrap inner-page"><div className="empty-state"><ShieldCheck size={30} /><h3>Cần đăng nhập admin</h3><p>Đăng nhập tài khoản quản trị viên để quản lý chat đặc quyền.</p><button className="button button-primary" onClick={() => setAuthOpen(true)}>Đăng nhập</button></div><AuthDialog open={authOpen} onClose={() => setAuthOpen(false)} /></main></PageShell>;
  if (user.role !== "admin") return <PageShell><main className="content-wrap inner-page"><div className="empty-state"><ShieldCheck size={30} /><h3>Không có quyền truy cập</h3><p>Khu vực này chỉ dành cho quản trị viên.</p></div></main></PageShell>;

  async function sendText() {
    const text = draft.trim();
    if (!selectedUserId || !text || sendMessage.isPending || uploadMedia.isPending) return;
    if (textRequestRef.current?.text !== text) textRequestRef.current = { text, id: crypto.randomUUID() };
    try {
      await sendMessage.mutateAsync({ userId: selectedUserId, text, clientRequestId: textRequestRef.current.id });
      textRequestRef.current = null;
      setDraft("");
    } catch { /* Keep draft and request ID so a retry cannot duplicate a committed message. */ }
  }
  async function sendFile(file: File) {
    if (!selectedUserId) return;
    const userId = selectedUserId;
    const text = draft.trim() || null;
    const limit = MEDIA_LIMITS[file.type];
    if (!limit) { setMediaError("Chỉ hỗ trợ ảnh JPG/PNG/WebP/GIF hoặc video MP4/MOV/WebM."); return; }
    if (!file.size) { setMediaError("Tệp media đang trống."); return; }
    if (file.size > limit * 1024 * 1024) { setMediaError(`Tệp quá lớn. ${file.type.startsWith("image/") ? "Ảnh" : "Video"} tối đa ${limit} MB.`); return; }
    setMediaError(""); setPendingAttachment(null);
    try {
      setMediaStatus("Đang đọc tệp…");
      const input = await readMedia(file);
      setMediaStatus("Đang tải media…");
      const result = await uploadMedia.mutateAsync({ userId, ...input });
      const clientRequestId = crypto.randomUUID();
      setPendingAttachment({ attachmentId: result.attachmentId, userId, filename: file.name, text, clientRequestId });
      setMediaStatus("Đang gửi tin nhắn…");
      await sendMessage.mutateAsync({ userId, attachmentId: result.attachmentId, ...(text ? { text } : {}), clientRequestId });
      textRequestRef.current = null;
      setPendingAttachment(null); setMediaStatus("");
      toast.success("Đã gửi media.");
    } catch (error) {
      const message = error instanceof Error ? error.message : "Vui lòng thử lại.";
      setMediaStatus(""); setMediaError(message);
      toast.error("Không gửi được media", { description: message });
    }
  }
  async function retryPendingAttachment() {
    if (!pendingAttachment || sendMessage.isPending) return;
    try {
      setMediaError(""); setMediaStatus("Đang gửi lại tin nhắn…");
      await sendMessage.mutateAsync({ userId: pendingAttachment.userId, attachmentId: pendingAttachment.attachmentId, ...(pendingAttachment.text ? { text: pendingAttachment.text } : {}), clientRequestId: pendingAttachment.clientRequestId });
      setPendingAttachment(null); setMediaStatus(""); toast.success("Đã gửi media.");
    } catch (error) {
      const message = error instanceof Error ? error.message : "Vui lòng thử lại.";
      setMediaStatus(""); setMediaError(message); toast.error("Không gửi được media", { description: message });
    }
  }
  return <PageShell><main className="content-wrap inner-page admin-chat-page">
    <div className="page-topline"><Link href="/admin/accounts" className="back-link">← Tài khoản</Link><span className="result-note"><Link href="/admin/accounts" className="text-link">Cấp/bỏ quyền chat</Link> · polling mỗi 3 giây</span></div>
    <SectionHeading eyebrow="CINEMORA ADMIN" title="Chat đặc quyền" action={<div className="admin-chat-header-actions"><button type="button" className={`admin-chat-sound-toggle${soundEnabled ? " is-on" : ""}`} onClick={toggleNotificationSound} aria-pressed={soundEnabled} title={soundEnabled ? "Tắt âm báo tin nhắn mới" : "Bật âm báo tin nhắn mới"}>{soundEnabled ? <Volume2 size={15} /> : <VolumeX size={15} />}<span>{soundEnabled ? "Âm báo bật" : "Bật âm báo"}</span></button><button className="admin-tv-refresh" onClick={() => { conversations.refetch(); messages.refetch(); }} disabled={conversations.isFetching || messages.isFetching}><RefreshCw size={15} /></button></div>} />
    <div className="admin-chat-layout">
      <aside className="admin-chat-conversations"><div className="admin-chat-panel-title"><strong>Cuộc hội thoại</strong><span>{conversations.data?.length ?? 0} tài khoản</span></div>{conversations.isLoading ? <p>Đang tải…</p> : (conversations.data ?? []).length === 0 ? <div className="admin-chat-empty"><MessageCircle size={24} /><span>Chưa có tin nhắn.</span></div> : (conversations.data ?? []).map(item => <button type="button" key={item.userId} className={`admin-chat-conversation${item.userId === selectedUserId ? " is-selected" : ""}${item.unreadCount > 0 || item.needsReply ? " has-attention" : ""}`} onClick={() => setSelectedUserId(item.userId)}><span className="admin-chat-avatar">{(item.name || item.email || "?").slice(0, 1).toUpperCase()}</span><span className="admin-chat-conversation-copy"><strong>{item.name || item.email || `User #${item.userId}`}</strong><small>{item.email || `ID #${item.userId}`} · {item.memberMessageCount} tin nhắn thành viên</small><em>{item.lastMessagePreview || "[Tệp đính kèm]"}</em></span><span className="admin-chat-conversation-meta"><time>{formatDate(item.lastMessageAt)}</time>{item.unreadCount > 0 && <span className="admin-chat-unread-badge" title={`${item.unreadCount} tin nhắn chưa đọc`}>{item.unreadCount > 99 ? "99+" : item.unreadCount} mới</span>}{item.needsReply && <span className="admin-chat-needs-reply"><i />Chờ phản hồi</span>}</span></button>)}</aside>
      <section className="admin-chat-thread">
        <header className="admin-chat-thread-head"><div><strong>{selected?.name || selected?.email || (selectedUserId ? `User #${selectedUserId}` : "Chọn cuộc hội thoại")}</strong><span>{selected?.email || ""}</span></div><span className="live-sync"><span /> Live polling</span></header>
        {!selectedUserId ? <div className="admin-chat-empty admin-chat-thread-empty"><MessageCircle size={30} /><span>Chọn một cuộc hội thoại để xem tin nhắn.</span></div> : <>
          <div className="admin-chat-messages">{messages.isLoading ? <p>Đang tải tin nhắn…</p> : (messages.data ?? []).map(message => <article key={message.id} className={`admin-chat-message ${message.sender === "admin" ? "is-admin" : "is-user"}`}><div className="admin-chat-bubble"><span className="admin-chat-sender">{message.sender === "admin" ? "QUẢN TRỊ VIÊN" : selected?.name || "THÀNH VIÊN"}</span><div>{message.text && <p>{message.text}</p>}{message.mediaUrl && <AdminChatAttachment url={message.mediaUrl} mimeType={message.mediaType} />}</div><time>{message.sender === "admin" ? "Bạn · " : "User · "}{formatDate(message.createdAt)}</time></div></article>)}<div ref={bottomRef} /></div>
          {(mediaStatus || mediaError || pendingAttachment) && <div className={`admin-chat-media-state${mediaError ? " has-error" : ""}`} role={mediaError ? "alert" : "status"}>{mediaError ? <AlertCircle size={15} /> : null}<span>{mediaError || mediaStatus || `Chưa gửi được ${pendingAttachment?.filename ?? "media"}.`}</span>{pendingAttachment && <button type="button" className="admin-chat-retry" onClick={() => void retryPendingAttachment()} disabled={sendMessage.isPending}>Thử gửi lại</button>}{mediaError && <button type="button" className="admin-chat-dismiss" aria-label="Đóng thông báo" onClick={() => setMediaError("")}><X size={14} /></button>}</div>}
          <form className="admin-chat-composer" onSubmit={event => { event.preventDefault(); void sendText(); }}><label className={`admin-chat-attach${uploadMedia.isPending || sendMessage.isPending ? " is-disabled" : ""}`} title="Gửi ảnh hoặc video (ảnh tối đa 8 MB, video tối đa 32 MB)"><Paperclip size={16} /><input type="file" accept="image/jpeg,image/png,image/webp,image/gif,video/mp4,video/quicktime,video/webm" hidden disabled={uploadMedia.isPending || sendMessage.isPending} onChange={event => { const file = event.target.files?.[0]; if (file) void sendFile(file); event.currentTarget.value = ""; }} />{mediaStatus || "Ảnh/video"}</label><input value={draft} onChange={event => setDraft(event.target.value)} placeholder="Viết trả lời…" maxLength={4000} disabled={sendMessage.isPending || uploadMedia.isPending} /><button className="button button-primary" disabled={!draft.trim() || sendMessage.isPending || uploadMedia.isPending}><Send size={14} /> Gửi</button></form>
        </>}
      </section>
    </div>
  </main></PageShell>;
}
