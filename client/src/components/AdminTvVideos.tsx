import { useRef, useState } from "react";
import { Film, Plus, Save, Trash2, X } from "lucide-react";
import { trpc } from "@/lib/trpc";

type Quality = { label: string; streamUrl: string; subtitleUrl: string; bilingualSubtitleUrl: string };
type Episode = { episodeNumber: number; name: string; subtitleUrl: string; bilingualSubtitleUrl: string; qualities: Quality[] };
type VideoForm = { id?: number; name: string; logoUrl: string; description: string; sortOrder: string; isActive: boolean; allowPip: boolean; episodes: Episode[] };
const blankQuality = (): Quality => ({ label: "1080p", streamUrl: "", subtitleUrl: "", bilingualSubtitleUrl: "" });
const blankEpisode = (number = 1): Episode => ({ episodeNumber: number, name: `Tập ${number}`, subtitleUrl: "", bilingualSubtitleUrl: "", qualities: [blankQuality()] });
const emptyForm: VideoForm = { name: "", logoUrl: "", description: "", sortOrder: "0", isActive: true, allowPip: true, episodes: [blankEpisode()] };
const videoFieldStyle: React.CSSProperties = { minHeight: 46, width: "100%", boxSizing: "border-box", border: "1px solid rgba(210,243,107,.25)", borderRadius: 10, background: "#151a1d", color: "#fff", padding: "11px 13px" };

type LinkFilter = "all" | "online" | "unknown" | "offline";

