import { useEffect, useId, useState } from "react";
import { ArrowDown, ArrowUp, Database, ExternalLink, FileText, Link2, Pencil, Plus, RefreshCw, Save, ShieldCheck, Trash2, Upload, X } from "lucide-react";
import { Link as RouterLink } from "wouter";
import { AuthDialog } from "@/components/AuthDialog";
import { PageShell, SectionHeading } from "@/components/CinemaChrome";
import { useAuth } from "@/_core/hooks/useAuth";
import { trpc } from "@/lib/trpc";
import BulkEpisodesInput from "@/components/BulkEpisodesInput";

type MovieSourceEpisode = {
  id: number;
  sourceId: number;
  name: string;
  streamUrl: string;
  subtitleUrl: string | null;
  subtitleLabel?: string | null;
  subtitleTracks?: Array<{ language: string; subtitleUrl: string }>;
  hasUploadedSubtitle: boolean;
  sortOrder: number;
  qualities?: Array<{ label: string; streamUrl: string; subtitleUrl: string | null; subtitleTracks?: Array<{ language: string; subtitleUrl: string }> }>;
};

type MovieSource = {
  id: number;
  movieSlug: string;
  name: string;
  sortOrder: number;
  episodes: MovieSourceEpisode[];
};

type EpisodePayload = {
  name: string;
  streamUrl: string;
  subtitleUrl?: string | null;
  subtitleLabel?: string | null;
  subtitleVtt?: string | null;
  subtitleTracks?: Array<{ language: string; subtitleUrl?: string | null; subtitleVtt?: string | null }>;
  qualities?: Array<{ label: string; streamUrl: string; subtitleUrl?: string | null; subtitleLabel?: string | null; subtitleVtt?: string | null; subtitleTracks?: Array<{ language: string; subtitleUrl?: string | null; subtitleVtt?: string | null }> }>;
};

type SubtitleTrackDraft = { language: string; subtitleUrl: string; subtitleVtt: string };

type EpisodeDraft = {
  name: string;
  streamUrl: string;
  subtitleUrl: string;
  subtitleLabel: string;
  subtitleMode: "url" | "file";
  subtitleTracks: SubtitleTrackDraft[];
};

type EpisodeFormProps = {
  initial?: EpisodeDraft & { existingUploaded?: boolean };
  onSubmit: (payload: EpisodePayload) => Promise<void>;
  /** Thêm một lượt nhiều tập (ô dán danh sách) — chỉ dùng cho form "Thêm tập". */
  onSubmitMany?: (items: EpisodePayload[]) => Promise<{ added: number; skipped: number }>;
  /** Tập đang có của nguồn, dùng để phát hiện trùng khi admin dán danh sách. */
  existingEpisodes?: Array<{ name: string; streamUrl: string }>;
  onCancel?: () => void;
  submitLabel: string;
};

/** Cuộn tới đúng tập vừa mở form sửa để không bị khuất trong danh sách có thanh cuộn. */
function scrollEpisodeIntoView(id: number) {
  window.requestAnimationFrame(() => {
    const node = document.querySelector(`[data-episode-id="${id}"]`);
    node?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  });
}

function readFileAsBase64(file: File) {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = typeof reader.result === "string" ? reader.result : "";
      resolve(result.includes(",") ? result.slice(result.indexOf(",") + 1) : result);
    };
    reader.onerror = () => reject(new Error("Không thể đọc tệp phụ đề."));
    reader.readAsDataURL(file);
  });
}

function subtitleURLObject(value: string) {
  try { return new URL(value, window.location.origin); } catch { return null; }
}

function isInternalSubtitleRoute(value: string | null | undefined) {
  if (!value) return false;
  const url = subtitleURLObject(value);
  return Boolean(url && url.origin === window.location.origin && (url.pathname.startsWith("/api/movies/subtitle/") || url.pathname.startsWith("/api/public-storage/public-assets/movie-subs/") || url.pathname.startsWith("/uploads/movie-subs/")));
}

function displaySubtitleURL(value: string | null | undefined) {
  if (!value) return "";
  return isInternalSubtitleRoute(value) ? new URL(value, window.location.origin).toString() : value;
}

