import { useEffect, useMemo, useRef, useState } from "react";
import { MessageCircle, Paperclip, RefreshCw, Send, ShieldCheck } from "lucide-react";
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
async function readMedia(file: File) {
  const base64 = await new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result || ""));
    reader.onerror = () => reject(new Error("Không đọc được tệp media."));
    reader.readAsDataURL(file);
  });
  return { base64, filename: file.name, mimeType: file.type };
}

export default function AdminSpecialChat() {
  const { user, loading } = useAuth();
  const [authOpen, setAuthOpen] = useState(false);
  const [selectedUserId, setSelectedUserId] = useState<number | null>(null);
  const [draft, setDraft] = useState("");
  const bottomRef = useRef<HTMLDivElement>(null);
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
    if (!selectedUserId || !draft.trim() || sendMessage.isPending) return;
    await sendMessage.mutateAsync({ userId: selectedUserId, text: draft.trim() });
    setDraft("");
  }
  async function sendFile(file: File) {
    if (!selectedUserId) return;
    try {
      const input = await readMedia(file);
      const result = await uploadMedia.mutateAsync({ userId: selectedUserId, ...input });
      await sendMessage.mutateAsync({ userId: selectedUserId, attachmentId: result.attachmentId });
      toast.success("Đã gửi media.");
    } catch (error) {
      toast.error("Không gửi được media", { description: error instanceof Error ? error.message : "Vui lòng thử lại." });
    }
  }
  return <PageShell><main className="content-wrap inner-page admin-chat-page">
    <div className="page-topline"><Link href="/admin/accounts" className="back-link">← Tài khoản</Link><span className="result-note"><Link href="/admin/accounts" className="text-link">Cấp/bỏ quyền chat</Link> · polling mỗi 3 giây</span></div>
    <SectionHeading eyebrow="CINEMORA ADMIN" title="Chat đặc quyền" action={<button className="admin-tv-refresh" onClick={() => { conversations.refetch(); messages.refetch(); }} disabled={conversations.isFetching || messages.isFetching}><RefreshCw size={15} /></button>} />
    <div className="admin-chat-layout">
      <aside className="admin-chat-conversations"><div className="admin-chat-panel-title"><strong>Cuộc hội thoại</strong><span>{conversations.data?.length ?? 0} user</span></div>{conversations.isLoading ? <p>Đang tải…</p> : (conversations.data ?? []).length === 0 ? <div className="admin-chat-empty"><MessageCircle size={24} /><span>Chưa có tin nhắn.</span></div> : (conversations.data ?? []).map(item => <button type="button" key={item.userId} className={`admin-chat-conversation${item.userId === selectedUserId ? " is-selected" : ""}`} onClick={() => setSelectedUserId(item.userId)}><span className="admin-chat-avatar">{(item.name || item.email || "?").slice(0, 1).toUpperCase()}</span><span className="admin-chat-conversation-copy"><strong>{item.name || item.email || `User #${item.userId}`}</strong><small>{item.email || `ID #${item.userId}`} {item.hasSpecialPrivileges ? "· Được cấp quyền" : "· Đã bỏ quyền"}</small><em>{item.lastMessagePreview || "[Media]"}</em></span><time>{formatDate(item.lastMessageAt)}</time></button>)}</aside>
      <section className="admin-chat-thread"><header className="admin-chat-thread-head"><div><strong>{selected?.name || selected?.email || (selectedUserId ? `User #${selectedUserId}` : "Chọn cuộc hội thoại")}</strong><span>{selected?.email || ""}</span></div><span className="live-sync"><span /> Live polling</span></header>{!selectedUserId ? <div className="admin-chat-empty admin-chat-thread-empty"><MessageCircle size={30} /><span>Chọn một cuộc hội thoại để xem tin nhắn.</span></div> : <><div className="admin-chat-messages">{messages.isLoading ? <p>Đang tải tin nhắn…</p> : (messages.data ?? []).map(message => <article key={message.id} className={`admin-chat-message ${message.sender === "admin" ? "is-admin" : "is-user"}`}><div className="admin-chat-bubble"><div>{message.text && <p>{message.text}</p>}{message.mediaUrl && (message.mediaType?.startsWith("video/") ? <video controls preload="metadata" src={message.mediaUrl} /> : <img loading="lazy" src={message.mediaUrl} alt="Media từ cuộc trò chuyện" />)}</div><time>{message.sender === "admin" ? "Bạn · " : "User · "}{formatDate(message.createdAt)}</time></div></article>)}<div ref={bottomRef} /></div><form className="admin-chat-composer" onSubmit={event => { event.preventDefault(); void sendText(); }}><label className="admin-chat-attach" title="Gửi ảnh hoặc video"><Paperclip size={16} /><input type="file" accept="image/jpeg,image/png,image/webp,image/gif,video/mp4,video/quicktime,video/webm" hidden onChange={event => { const file = event.target.files?.[0]; if (file) void sendFile(file); event.currentTarget.value = ""; }} />{uploadMedia.isPending ? "Đang tải…" : "Ảnh/video"}</label><input value={draft} onChange={event => setDraft(event.target.value)} placeholder="Viết trả lời…" maxLength={4000} /><button className="button button-primary" disabled={!draft.trim() || sendMessage.isPending}><Send size={14} /> Gửi</button></form></>}</section>
    </div>
  </main></PageShell>;
}