export function AdminTvVideos() {
  const formRef = useRef<HTMLFormElement>(null);
  const [form, setForm] = useState<VideoForm>(emptyForm);
  const [queryText, setQueryText] = useState("");
  const [linkFilter, setLinkFilter] = useState<LinkFilter>("all");
  const [message, setMessage] = useState<string | null>(null);
  const videos = trpc.tv.adminVideos.useQuery(undefined, { refetchInterval: 5000, refetchOnWindowFocus: true });
  const utils = trpc.useUtils();
  const create = trpc.tv.createVideo.useMutation({ onSuccess: async () => { setForm(emptyForm); setMessage("Đã kiểm tra tất cả link và thêm video thành công."); await utils.tv.adminVideos.invalidate(); }, onError: error => setMessage(error.message) });
  const update = trpc.tv.updateVideo.useMutation({ onSuccess: async () => { setForm(emptyForm); setMessage("Đã kiểm tra lại tất cả link và cập nhật video thành công."); await utils.tv.adminVideos.invalidate(); }, onError: error => setMessage(error.message) });
  const remove = trpc.tv.removeVideo.useMutation({ onSuccess: async () => { setMessage("Đã xóa video."); await utils.tv.adminVideos.invalidate(); } });
  const uploadLogo = trpc.tv.uploadPoster.useMutation({ onSuccess: url => { set("logoUrl", new URL(url, window.location.origin).toString()); setMessage("Đã tải ảnh logo lên máy chủ."); }, onError: error => setMessage(error.message) });
  const uploadSubtitle = trpc.tv.uploadSubtitle.useMutation({ onSuccess: () => setMessage("Đã tải file VTT lên máy chủ."), onError: error => setMessage(error.message) });
  const busy = create.isPending || update.isPending || uploadLogo.isPending || uploadSubtitle.isPending;
  const set = <K extends keyof VideoForm>(key: K, value: VideoForm[K]) => setForm(current => ({ ...current, [key]: value }));

  function uploadLogoFile(file: File | undefined) {
    if (!file) return;
    if (!["image/jpeg", "image/png", "image/webp"].includes(file.type)) { setMessage("Logo chỉ hỗ trợ JPG, PNG hoặc WebP."); return; }
    if (file.size > 8 * 1024 * 1024) { setMessage("Logo phải nhỏ hơn 8MB."); return; }
    const reader = new FileReader();
    reader.onload = () => uploadLogo.mutate({ base64: String(reader.result), mimeType: file.type as "image/jpeg" | "image/png" | "image/webp" });
    reader.readAsDataURL(file);
  }

  function uploadSubtitleFile(file: File | undefined, episodeIndex: number, qualityIndex: number | null, bilingual = false) {
    if (!file) return;
    const extension = file.name.toLowerCase().split(".").pop();
    if (extension !== "vtt" && extension !== "srt" && file.type !== "text/vtt" && file.type !== "application/x-subrip") { setMessage("Phụ đề chỉ hỗ trợ file .vtt hoặc .srt."); return; }
    if (file.size > 20 * 1024 * 1024) { setMessage("File phụ đề phải nhỏ hơn 20MB."); return; }
    const reader = new FileReader();
    reader.onload = () => uploadSubtitle.mutate({ base64: String(reader.result), mimeType: "text/vtt" }, { onSuccess: url => set("episodes", form.episodes.map((episode, index) => index === episodeIndex ? { ...episode, ...(qualityIndex === null ? { ...(bilingual ? { bilingualSubtitleUrl: new URL(url, window.location.origin).toString() } : { subtitleUrl: new URL(url, window.location.origin).toString() }) } : { qualities: episode.qualities.map((quality, qIndex) => qIndex === qualityIndex ? { ...quality, ...(bilingual ? { bilingualSubtitleUrl: new URL(url, window.location.origin).toString() } : { subtitleUrl: new URL(url, window.location.origin).toString() }) } : quality) }) } : episode)) });
    reader.readAsDataURL(file);
  }
  function submit(event: React.FormEvent) {
    event.preventDefault();
    setMessage("Đang kiểm tra tất cả link video, vui lòng chờ…");
    const payload = { name: form.name, logoUrl: form.logoUrl || null, description: form.description || null, sortOrder: Number(form.sortOrder) || 0, isActive: form.isActive, allowPip: form.allowPip, episodes: form.episodes.map(episode => ({ ...episode, episodeNumber: Number(episode.episodeNumber), name: episode.name || `Tập ${episode.episodeNumber}` })) };
    if (form.id) update.mutate({ id: form.id, ...payload }); else create.mutate(payload);
  }

  function edit(video: any) {
    setForm({ id: video.id, name: video.name, logoUrl: video.logoUrl || "", description: video.description || "", sortOrder: String(video.sortOrder), isActive: video.isActive, allowPip: video.allowPip !== false, episodes: video.episodes.map((episode: any) => ({ episodeNumber: episode.episodeNumber, name: episode.name, subtitleUrl: episode.subtitleUrl || "", bilingualSubtitleUrl: episode.bilingualSubtitleUrl || "", qualities: episode.qualities.map((quality: any) => ({ label: quality.label, streamUrl: quality.streamUrl, subtitleUrl: quality.subtitleUrl || "", bilingualSubtitleUrl: quality.bilingualSubtitleUrl || "" })) })) });
    requestAnimationFrame(() => formRef.current?.scrollIntoView({ behavior: "smooth", block: "start" }));
  }

  const normalizedQuery = queryText.trim().toLocaleLowerCase("vi-VN");
  const allVideos = videos.data || [];
  const filtered = allVideos.filter(video => {
    const searchable = [video.name, video.description || "", ...video.episodes.flatMap((episode: any) => [episode.name, String(episode.episodeNumber), ...episode.qualities.flatMap((quality: any) => [quality.label, quality.streamUrl, quality.healthMessage || ""])])].join(" ").toLocaleLowerCase("vi-VN");
    const matchesSearch = !normalizedQuery || searchable.includes(normalizedQuery);
    const matchesHealth = linkFilter === "all" || video.episodes.some((episode: any) => episode.qualities.some((quality: any) => (quality.healthStatus || "unknown") === linkFilter));
    return matchesSearch && matchesHealth;
  });
  const linkCounts = {
    all: allVideos.reduce((sum, video) => sum + video.episodes.reduce((count, episode) => count + episode.qualities.length, 0), 0),
    online: allVideos.reduce((sum, video) => sum + video.episodes.reduce((count, episode) => count + episode.qualities.filter((quality: any) => quality.healthStatus === "online").length, 0), 0),
    unknown: allVideos.reduce((sum, video) => sum + video.episodes.reduce((count, episode) => count + episode.qualities.filter((quality: any) => !quality.healthStatus || quality.healthStatus === "unknown").length, 0), 0),
    offline: allVideos.reduce((sum, video) => sum + video.episodes.reduce((count, episode) => count + episode.qualities.filter((quality: any) => quality.healthStatus === "offline").length, 0), 0),
  };
  const statusText = (quality: any) => quality.healthStatus === "online" ? "● Đang hoạt động" : quality.healthStatus === "offline" ? `● Link lỗi · ${quality.healthMessage || "kiểm tra thất bại"}` : `● Chưa xác minh · ${quality.healthMessage || "đang chờ kiểm tra"}`;

  return <section className="admin-video-section">
    <div className="admin-video-title"><div><span className="eyebrow">VIDEO TRONG TRUYỀN HÌNH</span><h2>Đăng video / video dạng tập</h2><p>Hệ thống kiểm tra link video HTTP/HTTPS; mỗi chất lượng có thể gắn URL hoặc upload file phụ đề WebVTT (.vtt).</p></div><Film size={28} /></div>
    <form ref={formRef} className="admin-video-form" onSubmit={submit}>
      <div className="admin-tv-form-heading"><div><strong>{form.id ? "Chỉnh sửa video" : "Thêm video mới"}</strong><span>Video thường dùng một tập; video bộ có thể thêm nhiều tập và nhiều chất lượng.</span></div>{form.id && <button type="button" className="button button-ghost" onClick={() => setForm(emptyForm)}><X size={15} /> Hủy sửa</button>}</div>
      <div className="admin-tv-grid"><div className="admin-video-field" style={{ display: "flex", flexDirection: "column", gap: 9 }}><span>Tên video</span><input style={videoFieldStyle} required value={form.name} onChange={event => set("name", event.target.value)} placeholder="Tên video" /></div><div className="admin-video-field" style={{ display: "flex", flexDirection: "column", gap: 9 }}><span>Upload ảnh logo</span><input style={videoFieldStyle} type="file" accept="image/jpeg,image/png,image/webp" onChange={event => uploadLogoFile(event.target.files?.[0])} />{uploadLogo.isPending && <small>Đang tải logo lên…</small>}</div></div>
      <div className="admin-video-field" style={{ display: "flex", flexDirection: "column", gap: 9 }}><span>Logo URL</span><input style={videoFieldStyle} type="url" value={form.logoUrl} onChange={event => set("logoUrl", event.target.value)} placeholder="Tự điền sau khi upload hoặc https://.../logo.png" /></div>
      <div className="admin-video-field" style={{ display: "flex", flexDirection: "column", gap: 9 }}><span>Mô tả</span><textarea style={videoFieldStyle} rows={2} value={form.description} onChange={event => set("description", event.target.value)} placeholder="Mô tả nếu có" /></div>
      <div className="admin-video-field" style={{ display: "flex", flexDirection: "column", gap: 9 }}><span>Thứ tự hiển thị</span><input style={videoFieldStyle} type="number" min="0" value={form.sortOrder} onChange={event => set("sortOrder", event.target.value)} /></div>
      <div className="admin-video-episodes"><div className="admin-video-subtitle"><strong>Các tập và chất lượng</strong><button type="button" className="button button-ghost" onClick={() => set("episodes", [...form.episodes, blankEpisode(form.episodes.length + 1)])}><Plus size={14} /> Thêm tập</button></div>
        {form.episodes.map((episode, episodeIndex) => <div className="admin-video-episode" key={episodeIndex}>
          <div className="admin-tv-grid"><div className="admin-video-field" style={{ display: "flex", flexDirection: "column", gap: 9 }}><span>Số tập</span><input style={videoFieldStyle} type="number" min="1" value={episode.episodeNumber} onChange={event => set("episodes", form.episodes.map((item, index) => index === episodeIndex ? { ...item, episodeNumber: Number(event.target.value) } : item))} /></div><div className="admin-video-field" style={{ display: "flex", flexDirection: "column", gap: 9 }}><span>Tên tập</span><input style={videoFieldStyle} value={episode.name} onChange={event => set("episodes", form.episodes.map((item, index) => index === episodeIndex ? { ...item, name: event.target.value } : item))} /></div></div>
          <div className="admin-video-subtitle-grid">
            <label><span>Phụ đề chính (.vtt/.srt)</span><input type="url" value={episode.subtitleUrl} aria-label="URL phụ đề chính của tập" placeholder="URL phụ đề chính (không bắt buộc)" onChange={event => set("episodes", form.episodes.map((item, index) => index === episodeIndex ? { ...item, subtitleUrl: event.target.value } : item))} /><input type="file" accept=".vtt,.srt,text/vtt,application/x-subrip" aria-label="Upload phụ đề chính của tập" onChange={event => uploadSubtitleFile(event.target.files?.[0], episodeIndex, null)} /></label>
            <label><span>Phụ đề song ngữ (.vtt/.srt)</span><input type="url" value={episode.bilingualSubtitleUrl} aria-label="URL phụ đề song ngữ của tập" placeholder="URL phụ đề song ngữ (không bắt buộc)" onChange={event => set("episodes", form.episodes.map((item, index) => index === episodeIndex ? { ...item, bilingualSubtitleUrl: event.target.value } : item))} /><input type="file" accept=".vtt,.srt,text/vtt,application/x-subrip" aria-label="Upload phụ đề song ngữ của tập" onChange={event => uploadSubtitleFile(event.target.files?.[0], episodeIndex, null, true)} /></label>
          </div>
          {episode.qualities.map((quality, qualityIndex) => <div className="admin-video-quality" key={qualityIndex}>
            <input value={quality.label} aria-label="Chất lượng" placeholder="1080p" onChange={event => set("episodes", form.episodes.map((item, index) => index === episodeIndex ? { ...item, qualities: item.qualities.map((q, qIndex) => qIndex === qualityIndex ? { ...q, label: event.target.value } : q) } : item))} />
            <input required type="url" value={quality.streamUrl} aria-label="Link video" placeholder="https://.../video.m3u8 hoặc .mp4" onChange={event => set("episodes", form.episodes.map((item, index) => index === episodeIndex ? { ...item, qualities: item.qualities.map((q, qIndex) => qIndex === qualityIndex ? { ...q, streamUrl: event.target.value } : q) } : item))} />
            <div className="admin-video-quality-subtitles">
              <label><span>Sub chính</span><input type="url" value={quality.subtitleUrl} aria-label="URL phụ đề VTT chính" placeholder="URL sub chính .vtt/.srt" onChange={event => set("episodes", form.episodes.map((item, index) => index === episodeIndex ? { ...item, qualities: item.qualities.map((q, qIndex) => qIndex === qualityIndex ? { ...q, subtitleUrl: event.target.value } : q) } : item))} /><input type="file" accept=".vtt,.srt,text/vtt,application/x-subrip" aria-label="Upload phụ đề VTT/SRT chính" onChange={event => uploadSubtitleFile(event.target.files?.[0], episodeIndex, qualityIndex)} /></label>
              <label><span>Sub song ngữ</span><input type="url" value={quality.bilingualSubtitleUrl} aria-label="URL subtitle song ngữ" placeholder="URL song ngữ .vtt/.srt" onChange={event => set("episodes", form.episodes.map((item, index) => index === episodeIndex ? { ...item, qualities: item.qualities.map((q, qIndex) => qIndex === qualityIndex ? { ...q, bilingualSubtitleUrl: event.target.value } : q) } : item))} /><input type="file" accept=".vtt,.srt,text/vtt,application/x-subrip" aria-label="Upload subtitle song ngữ" onChange={event => uploadSubtitleFile(event.target.files?.[0], episodeIndex, qualityIndex, true)} /></label>
            </div>
            {episode.qualities.length > 1 && <button type="button" className="icon-button" onClick={() => set("episodes", form.episodes.map((item, index) => index === episodeIndex ? { ...item, qualities: item.qualities.filter((_, qIndex) => qIndex !== qualityIndex) } : item))}><Trash2 size={15} /></button>}
          </div>)}
          <button type="button" className="button button-muted" onClick={() => set("episodes", form.episodes.map((item, index) => index === episodeIndex ? { ...item, qualities: [...item.qualities, blankQuality()] } : item))}><Plus size={13} /> Thêm chất lượng</button>
          {form.episodes.length > 1 && <button type="button" className="button button-danger" onClick={() => set("episodes", form.episodes.filter((_, index) => index !== episodeIndex))}><Trash2 size={13} /> Xóa tập</button>}
        </div>)}
      </div>
      <label className="admin-tv-check"><input type="checkbox" checked={form.isActive} onChange={event => set("isActive", event.target.checked)} /><span>Hiển thị trên app</span></label>
      <label className="admin-tv-check"><input type="checkbox" checked={form.allowPip} onChange={event => set("allowPip", event.target.checked)} /><span>Cho phép người dùng bật Picture-in-Picture (PiP) cho video này</span></label>
      <button className="button button-primary" disabled={busy}><Save size={15} /> {busy ? "Đang kiểm tra link…" : form.id ? "Lưu video" : "Kiểm tra và thêm video"}</button>
      {message && <p className={message.includes("thành công") ? "admin-tv-success" : "admin-tv-error"}>{message}</p>}
    </form>
    <div className="admin-video-list-head"><h3>DANH SÁCH VIDEO ĐÃ THÊM</h3><input value={queryText} onChange={event => setQueryText(event.target.value)} placeholder="Tìm video, tập, chất lượng hoặc link…" /></div>
    <div className="admin-video-link-filters">{(["all", "online", "unknown", "offline"] as const).map(filter => <button key={filter} type="button" className={linkFilter === filter ? "is-active" : ""} onClick={() => setLinkFilter(filter)}>{filter === "all" ? "Tất cả link" : filter === "online" ? "Đang hoạt động" : filter === "offline" ? "Link lỗi" : "Chưa xác minh"}<b>{linkCounts[filter]}</b></button>)}</div>
    <div className="admin-video-list admin-video-list-scroll">
      {videos.isLoading ? <p>Đang tải…</p> : filtered.length === 0 ? <div className="admin-tv-filter-empty">Không có video/link phù hợp bộ lọc.</div> : filtered.map(video => <article className="admin-video-item" key={video.id}>
        <div><strong>{video.name}</strong><span>{video.description || "Không có mô tả"}</span><small>{video.episodes.length} tập · {video.episodes.reduce((total, episode) => total + episode.qualities.length, 0)} link chất lượng · {video.isActive ? "Đang hiển thị" : "Đang ẩn"}</small>
          <div className="admin-video-link-details">{video.episodes.map((episode: any) => <div className="admin-video-episode-summary" key={episode.id}><b>{episode.name} (Tập {episode.episodeNumber})</b>{episode.qualities.map((quality: any) => <div className="admin-video-link-row" key={quality.id}><span>{quality.label}</span><code>{quality.streamUrl}</code><em className={`admin-video-health admin-video-health-${quality.healthStatus || "unknown"}`}>{statusText(quality)}</em></div>)}</div>)}</div>
        </div>
        <div className="admin-tv-actions"><button type="button" className="button button-primary" onClick={() => edit(video)}><Save size={14} /> Sửa</button><button type="button" className="button button-danger" disabled={remove.isPending} onClick={() => { if (window.confirm(`Xóa video ${video.name}?`)) remove.mutate({ id: video.id }); }}><Trash2 size={14} /> Xóa</button></div>
      </article>)}
    </div>
  </section>;
}