function storedSubtitleURL(value: string | null | undefined) {
  if (!value) return value || null;
  const url = subtitleURLObject(value);
  return url && url.origin === window.location.origin && (url.pathname.startsWith("/api/movies/subtitle/") || url.pathname.startsWith("/api/public-storage/public-assets/movie-subs/") || url.pathname.startsWith("/uploads/movie-subs/")) ? `${url.pathname}${url.search}` : value;
}

function EpisodeForm({ initial, onSubmit, onSubmitMany, existingEpisodes, onCancel, submitLabel }: EpisodeFormProps) {
  const subtitleModeName = useId();
  const initialSubtitleRoute = isInternalSubtitleRoute(initial?.subtitleUrl) ? displaySubtitleURL(initial?.subtitleUrl) : "";
  const [draft, setDraft] = useState<EpisodeDraft>(initial ? { ...initial, subtitleUrl: initialSubtitleRoute || displaySubtitleURL(initial.subtitleUrl), subtitleLabel: initial.subtitleLabel || "", subtitleTracks: (initial.subtitleTracks || []).map(track => ({ ...track, subtitleUrl: displaySubtitleURL(track.subtitleUrl), subtitleVtt: "" })) } : { name: "", streamUrl: "", subtitleUrl: "", subtitleLabel: "", subtitleMode: "url", subtitleTracks: [] });
  const [preserveExistingSubtitle, setPreserveExistingSubtitle] = useState(Boolean(initial?.existingUploaded && isInternalSubtitleRoute(initial.subtitleUrl)));
  const [file, setFile] = useState<File | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const uploadSubtitle = trpc.movieSources.uploadSubtitle.useMutation();
  // Chế độ dán danh sách chỉ có khi thêm tập mới; sửa tập vẫn dùng form một tập.
  const bulkAvailable = submitLabel === "Thêm tập" && Boolean(onSubmitMany);
  const [mode, setMode] = useState<"single" | "bulk">("single");

  async function uploadTrack(index: number, selectedFile: File | undefined) {
    if (!selectedFile) return;
    try {
      const base64 = await readFileAsBase64(selectedFile);
      const uploaded = await uploadSubtitle.mutateAsync({ base64, filename: selectedFile.name });
      setDraft(current => ({ ...current, subtitleTracks: current.subtitleTracks.map((track, trackIndex) => trackIndex === index ? { ...track, subtitleUrl: displaySubtitleURL(uploaded.url), subtitleVtt: uploaded.content } : track) }));
    } catch (uploadError) {
      setError(uploadError instanceof Error ? uploadError.message : "Không thể tải phụ đề lên.");
    }
  }

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    const name = draft.name.trim();
    const streamUrl = draft.streamUrl.trim();
    if (!name) {
      setError("Vui lòng nhập tên tập.");
      return;
    }
    try {
      new URL(streamUrl);
    } catch {
      setError("Link M3U8 phải là một URL hợp lệ.");
      return;
    }
    const subtitleUrl = draft.subtitleUrl.trim();
    if (draft.subtitleMode === "url" && subtitleUrl) {
      try {
        new URL(subtitleUrl);
      } catch {
        setError("Link phụ đề phải là một URL hợp lệ.");
        return;
      }
    }

    setSaving(true);
    try {
      if (draft.subtitleMode === "file" && file) {
        const base64 = await readFileAsBase64(file);
        const uploaded = await uploadSubtitle.mutateAsync({ base64, filename: file.name });
        await onSubmit({ name, streamUrl, subtitleUrl: storedSubtitleURL(uploaded.url), subtitleLabel: draft.subtitleLabel.trim() || null, subtitleVtt: uploaded.content, subtitleTracks: draft.subtitleTracks.map(track => ({ ...track, subtitleUrl: storedSubtitleURL(track.subtitleUrl) })), qualities: [] });
      } else if (draft.subtitleMode === "file" && initial?.existingUploaded) {
        // Không chọn tệp mới: giữ nguyên nội dung phụ đề đã tải lên khi sửa tập.
        await onSubmit({ name, streamUrl, subtitleUrl: preserveExistingSubtitle && initialSubtitleRoute === subtitleUrl ? undefined : storedSubtitleURL(subtitleUrl), subtitleLabel: draft.subtitleLabel.trim() || null, subtitleTracks: draft.subtitleTracks.map(track => ({ ...track, subtitleUrl: storedSubtitleURL(track.subtitleUrl) })), qualities: [] });
      } else {
        await onSubmit({ name, streamUrl, subtitleUrl: draft.subtitleMode === "url" && subtitleUrl ? storedSubtitleURL(subtitleUrl) : null, subtitleLabel: draft.subtitleLabel.trim() || null, subtitleVtt: null, subtitleTracks: draft.subtitleTracks.map(track => ({ ...track, subtitleUrl: storedSubtitleURL(track.subtitleUrl) })), qualities: [] });
      }
    } catch (submitError) {
      setError(submitError instanceof Error ? submitError.message : "Không thể lưu tập phim.");
    } finally {
      setSaving(false);
    }
  }

  if (bulkAvailable && mode === "bulk" && onSubmitMany) {
    return <BulkEpisodesInput
      existingEpisodes={existingEpisodes || []}
      pending={saving}
      onClose={() => { setMode("single"); setError(null); }}
      onSubmit={async items => {
        const result = await onSubmitMany(items.map(item => ({ ...item, subtitleVtt: null })));
        return result;
      }}
    />;
  }

  return <form className="admin-source-episode-form" onSubmit={submit}>
    <div className="admin-source-form-heading"><strong>{submitLabel === "Thêm tập" ? "Thêm tập mới" : "Chỉnh sửa tập"}</strong>{bulkAvailable ? <button type="button" className="admin-source-mode-switch" onClick={() => { setMode("bulk"); setError(null); }}>Dán danh sách nhiều tập</button> : onCancel && <button type="button" className="admin-tv-refresh" onClick={onCancel} aria-label="Huỷ sửa"><X size={14} /></button>}</div>
    <div className="admin-source-form-grid">
      <label>Tên tập<input value={draft.name} onChange={event => setDraft({ ...draft, name: event.target.value })} placeholder="Ví dụ: Tập 01" required /></label>
      <label>Link M3U8<input type="url" value={draft.streamUrl} onChange={event => setDraft({ ...draft, streamUrl: event.target.value })} placeholder="https://…/playlist.m3u8" required /></label>
    </div>
    <fieldset className="admin-source-subtitle-fieldset"><legend>Phụ đề</legend>
      <div className="admin-source-subtitle-choice"><label><input type="radio" name={subtitleModeName} checked={draft.subtitleMode === "url"} onChange={() => { setPreserveExistingSubtitle(false); setDraft({ ...draft, subtitleMode: "url" }); }} /> Dán link phụ đề .vtt</label><label><input type="radio" name={subtitleModeName} checked={draft.subtitleMode === "file"} onChange={() => setDraft({ ...draft, subtitleMode: "file" })} /> Upload tệp</label></div>
      {draft.subtitleMode === "url" ? <input type={isInternalSubtitleRoute(draft.subtitleUrl) ? "text" : "url"} value={draft.subtitleUrl} onChange={event => { setPreserveExistingSubtitle(false); setDraft({ ...draft, subtitleUrl: event.target.value }); }} placeholder="https://…/subtitle.vtt" /> : <label className="admin-source-file-input"><Upload size={14} /><span>{file ? file.name : initialSubtitleRoute ? `Đang dùng: ${initialSubtitleRoute}` : initial?.existingUploaded ? "Giữ tệp hiện tại hoặc chọn tệp mới" : "Chọn tệp .vtt hoặc .srt"}</span><input type="file" accept=".vtt,.srt,text/vtt,application/x-subrip" onChange={event => { setPreserveExistingSubtitle(false); setFile(event.target.files?.[0] || null); }} /></label>}
      <label className="admin-source-subtitle-label-field">Ngôn ngữ phụ đề<input value={draft.subtitleLabel} onChange={event => setDraft({ ...draft, subtitleLabel: event.target.value })} placeholder="Ví dụ: Tiếng Việt / English" maxLength={80} /></label>
      <small>Hỗ trợ .vtt và .srt, hệ thống tự chuyển sang WebVTT.</small>
    </fieldset>
    <div className="admin-source-language-tracks"><div className="admin-source-language-heading"><strong>Subtitle theo ngôn ngữ</strong><button type="button" className="button button-muted" onClick={() => setDraft(current => ({ ...current, subtitleTracks: [...current.subtitleTracks, { language: "English", subtitleUrl: "", subtitleVtt: "" }] }))}><Plus size={13} /> Thêm ngôn ngữ</button></div>{draft.subtitleTracks.map((track, index) => <div className="admin-source-language-row" key={index}><input value={track.language} placeholder="Tiếng Việt / English" aria-label="Ngôn ngữ subtitle" onChange={event => setDraft(current => ({ ...current, subtitleTracks: current.subtitleTracks.map((item, itemIndex) => itemIndex === index ? { ...item, language: event.target.value } : item) }))} /><input type="url" value={track.subtitleUrl} placeholder="URL .vtt" onChange={event => setDraft(current => ({ ...current, subtitleTracks: current.subtitleTracks.map((item, itemIndex) => itemIndex === index ? { ...item, subtitleUrl: event.target.value, subtitleVtt: "" } : item) }))} /><label className="subtitle-track-file-picker"><span>{track.subtitleVtt ? "Đã tải file" : "Chọn .vtt/.srt"}</span><input type="file" accept=".vtt,.srt,text/vtt,application/x-subrip" aria-label="Upload subtitle" onChange={event => { void uploadTrack(index, event.target.files?.[0]); event.currentTarget.value = ""; }} /></label><button type="button" className="custom-icon-danger" onClick={() => setDraft(current => ({ ...current, subtitleTracks: current.subtitleTracks.filter((_, itemIndex) => itemIndex !== index) }))} aria-label="Xóa subtitle"><Trash2 size={14} /></button></div>)}</div>
    {error && <p className="admin-tv-error">{error}</p>}
    <div className="admin-source-form-actions"><button className="button button-primary" disabled={saving || uploadSubtitle.isPending}><Save size={14} />{saving || uploadSubtitle.isPending ? "Đang lưu…" : submitLabel}</button>{onCancel && <button type="button" className="button button-ghost" onClick={onCancel}>Huỷ</button>}</div>
  </form>;
}

