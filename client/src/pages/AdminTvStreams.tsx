import { useEffect, useState } from "react";
import { Link } from "wouter";
import { Save, Trash2, Tv, X } from "lucide-react";
import { AuthDialog } from "@/components/AuthDialog";
import { PageShell, SectionHeading } from "@/components/CinemaChrome";
import { useAuth } from "@/_core/hooks/useAuth";
import { trpc } from "@/lib/trpc";

type FormState = { id?: number; name: string; streamUrl: string; logoUrl: string; posterUrl: string; description: string; sortOrder: string; isActive: boolean };
const emptyForm: FormState = { name: "", streamUrl: "", logoUrl: "", posterUrl: "", description: "", sortOrder: "0", isActive: true };

export default function AdminTvStreams() {
  const { user, loading } = useAuth();
  const [authOpen, setAuthOpen] = useState(false);
  const [form, setForm] = useState<FormState>(emptyForm);
  const [message, setMessage] = useState<string | null>(null);
  const query = trpc.tv.adminList.useQuery(undefined, { enabled: user?.role === "admin", retry: false, refetchInterval: 15_000, refetchOnWindowFocus: true });
  const utils = trpc.useUtils();
  const create = trpc.tv.create.useMutation({ onSuccess: async () => { setForm(emptyForm); setMessage("Đã thêm kênh và kiểm tra stream."); await utils.tv.adminList.invalidate(); } });
  const update = trpc.tv.update.useMutation({ onSuccess: async () => { setForm(emptyForm); setMessage("Đã cập nhật, kiểm tra lại stream và gửi realtime."); await utils.tv.adminList.invalidate(); } });
  const remove = trpc.tv.remove.useMutation({ onSuccess: async () => { setMessage("Đã xóa kênh và gửi cập nhật realtime."); await utils.tv.adminList.invalidate(); } });
  const uploadPoster = trpc.tv.uploadPoster.useMutation({ onSuccess: (url) => { setField("posterUrl", new URL(url, window.location.origin).toString()); setMessage("Đã tải poster lên máy chủ và tự điền URL public."); } });

  useEffect(() => { if (user && user.role !== "admin") setMessage("Tài khoản này chưa có quyền admin."); }, [user]);
  if (loading) return <PageShell><main className="content-wrap inner-page"><p>Đang kiểm tra quyền truy cập…</p></main></PageShell>;
  if (!user) return <PageShell><main className="content-wrap inner-page"><div className="empty-state"><Tv size={30} /><h3>Cần đăng nhập admin</h3><p>Đăng nhập tài khoản có role admin để quản lý kênh truyền hình.</p><button className="button button-primary" onClick={() => setAuthOpen(true)}>Đăng nhập</button></div><AuthDialog open={authOpen} onClose={() => setAuthOpen(false)} /></main></PageShell>;
  if (user.role !== "admin") return <PageShell><main className="content-wrap inner-page"><div className="empty-state"><Tv size={30} /><h3>Không có quyền truy cập</h3><p>Hãy dùng tài khoản quản trị viên của Cinemora.</p></div></main></PageShell>;

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
  function submit(event: React.FormEvent) {
    event.preventDefault(); setMessage(null);
    const payload = { name: form.name, streamUrl: form.streamUrl, logoUrl: form.logoUrl || null, posterUrl: form.posterUrl || null, description: form.description || null, sortOrder: Number(form.sortOrder) || 0, isActive: form.isActive };
    if (form.id) update.mutate({ id: form.id, ...payload }); else create.mutate(payload);
  }
  return <PageShell><main className="content-wrap inner-page admin-tv-page">
    <div className="page-topline"><Link href="/" className="back-link">← Trang chủ</Link><span className="result-note">Quản trị viên</span></div>
    <SectionHeading eyebrow="CINEMORA ADMIN" title="Quản lý Truyền hình" />
    <form className="admin-tv-form" onSubmit={submit}>
      <div className="admin-tv-form-heading"><div><strong>{form.id ? "Chỉnh sửa kênh" : "Thêm kênh mới"}</strong><span>Hỗ trợ HLS `.m3u8` và các URL stream trực tiếp. Sau khi lưu hệ thống sẽ tự kiểm tra.</span></div>{form.id && <button type="button" className="button button-ghost" onClick={() => setForm(emptyForm)}><X size={15} /> Hủy sửa</button>}</div>
      <label>Tên kênh<input required value={form.name} onChange={e => setField("name", e.target.value)} placeholder="VTV1" /></label>
      <label>URL stream<input required type="url" value={form.streamUrl} onChange={e => setField("streamUrl", e.target.value)} placeholder="https://example.com/live/playlist.m3u8" /></label>
      <div className="admin-tv-grid"><label>Upload poster<input type="file" accept="image/jpeg,image/png,image/webp" onChange={e => choosePoster(e.target.files?.[0])} />{uploadPoster.isPending && <small>Đang tải poster lên…</small>}</label><label>Thứ tự<input type="number" min="0" value={form.sortOrder} onChange={e => setField("sortOrder", e.target.value)} /></label></div>
      <label>URL poster<input type="text" value={form.posterUrl} onChange={e => setField("posterUrl", e.target.value)} placeholder="Tự điền sau khi upload hoặc https://.../poster.jpg" /><small>Poster upload có thể dùng trực tiếp đường dẫn /uploads/tv-posters/…</small></label>
      <label>Logo nhỏ (không bắt buộc)<input type="url" value={form.logoUrl} onChange={e => setField("logoUrl", e.target.value)} placeholder="https://.../logo.png" /></label>
      <label>Mô tả<textarea rows={3} value={form.description} onChange={e => setField("description", e.target.value)} placeholder="Kênh truyền hình trực tiếp" /></label>
      <label className="admin-tv-check"><input type="checkbox" checked={form.isActive} onChange={e => setField("isActive", e.target.checked)} /> Hiển thị trên app</label>
      <button className="button button-primary" disabled={busy}><Save size={15} /> {busy ? "Đang kiểm tra và lưu…" : form.id ? "Lưu thay đổi" : "Thêm kênh"}</button>
      {(message || error) && <p className={error ? "admin-tv-error" : "admin-tv-success"}>{error || message}</p>}
    </form>
    <section className="admin-tv-list"><SectionHeading eyebrow="DANH SÁCH HIỆN TẠI" title={`${query.data?.length || 0} kênh`} />{query.isLoading ? <p>Đang tải…</p> : (query.data || []).map(stream => <article className="admin-tv-item" key={stream.id}><div><strong>{stream.name}</strong><span>{stream.streamUrl}</span><small>{stream.isActive ? "Đang hiển thị" : "Đang ẩn"} · thứ tự {stream.sortOrder}</small><em className={`admin-tv-health admin-tv-health-${stream.healthStatus || "unknown"}`}>{stream.healthStatus === "online" ? "● Đang hoạt động" : stream.healthStatus === "offline" ? `● Không hoạt động · ${stream.healthMessage || "kiểm tra thất bại"}` : "● Chưa kiểm tra"}{stream.lastCheckedAt ? ` · ${new Date(stream.lastCheckedAt).toLocaleString("vi-VN")}` : ""}</em></div><div className="admin-tv-actions"><button className="button button-ghost" onClick={() => setForm({ id: stream.id, name: stream.name, streamUrl: stream.streamUrl, logoUrl: stream.logoUrl || "", posterUrl: stream.posterUrl || "", description: stream.description || "", sortOrder: String(stream.sortOrder), isActive: stream.isActive })}><Save size={14} /> Sửa</button><button className="button button-danger" disabled={remove.isPending} onClick={() => { if (window.confirm(`Xóa kênh ${stream.name}?`)) remove.mutate({ id: stream.id }); }}><Trash2 size={14} /> Xóa</button></div></article>)}</section>
  </main></PageShell>;
}
