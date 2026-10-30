import { useEffect, useMemo, useRef, useState } from "react";
import { AlertCircle, MessageCircle, Paperclip, RefreshCw, Send, ShieldCheck, X } from "lucide-react";
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
  const source = attempt ? `${url}${url.includes("?") ? "&" : "?"}retry=${attempt}` : url;
  if (failed) return <button type="button" className="admin-chat-media-fallback" onClick={() => { setFailed(false); setAttempt(value => value + 1); }}><RefreshCw size={15} /> Không tải được tệp · thử lại</button>;
  return mimeType?.startsWith("video/")
    ? <video key={source} controls preload="metadata" src={source} onError={() => setFailed(true)} />
    : <img key={source} loading="lazy" src={source} alt="Media từ cuộc trò chuyện" onError={() => setFailed(true)} />;
}

export default function AdminSpecialChat() {
  const { user, loading } = useAuth();
  const [authOpen, setAuthOpen] = useState(false);
  const [selectedUserId, setSelectedUserId] = useState<number | null>(null);
  const [draft, setDraft] = useState("");
  const [mediaStatus, setMediaStatus] = useState("");
  const [mediaError, setMediaError] = useState("");
  const [pendingAttachment, setPendingAttachment] = useState<{ attachmentId: number; userId: number; filename: string; text: string | null; clientRequestId: string } | null>(null);
  const bottomRef = useRef<HTMLDivElement>(null);
  const textRequestRef = useRef<{ text: string; id: string } | null>(null);
  const conversations = trpc.adminSpecialChat.conversations.useQuery(undefined, { enabled: user?.role === "admin", refetchInterval: 3_000, retry: false });
  const messages = trpc.adminSpecialChat.messages.useQuery({ userId: selectedUserId || 0 }, { enabled: user?.role === "admin" && selectedUserId !== null, refetchInterval: 3_000, retry: false });
  const sendMessage = trpc.adminSpecialChat.sendMessage.useMutation({ onSuccess: async () => { setDraft(""); await Promise.all([messages.refetch(), conversations.refetch()]); }, onError: error => toast.error("Không gửi được tin nhắn", { description: error.message }) });
  const uploadMedia = trpc.adminSpecialChat.uploadMedia.useMutation();
  const selected = useMemo(() => (conversations.data ?? []).find(item => item.userId === selectedUserId) ?? null, [conversations.data, selectedUserId]);
  useEffect(() => {
    if (selectedUserId === null && conversations.data?.[0]) setSelectedUserId(conversations.data[0].userId);
  }, [conversations.data, selectedUserId]);
  useEffect(() => { bottomRef.current?.scrollIntoView({ behavior: "smooth" }); }, [messages.data?.length, selectedUserId]);

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
    <SectionHeading eyebrow="CINEMORA ADMIN" title="Chat đặc quyền" action={<button className="admin-tv-refresh" onClick={() => { conversations.refetch(); messages.refetch(); }} disabled={conversations.isFetching || messages.isFetching}><RefreshCw size={15} /></button>} />
    <div className="admin-chat-layout">
      <aside className="admin-chat-conversations"><div className="admin-chat-panel-title"><strong>Cuộc hội thoại</strong><span>{conversations.data?.length ?? 0} user</span></div>{conversations.isLoading ? <p>Đang tải…</p> : (conversations.data ?? []).length === 0 ? <div className="admin-chat-empty"><MessageCircle size={24} /><span>Chưa có tin nhắn.</span></div> : (conversations.data ?? []).map(item => <button type="button" key={item.userId} className={`admin-chat-conversation${item.userId === selectedUserId ? " is-selected" : ""}`} onClick={() => setSelectedUserId(item.userId)}><span className="admin-chat-avatar">{(item.name || item.email || "?").slice(0, 1).toUpperCase()}</span><span className="admin-chat-conversation-copy"><strong>{item.name || item.email || `User #${item.userId}`}</strong><small>{item.email || `ID #${item.userId}`} {item.hasSpecialPrivileges ? "· Được cấp quyền" : "· Đã bỏ quyền"}</small><em>{item.lastMessagePreview || "[Media]"}</em></span><time>{formatDate(item.lastMessageAt)}</time></button>)}</aside>
      <section className="admin-chat-thread">
        <header className="admin-chat-thread-head"><div><strong>{selected?.name || selected?.email || (selectedUserId ? `User #${selectedUserId}` : "Chọn cuộc hội thoại")}</strong><span>{selected?.email || ""}</span></div><span className="live-sync"><span /> Live polling</span></header>
        {!selectedUserId ? <div className="admin-chat-empty admin-chat-thread-empty"><MessageCircle size={30} /><span>Chọn một cuộc hội thoại để xem tin nhắn.</span></div> : <>
          <div className="admin-chat-messages">{messages.isLoading ? <p>Đang tải tin nhắn…</p> : (messages.data ?? []).map(message => <article key={message.id} className={`admin-chat-message ${message.sender === "admin" ? "is-admin" : "is-user"}`}><div className="admin-chat-bubble"><div>{message.text && <p>{message.text}</p>}{message.mediaUrl && <AdminChatAttachment url={message.mediaUrl} mimeType={message.mediaType} />}</div><time>{message.sender === "admin" ? "Bạn · " : "User · "}{formatDate(message.createdAt)}</time></div></article>)}<div ref={bottomRef} /></div>
          {(mediaStatus || mediaError || pendingAttachment) && <div className={`admin-chat-media-state${mediaError ? " has-error" : ""}`} role={mediaError ? "alert" : "status"}>{mediaError ? <AlertCircle size={15} /> : null}<span>{mediaError || mediaStatus || `Chưa gửi được ${pendingAttachment?.filename ?? "media"}.`}</span>{pendingAttachment && <button type="button" className="admin-chat-retry" onClick={() => void retryPendingAttachment()} disabled={sendMessage.isPending}>Thử gửi lại</button>}{mediaError && <button type="button" className="admin-chat-dismiss" aria-label="Đóng thông báo" onClick={() => setMediaError("")}><X size={14} /></button>}</div>}
          <form className="admin-chat-composer" onSubmit={event => { event.preventDefault(); void sendText(); }}><label className={`admin-chat-attach${uploadMedia.isPending || sendMessage.isPending ? " is-disabled" : ""}`} title="Gửi ảnh hoặc video (ảnh tối đa 8 MB, video tối đa 32 MB)"><Paperclip size={16} /><input type="file" accept="image/jpeg,image/png,image/webp,image/gif,video/mp4,video/quicktime,video/webm" hidden disabled={uploadMedia.isPending || sendMessage.isPending} onChange={event => { const file = event.target.files?.[0]; if (file) void sendFile(file); event.currentTarget.value = ""; }} />{mediaStatus || "Ảnh/video"}</label><input value={draft} onChange={event => setDraft(event.target.value)} placeholder="Viết trả lời…" maxLength={4000} disabled={sendMessage.isPending || uploadMedia.isPending} /><button className="button button-primary" disabled={!draft.trim() || sendMessage.isPending || uploadMedia.isPending}><Send size={14} /> Gửi</button></form>
        </>}
      </section>
    </div>
  </main></PageShell>;
}