export default function AdminMovieSources() {
  const { user, loading } = useAuth();
  const [authOpen, setAuthOpen] = useState(false);
  const [sourceName, setSourceName] = useState("");
  const [sourceNameDrafts, setSourceNameDrafts] = useState<Record<number, string>>({});
  const [addingSource, setAddingSource] = useState(false);
  const [editingEpisodeId, setEditingEpisodeId] = useState<number | null>(null);
  const [addFormRevision, setAddFormRevision] = useState<Record<number, number>>({});
  const [actionStatus, setActionStatus] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const slug = new URLSearchParams(window.location.search).get("slug")?.trim() || "";
  const isAdmin = user?.role === "admin";
  const detailQuery = trpc.cinema.detail.useQuery({ slug }, { enabled: isAdmin && Boolean(slug), retry: false });
  const sourcesQuery = trpc.movieSources.list.useQuery({ slug }, { enabled: isAdmin && Boolean(slug), retry: false });
  const sources = (sourcesQuery.data || []) as MovieSource[];
  const utils = trpc.useUtils();

  useEffect(() => {
    setSourceNameDrafts(Object.fromEntries(sources.map(source => [source.id, source.name])));
  }, [sourcesQuery.data]);

  async function refreshSources(message: string) {
    await sourcesQuery.refetch();
    setActionStatus(message);
    setActionError(null);
  }

  const addSource = trpc.movieSources.addSource.useMutation({ onSuccess: async () => { setSourceName(""); setAddingSource(false); await refreshSources("Đã thêm nguồn mới."); }, onError: error => setActionError(error.message) });
  const renameSource = trpc.movieSources.renameSource.useMutation({ onSuccess: () => refreshSources("Đã đổi tên nguồn.").catch(() => undefined), onError: error => setActionError(error.message) });
  const removeSource = trpc.movieSources.removeSource.useMutation({ onSuccess: () => refreshSources("Đã xoá nguồn và toàn bộ tập.").catch(() => undefined), onError: error => setActionError(error.message) });
  const addEpisodes = trpc.movieSources.addEpisodes.useMutation();
  const addEpisode = trpc.movieSources.addEpisode.useMutation({ onSuccess: async (_episode, variables) => { setAddFormRevision(current => ({ ...current, [variables.sourceId]: (current[variables.sourceId] || 0) + 1 })); await refreshSources("Đã thêm tập mới."); }, onError: error => setActionError(error.message) });
  const updateEpisode = trpc.movieSources.updateEpisode.useMutation({ onSuccess: async () => { setEditingEpisodeId(null); await refreshSources("Đã cập nhật tập phim."); }, onError: error => setActionError(error.message) });
  const removeEpisode = trpc.movieSources.removeEpisode.useMutation({ onSuccess: () => refreshSources("Đã xoá tập phim.").catch(() => undefined), onError: error => setActionError(error.message) });
  const reorderEpisodes = trpc.movieSources.reorderEpisodes.useMutation({ onSuccess: () => refreshSources("Đã cập nhật thứ tự tập.").catch(() => undefined), onError: error => setActionError(error.message) });
  const anyPending = addSource.isPending || renameSource.isPending || removeSource.isPending || addEpisode.isPending || addEpisodes.isPending || updateEpisode.isPending || removeEpisode.isPending || reorderEpisodes.isPending;

  if (loading) return <PageShell><main className="content-wrap inner-page"><p>Đang kiểm tra quyền truy cập…</p></main></PageShell>;
  if (!user) return <PageShell><main className="content-wrap inner-page"><div className="empty-state"><ShieldCheck size={30} /><h3>Cần đăng nhập admin</h3><p>Đăng nhập tài khoản quản trị viên để quản lý nguồn và tập phim.</p><button className="button button-primary" onClick={() => setAuthOpen(true)}>Đăng nhập</button></div><AuthDialog open={authOpen} onClose={() => setAuthOpen(false)} /></main></PageShell>;
  if (!isAdmin) return <PageShell><main className="content-wrap inner-page"><div className="empty-state"><ShieldCheck size={30} /><h3>Không có quyền truy cập</h3><p>Khu vực này chỉ dành cho quản trị viên.</p></div></main></PageShell>;
  if (!slug) return <PageShell><main className="content-wrap inner-page"><div className="empty-state"><Database size={30} /><h3>Thiếu mã phim</h3><p>Hãy mở trang này từ nút Nguồn &amp; tập trong danh sách phim.</p><RouterLink href="/admin/movies" className="button button-primary">Quay lại danh sách phim</RouterLink></div></main></PageShell>;

  function addNewSource(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const name = sourceName.trim();
    if (!name) return;
    setActionError(null);
    addSource.mutate({ slug, name });
  }

  function saveSourceName(source: MovieSource) {
    const name = (sourceNameDrafts[source.id] || "").trim();
    if (!name || name === source.name) return;
    renameSource.mutate({ id: source.id, name });
  }

  function moveEpisode(source: MovieSource, index: number, direction: -1 | 1) {
    const nextIndex = index + direction;
    if (nextIndex < 0 || nextIndex >= source.episodes.length || reorderEpisodes.isPending) return;
    const ids = source.episodes.map(episode => episode.id);
    [ids[index], ids[nextIndex]] = [ids[nextIndex], ids[index]];
    reorderEpisodes.mutate({ sourceId: source.id, ids });
  }

  function editDraft(episode: MovieSourceEpisode): EpisodeDraft & { existingUploaded: boolean } {
    return { name: episode.name, streamUrl: episode.streamUrl, subtitleUrl: displaySubtitleURL(episode.subtitleUrl), subtitleLabel: episode.subtitleLabel || "", subtitleMode: episode.hasUploadedSubtitle ? "file" : "url", subtitleTracks: (episode.subtitleTracks || []).map(track => ({ language: track.language, subtitleUrl: displaySubtitleURL(track.subtitleUrl), subtitleVtt: "" })), existingUploaded: episode.hasUploadedSubtitle };
  }

  async function handleAddEpisode(sourceId: number, payload: EpisodePayload) {
    await addEpisode.mutateAsync({ sourceId, ...payload });
  }

  /** Thêm cả danh sách tập trong một lần gọi, dùng cho ô dán danh sách. */
  async function handleAddEpisodes(sourceId: number, items: EpisodePayload[]) {
    if (items.length === 0) return { added: 0, skipped: 0 };
    const result = await addEpisodes.mutateAsync({
      sourceId,
      episodes: items.map(item => ({ name: item.name, streamUrl: item.streamUrl, subtitleUrl: item.subtitleUrl ?? null, subtitleLabel: item.subtitleLabel ?? null, subtitleVtt: null, subtitleTracks: item.subtitleTracks ?? [] })),
    });
    await refreshSources(`Đã thêm ${result.added} tập${result.skipped.length > 0 ? `, bỏ qua ${result.skipped.length} dòng trùng` : ""}.`);
    return { added: result.added, skipped: result.skipped.length };
  }

  async function handleUpdateEpisode(id: number, payload: EpisodePayload) {
    await updateEpisode.mutateAsync({ id, ...payload });
  }

  return <PageShell><main className="content-wrap inner-page admin-movie-sources-page">
    <div className="page-topline"><RouterLink href="/admin/movies" className="back-link">← Danh sách phim</RouterLink><span className="result-note"><RouterLink href="/admin/accounts" className="text-link">Quản lý tài khoản</RouterLink> · Quản trị viên</span></div>
    <SectionHeading eyebrow="CINEMORA ADMIN" title="Quản lý nguồn & tập phim" action={<button type="button" className="admin-tv-refresh" onClick={() => { void Promise.all([detailQuery.refetch(), sourcesQuery.refetch()]); }} disabled={detailQuery.isFetching || sourcesQuery.isFetching} title="Làm mới"><RefreshCw size={15} /></button>} />
    {(actionError || detailQuery.error || sourcesQuery.error) && <p className="admin-tv-error admin-source-global-error">{actionError || (detailQuery.error ? `Không thể tải thông tin phim: ${detailQuery.error.message}` : `Không thể tải nguồn thủ công: ${sourcesQuery.error?.message}`)}</p>}
    {actionStatus && !actionError && <p className="admin-tv-success admin-source-global-status">{actionStatus}</p>}

    <section className="admin-source-info-card"><div><span className="admin-source-eyebrow">THÔNG TIN PHIM</span><h2>{detailQuery.isLoading ? "Đang tải thông tin phim…" : detailQuery.data?.name || "Không rõ tên phim"}</h2><p>Slug: <code>{slug}</code></p></div><RouterLink href="/admin/movies" className="button button-ghost">Quay lại danh sách phim</RouterLink></section>

    <section className="admin-source-panel"><div className="admin-source-panel-heading"><div><strong>Nguồn từ API</strong><span>Chỉ đọc dữ liệu gốc từ API của phim.</span></div><Database size={19} /></div><p className="admin-source-readonly-note">Nguồn gốc từ API — không sửa được ở đây</p>{detailQuery.isLoading ? <p className="admin-movies-muted">Đang tải các nguồn gốc…</p> : (detailQuery.data?.servers || []).length === 0 ? <p className="admin-movies-muted">Phim chưa có nguồn gốc từ API.</p> : <div className="admin-api-source-list">{detailQuery.data?.servers.map(server => <article className="admin-api-source-card" key={server.name}><div className="admin-api-source-heading"><strong>{server.name}</strong><span>{server.episodes.length} tập</span></div><div className="admin-api-episode-list">{server.episodes.map(episode => <span key={episode.slug}><FileText size={12} />{episode.name}</span>)}</div></article>)}</div>}</section>

    <section className="admin-source-panel admin-manual-source-panel"><div className="admin-source-panel-heading"><div><strong>Nguồn thêm thủ công</strong><span>Thêm nguồn riêng và không giới hạn số tập.</span></div><button type="button" className="button button-primary" onClick={() => { setAddingSource(!addingSource); setActionError(null); }} disabled={anyPending}><Plus size={15} /> Thêm nguồn</button></div>
      {addingSource && <form className="admin-add-source-form" onSubmit={addNewSource}><input value={sourceName} onChange={event => setSourceName(event.target.value)} placeholder="Tên nguồn, ví dụ: Lồng tiếng" required autoFocus /><button className="button button-primary" disabled={addSource.isPending}><Save size={14} />{addSource.isPending ? "Đang tạo…" : "Tạo nguồn"}</button><button type="button" className="button button-ghost" onClick={() => setAddingSource(false)}>Huỷ</button></form>}
      {sourcesQuery.isLoading ? <p className="admin-movies-muted">Đang tải nguồn thủ công…</p> : sources.length === 0 ? <div className="admin-source-empty"><Database size={24} /><strong>Chưa có nguồn thủ công</strong><span>Bấm “Thêm nguồn” để tạo nguồn đầu tiên cho phim này.</span></div> : <div className="admin-manual-source-list">{sources.map(source => <article className="admin-manual-source-card" key={source.id}>
        <div className="admin-manual-source-heading"><div className="admin-manual-source-name"><input value={sourceNameDrafts[source.id] ?? source.name} onChange={event => setSourceNameDrafts({ ...sourceNameDrafts, [source.id]: event.target.value })} aria-label={`Tên nguồn ${source.name}`} /><button type="button" className="button button-ghost" disabled={renameSource.isPending || !(sourceNameDrafts[source.id] || "").trim() || sourceNameDrafts[source.id] === source.name} onClick={() => saveSourceName(source)}><Save size={14} /> Lưu tên</button></div><button type="button" className="button button-danger" disabled={removeSource.isPending} onClick={() => { if (window.confirm(`Xoá nguồn “${source.name}” và toàn bộ ${source.episodes.length} tập?`)) removeSource.mutate({ id: source.id }); }}><Trash2 size={14} /> Xoá nguồn</button></div>
        <div className="admin-manual-source-meta">{source.episodes.length} tập · Nguồn do admin thêm</div>
        <div className="admin-episode-list">{source.episodes.length === 0 ? <p className="admin-movies-muted">Nguồn chưa có tập nào.</p> : source.episodes.map((episode, index) => <div className="admin-manual-episode-wrap" key={episode.id} data-episode-id={episode.id}><article className="admin-manual-episode"><div className="admin-manual-episode-copy"><strong>{episode.name}</strong><a href={episode.streamUrl} target="_blank" rel="noreferrer"><Link2 size={13} />{episode.streamUrl}</a>{episode.subtitleUrl ? <a href={episode.subtitleUrl} target="_blank" rel="noreferrer" className="admin-subtitle-link"><FileText size={13} />Phụ đề {episode.hasUploadedSubtitle ? "đã upload" : "VTT ngoài"}</a> : <span className="admin-no-subtitle">Chưa có phụ đề</span>}</div><div className="admin-episode-actions"><button type="button" className="admin-movies-action" disabled={index === 0 || reorderEpisodes.isPending} onClick={() => moveEpisode(source, index, -1)} title="Di chuyển lên"><ArrowUp size={14} /> Lên</button><button type="button" className="admin-movies-action" disabled={index === source.episodes.length - 1 || reorderEpisodes.isPending} onClick={() => moveEpisode(source, index, 1)} title="Di chuyển xuống"><ArrowDown size={14} /> Xuống</button><button type="button" className="admin-movies-action" disabled={anyPending} onClick={() => { const next = editingEpisodeId === episode.id ? null : episode.id; setEditingEpisodeId(next); if (next) scrollEpisodeIntoView(episode.id); }}><Pencil size={14} /> Sửa</button><button type="button" className="admin-movies-action is-danger" disabled={removeEpisode.isPending} onClick={() => { if (window.confirm(`Xoá tập “${episode.name}”?`)) removeEpisode.mutate({ id: episode.id }); }}><Trash2 size={14} /> Xoá</button></div></article>{editingEpisodeId === episode.id && <EpisodeForm key={`edit-${episode.id}`} initial={editDraft(episode)} submitLabel="Lưu tập" onCancel={() => setEditingEpisodeId(null)} onSubmit={payload => handleUpdateEpisode(episode.id, payload)} />}</div>)}</div>
        <EpisodeForm key={`add-${source.id}-${addFormRevision[source.id] || 0}`} submitLabel="Thêm tập" existingEpisodes={source.episodes.map(episode => ({ name: episode.name, streamUrl: episode.streamUrl }))} onSubmit={payload => handleAddEpisode(source.id, payload)} onSubmitMany={items => handleAddEpisodes(source.id, items)} />
      </article>)}</div>}
    </section>
  </main></PageShell>;
}
