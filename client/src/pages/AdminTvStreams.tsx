import { useEffect, useRef, useState } from "react";
import { Link } from "wouter";
import { MonitorPlay, RefreshCw, Save, Search, Trash2, Tv, X } from "lucide-react";
import { AuthDialog } from "@/components/AuthDialog";
import { PageShell, SectionHeading } from "@/components/CinemaChrome";
import { TVStreamPreview } from "@/components/TVStreamPreview";
import { AdminTvVideos } from "@/components/AdminTvVideos";
import { useAuth } from "@/_core/hooks/useAuth";
import { trpc } from "@/lib/trpc";

type FormState = { id?: number; name: string; streamUrl: string; audioUrl: string; logoUrl: string; posterUrl: string; description: string; sortOrder: string; isActive: boolean };
type HealthFilter = "all" | "online" | "offline" | "unknown";
const emptyForm: FormState = { name: "", streamUrl: "", audioUrl: "", logoUrl: "", posterUrl: "", description: "", sortOrder: "0", isActive: true };

export default function AdminTvStreams() {
  const { user, loading } = useAuth();
  const [authOpen, setAuthOpen] = useState(false);
  const [form, setForm] = useState<FormState>(emptyForm);
  const [message, setMessage] = useState<string | null>(null);
  const [previewStream, setPreviewStream] = useState<{ id: number; name: string; streamUrl: string; audioUrl?: string | null; posterUrl?: string | null } | null>(null);
  const [healthFilter, setHealthFilter] = useState<HealthFilter>("all");
  const [searchQuery, setSearchQuery] = useState("");
  const formRef = useRef<HTMLFormElement>(null);
  const query = trpc.tv.adminList.useQuery(undefined, { enabled: user?.role === "admin", retry: false, refetchInterval: 5_000, refetchIntervalInBackground: true, refetchOnWindowFocus: true });
  const utils = trpc.useUtils();
  const create = trpc.tv.create.useMutation({ onSuccess: async () => { setForm(emptyForm); setMessage("Đã thêm kênh và kiểm tra stream."); await utils.tv.adminList.invalidate(); } });
  const update = trpc.tv.update.useMutation({ onSuccess: async () => { setForm(emptyForm); setMessage("Đã cập nhật, kiểm tra lại stream và gửi realtime."); await utils.tv.adminList.invalidate(); } });
  const remove = trpc.tv.remove.useMutation({ onSuccess: async () => { setMessage("Đã xóa kênh và gửi cập nhật realtime."); await utils.tv.adminList.invalidate(); } });
  const uploadPoster = trpc.tv.uploadPoster.useMutation({ onSuccess: (url) => { setField("posterUrl", new URL(url, window.location.origin).toString()); setMessage("Đã tải poster lên máy chủ và tự điền URL public."); } });

  useEffect(() => { if (user && user.role !== "admin") setMessage("Tài khoản này chưa có quyền admin."); }, [user]);
  if (loading) return <PageShell><main className="content-wrap inner-page"><p>Đang kiểm tra quyền truy cập…</p></main></PageShell>;
  if (!user) return <PageShell><main className="content-wrap inner-page"><div className="empty-state"><Tv size={30} /><h3>Cần đăng nhập admin</h3><p>Đăng nhập tài khoản có role admin để quản lý kênh truyền hình.</p><button className="button button-primary" onClick={() => setAuthOpen(true)}>Đăng nhập</button></div><AuthDialog open={authOpen} onClose={() => setAuthOpen(false)} /></main></PageShell>;
  if (user.role !== "admin") return <PageShell><main className="content-wrap inner-page"><div className="empty-state"><Tv size={30} /><h3>Không có quyền truy cập</h3><p>Hãy dùng tài khoản quản trị viên của Cinemora.</p></div></main></PageShell>;

  const streams = query.data || [];
  const normalizedSearch = searchQuery.trim().toLocaleLowerCase("vi-VN");
  const visibleStreams = streams.filter(stream => {
    const matchesHealth = healthFilter === "all" || (stream.healthStatus || "unknown") === healthFilter;
    if (!normalizedSearch) return matchesHealth;
    const haystack = [stream.name, stream.streamUrl, stream.audioUrl || "", stream.description || ""].join(" ").toLocaleLowerCase("vi-VN");
    return matchesHealth && haystack.includes(normalizedSearch);
  });
  const counts = { all: streams.length, online: streams.filter(stream => stream.healthStatus === "online").length, offline: streams.filter(stream => stream.healthStatus === "offline").length, unknown: streams.filter(stream => !stream.healthStatus || stream.healthStatus === "unknown").length };
  const busy = create.isPending || update.isPending || uploadPoster.isPending;
  const error = create.error?.message || update.error?.message || uploadPoster.error?.message || remove.error?.message;
  function setField<K extends keyof FormState>(key: K, value: FormState[K]) { setForm(current => ({ ...current, [key]: value })); }
  function choosePoster(file: File | undefined) {
    if (!file) return;
    if (!["image/jpeg", "image/png", "image/webp"].includes(file.type)) { setMessage("Poster chỉ hỗ trợ JPG, PNG hoặc WebP."); return; }
    if (file.size > 8 * 1024 * 1024) { setMessage("Poster phải nhỏ hơn 8MB."); return; }
    const reader = new FileReader();
    reader.onload = () => uploadPoster.mutate({ base64: String(reader.result), mimeType: file.type as "image/jpeg" | "image/png" | "image/webp" });
    reader.readAsDataURL(file);
  }
  function beginEdit(stream: (typeof streams)[number]) {
    setForm({ id: stream.id, name: stream.name, streamUrl: stream.streamUrl, audioUrl: stream.audioUrl || "", logoUrl: stream.logoUrl || "", posterUrl: stream.posterUrl || "", description: stream.description || "", sortOrder: String(stream.sortOrder), isActive: stream.isActive });
    requestAnimationFrame(() => formRef.current?.scrollIntoView({ behavior: "smooth", block: "start" }));
  }
  function submit(event: React.FormEvent) {
    event.preventDefault(); setMessage(null);
    const payload = { name: form.name, streamUrl: form.streamUrl, audioUrl: form.audioUrl || null, logoUrl: form.logoUrl || null, posterUrl: form.posterUrl || null, description: form.description || null, sortOrder: Number(form.sortOrder) || 0, isActive: form.isActive };
    if (form.id) update.mutate({ id: form.id, ...payload }); else create.mutate(payload);
  }
  const filterLabels: Array<[HealthFilter, string]> = [["all", "Tất cả"], ["online", "Đang hoạt động"], ["offline", "Gặp lỗi"], ["unknown", "Chưa xác minh"]];
  return <PageShell><main className="content-wrap inner-page admin-tv-page">
    <div className="page-topline"><Link href="/" className="back-link">← Trang chủ</Link><span className="result-note">Quản trị viên</span></div>
    <SectionHeading eyebrow="CINEMORA ADMIN" title="Quản lý Truyền hình" />
    <form ref={formRef} className="admin-tv-form" onSubmit={submit}>
      <div className="admin-tv-form-heading"><div><strong>{form.id ? "Chỉnh sửa kênh" : "Thêm kênh mới"}</strong><span>Hỗ trợ HLS `.m3u8` và các URL stream trực tiếp. Sau khi lưu hệ thống sẽ tự kiểm tra.</span></div>{form.id && <button type="button" className="button button-ghost" onClick={() => setForm(emptyForm)}><X size={15} /> Hủy sửa</button>}</div>
      <label>Tên kênh<input required value={form.name} onChange={e => setField("name", e.target.value)} placeholder="VTV1" /></label>
      <label>URL stream<input required type="url" value={form.streamUrl} onChange={e => setField("streamUrl", e.target.value)} placeholder="https://example.com/live/playlist.m3u8" /></label>
      <label>URL audio riêng (không bắt buộc)<input type="url" value={form.audioUrl} onChange={e => setField("audioUrl", e.target.value)} placeholder="https://example.com/live/audio.m3u8 hoặc audio.mp3" /><small>Chỉ nhập khi stream video không có audio. App sẽ phát và giữ audio chạy cùng tiến trình live.</small></label>
      <div className="admin-tv-grid"><label>Upload poster<input type="file" accept="image/jpeg,image/png,image/webp" onChange={e => choosePoster(e.target.files?.[0])} />{uploadPoster.isPending && <small>Đang tải poster lên…</small>}</label><label>Thứ tự<input type="number" min="0" value={form.sortOrder} onChange={e => setField("sortOrder", e.target.value)} /></label></div>
      <label>URL poster<input type="text" value={form.posterUrl} onChange={e => setField("posterUrl", e.target.value)} placeholder="Tự điền sau khi upload hoặc https://.../poster.jpg" /><small>Poster upload có thể dùng trực tiếp đường dẫn /uploads/tv-posters/…</small></label>
      <label>Logo nhỏ (không bắt buộc)<input type="url" value={form.logoUrl} onChange={e => setField("logoUrl", e.target.value)} placeholder="https://.../logo.png" /></label>
      <label>Mô tả<textarea rows={3} value={form.description} onChange={e => setField("description", e.target.value)} placeholder="Kênh truyền hình trực tiếp" /></label>
      <label className="admin-tv-check"><input type="checkbox" checked={form.isActive} onChange={e => setField("isActive", e.target.checked)} /> Hiển thị trên app</label>
      <button className="button button-primary" disabled={busy}><Save size={15} /> {busy ? "Đang kiểm tra và lưu…" : form.id ? "Lưu thay đổi" : "Thêm kênh"}</button>
      {(message || error) && <p className={error ? "admin-tv-error" : "admin-tv-success"}>{error || message}</p>}
    </form>
    <section className="admin-tv-list">
      <div className="admin-tv-list-heading"><SectionHeading eyebrow="DANH SÁCH HIỆN TẠI" title={`${visibleStreams.length}/${streams.length} kênh`} /><div className="admin-tv-live-note"><span className="admin-tv-live-dot" /> Tự cập nhật mỗi 5 giây <button type="button" className="admin-tv-refresh" onClick={() => query.refetch()} disabled={query.isFetching} title="Cập nhật ngay"><RefreshCw size={14} className={query.isFetching ? "admin-tv-refresh-spin" : ""} /></button></div></div>
      <label className="admin-tv-search"><Search size={15} /><input value={searchQuery} onChange={event => setSearchQuery(event.target.value)} placeholder="Tìm nhanh theo tên kênh, URL hoặc mô tả…" aria-label="Tìm kiếm trong danh sách kênh" />{searchQuery && <button type="button" onClick={() => setSearchQuery("")} aria-label="Xóa tìm kiếm"><X size={15} /></button>}</label>
      <div className="admin-tv-filters" role="tablist" aria-label="Lọc trạng thái stream">{filterLabels.map(([key, label]) => <button key={key} type="button" role="tab" aria-selected={healthFilter === key} className={`admin-tv-filter ${healthFilter === key ? "is-active" : ""}`} onClick={() => setHealthFilter(key)}>{label}<b>{counts[key]}</b></button>)}</div>
      <div className="admin-tv-current-list-scroll">{query.isLoading ? <p>Đang tải…</p> : visibleStreams.length === 0 ? <div className="admin-tv-filter-empty">Không có kênh nào thuộc bộ lọc này.</div> : visibleStreams.map(stream => <article className="admin-tv-item" key={stream.id}><div><strong>{stream.name}</strong><span>{stream.streamUrl}</span>{stream.audioUrl && <span className="admin-tv-audio">Audio riêng: {stream.audioUrl}</span>}<small>{stream.isActive ? "Đang hiển thị" : "Đang ẩn"} · thứ tự {stream.sortOrder}</small><em className={`admin-tv-health admin-tv-health-${stream.healthStatus || "unknown"}`}>{stream.healthStatus === "online" ? "● Đang hoạt động" : stream.healthStatus === "offline" ? `● Gặp lỗi · ${stream.healthMessage || "kiểm tra thất bại"}` : `● Chưa xác minh · ${stream.healthMessage || "máy chủ chưa xác nhận được"}`}{stream.lastCheckedAt ? ` · ${new Date(stream.lastCheckedAt).toLocaleString("vi-VN")}` : ""}</em></div><div className="admin-tv-actions"><button type="button" className="button button-primary" onClick={() => setPreviewStream(stream)}><MonitorPlay size={14} /> Xem thử</button><button type="button" className="button button-ghost" onClick={() => beginEdit(stream)}><Save size={14} /> Sửa</button><button type="button" className="button button-danger" disabled={remove.isPending} onClick={() => { if (window.confirm(`Xóa kênh ${stream.name}?`)) remove.mutate({ id: stream.id }); }}><Trash2 size={14} /> Xóa</button></div></article>)}</div>
    </section>
    <AdminTvVideos />
    {previewStream && <TVStreamPreview name={previewStream.name} streamUrl={previewStream.streamUrl} audioUrl={previewStream.audioUrl} posterUrl={previewStream.posterUrl} onClose={() => setPreviewStream(null)} />}
  </main></PageShell>;
}
