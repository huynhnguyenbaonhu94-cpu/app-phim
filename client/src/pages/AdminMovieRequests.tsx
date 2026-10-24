import { useState } from "react";
import { ExternalLink, Film, RefreshCw, Save, ShieldCheck } from "lucide-react";
import { Link } from "wouter";
import { PageShell, SectionHeading } from "@/components/CinemaChrome";
import { AuthDialog } from "@/components/AuthDialog";
import { useAuth } from "@/_core/hooks/useAuth";
import { trpc } from "@/lib/trpc";

const STATUS_OPTIONS = [
  ["received", "Đã Tiếp Nhận"],
  ["processing", "Đang Xử Lý"],
  ["updated", "Đã Cập Nhật"],
  ["other", "Khác"],
] as const;

type RequestStatus = (typeof STATUS_OPTIONS)[number][0];

function formatDate(value: unknown) {
  if (!value) return "Chưa có";
  const date = new Date(value as string | number | Date);
  return Number.isNaN(date.getTime()) ? "Chưa có" : date.toLocaleString("vi-VN");
}

function statusLabel(status: string) {
  return STATUS_OPTIONS.find(([value]) => value === status)?.[1] ?? "Đã Tiếp Nhận";
}

function statusClass(status: string) {
  return `movie-request-status movie-request-status--${status || "received"}`;
}

export default function AdminMovieRequests() {
  const { user, loading } = useAuth();
  const [authOpen, setAuthOpen] = useState(false);
  const [drafts, setDrafts] = useState<Record<number, { status: RequestStatus; message: string }>>({});
  const requests = trpc.movieRequests.list.useQuery(undefined, {
    enabled: user?.role === "admin",
    refetchInterval: 8_000,
    retry: false,
  });
  const update = trpc.movieRequests.update.useMutation({
    onSuccess: () => requests.refetch(),
  });

  if (loading) return <PageShell><main className="content-wrap inner-page"><p>Đang kiểm tra quyền truy cập…</p></main></PageShell>;
  if (!user) return <PageShell><main className="content-wrap inner-page"><div className="empty-state"><ShieldCheck size={30} /><h3>Cần đăng nhập admin</h3><p>Đăng nhập tài khoản quản trị viên để xem yêu cầu phim.</p><button className="button button-primary" onClick={() => setAuthOpen(true)}>Đăng nhập</button></div><AuthDialog open={authOpen} onClose={() => setAuthOpen(false)} /></main></PageShell>;
  if (user.role !== "admin") return <PageShell><main className="content-wrap inner-page"><div className="empty-state"><ShieldCheck size={30} /><h3>Không có quyền truy cập</h3><p>Khu vực này chỉ dành cho quản trị viên.</p></div></main></PageShell>;

  return <PageShell><main className="content-wrap inner-page admin-movie-requests-page">
    <div className="page-topline"><Link href="/admin/accounts" className="back-link">← Quản trị</Link><span className="result-note"><Link href="/admin/accounts" className="text-link">Tài khoản</Link> · tự cập nhật mỗi 8 giây</span></div>
    <SectionHeading
      eyebrow="CINEMORA ADMIN"
      title="Yêu cầu phim"
      action={<button className="admin-tv-refresh" onClick={() => requests.refetch()} disabled={requests.isFetching} title="Cập nhật ngay"><RefreshCw size={15} className={requests.isFetching ? "admin-tv-refresh-spin" : ""} /></button>}
    />
    <p className="admin-accounts-note">Hiển thị tất cả yêu cầu từ tài khoản đã đăng nhập và khách. Khi admin đổi tiến trình, app của tài khoản tương ứng sẽ nhận trạng thái mới gần như real-time.</p>

    {requests.isLoading ? <p>Đang tải yêu cầu phim…</p> : requests.error ? <p className="admin-tv-error">Không thể tải yêu cầu: {requests.error.message}</p> : (requests.data ?? []).length === 0 ? (
      <div className="admin-movie-requests-empty"><Film size={28} /><strong>Chưa có yêu cầu phim</strong><span>Các yêu cầu mới từ app sẽ xuất hiện ở đây.</span></div>
    ) : <section className="admin-movie-request-list">
      {(requests.data ?? []).map((item) => {
        const draft = drafts[item.id] ?? { status: item.status as RequestStatus, message: item.adminMessage ?? "" };
        const hasLink = Boolean(item.link?.trim());
        const linkHref = hasLink && /^https?:\/\//i.test(item.link!.trim()) ? item.link!.trim() : null;
        return <article className="admin-movie-request-card" key={item.id}>
          <div className="admin-movie-request-main">
            <div className="admin-movie-request-poster">
              {item.posterUrl ? <img src={item.posterUrl} alt={`Poster ${item.title}`} /> : <Film size={22} />}
            </div>
            <div className="admin-movie-request-copy">
              <div className="admin-movie-request-title-row"><strong>{item.title}</strong><span className={statusClass(item.status)}>{statusLabel(item.status)}</span></div>
              <span className="admin-movie-request-meta">{item.requesterName || "Khách chưa đăng nhập"}{item.requesterEmail ? ` · ${item.requesterEmail}` : ""} · gửi {formatDate(item.createdAt)}</span>
              <span className="admin-movie-request-meta">Ưu tiên: <b>{item.priority}</b>{item.statusUpdatedAt ? ` · cập nhật ${formatDate(item.statusUpdatedAt)}` : ""}</span>
              {hasLink && <span className="admin-movie-request-link">Link: {linkHref ? <a href={linkHref} target="_blank" rel="noreferrer">{item.link} <ExternalLink size={11} /></a> : item.link}</span>}
              {item.notes && <p className="admin-movie-request-notes"><b>Ghi chú:</b> {item.notes}</p>}
            </div>
          </div>
          <div className="admin-movie-request-editor">
            <label>Tiến trình<select value={draft.status} onChange={(event) => setDrafts({ ...drafts, [item.id]: { ...draft, status: event.target.value as RequestStatus } })}>{STATUS_OPTIONS.map(([value, label]) => <option value={value} key={value}>{label}</option>)}</select></label>
            {draft.status === "other" && <label className="is-wide">Thông tin gửi đến người dùng<textarea value={draft.message} onChange={(event) => setDrafts({ ...drafts, [item.id]: { ...draft, message: event.target.value } })} placeholder="Nhập thông tin admin muốn gửi về yêu cầu này…" maxLength={4000} /></label>}
            <button className="button button-primary" disabled={update.isPending || (draft.status === "other" && !draft.message.trim())} onClick={() => update.mutate({ id: item.id, status: draft.status, ...(draft.message.trim() ? { adminMessage: draft.message.trim() } : {}) })}><Save size={14} /> {update.isPending ? "Đang lưu…" : "Cập nhật tiến trình"}</button>
            {update.error && <span className="admin-tv-error">{update.error.message}</span>}
          </div>
          {item.adminMessage && <div className="admin-movie-request-admin-message"><b>Thông tin admin đã gửi:</b><span>{item.adminMessage}</span></div>}
        </article>;
      })}
    </section>}
  </main></PageShell>;
}
