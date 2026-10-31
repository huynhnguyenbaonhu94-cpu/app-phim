import { useState } from "react";
import {
  Activity,
  Archive,
  ArrowUpRight,
  BarChart3,
  CheckCircle2,
  ChevronRight,
  CircleAlert,
  Clock3,
  Cloud,
  Database,
  Film,
  Gauge,
  Inbox,
  LayoutDashboard,
  ListChecks,
  MessageCircle,
  MessagesSquare,
  PlaySquare,
  RefreshCw,
  Server,
  Settings2,
  ShieldCheck,
  Sparkles,
  Tv,
  Users,
  Video,
} from "lucide-react";
import { Link } from "wouter";
import { AuthDialog } from "@/components/AuthDialog";
import { PageShell } from "@/components/CinemaChrome";
import { useAuth } from "@/_core/hooks/useAuth";
import { trpc } from "@/lib/trpc";
import "./AdminDashboard.css";

type DashboardOverview = {
  generatedAt: string;
  counts: {
    users: number;
    admins: number;
    privilegedUsers: number;
    customMovies: number;
    publishedMovies: number;
    totalViews: number;
    requests: number;
    requestReceived: number;
    requestProcessing: number;
    requestUpdated: number;
    requestOther: number;
    comments: number;
    conversations: number;
    messagesFromUsers: number;
    unreadMessages: number;
    tvChannels: number;
    activeTvChannels: number;
    tvVideos: number;
    activeTvVideos: number;
    episodes: number;
    backups: number;
  };
  latestBackup: {
    status: string | null;
    startedAt: string | null;
    completedAt: string | null;
    byteSize: number | null;
    errorMessage: string | null;
  } | null;
  r2: {
    configured: boolean;
    backupEnabled: boolean;
    backupFrequency: "daily" | "weekly";
    scheduleHourVietnam: number;
    latestStatus: string | null;
    running: boolean;
  };
  recentRequests: Array<{
    id: number;
    title: string;
    status: string;
    createdAt: string;
    requesterName: string | null;
  }>;
};

type MetricTone =
  | "lime"
  | "blue"
  | "violet"
  | "orange"
  | "rose"
  | "cyan"
  | "gold"
  | "slate";

type Metric = {
  label: string;
  value: number;
  detail: string;
  icon: typeof Users;
  tone: MetricTone;
};

const STATUS_META: Record<string, { label: string; tone: string }> = {
  received: { label: "Đã tiếp nhận", tone: "received" },
  processing: { label: "Đang xử lý", tone: "processing" },
  updated: { label: "Đã cập nhật", tone: "updated" },
  other: { label: "Khác", tone: "other" },
};

const QUICK_LINKS = [
  {
    href: "/admin/movies",
    label: "Quản lý phim",
    description: "Kho phim & bình luận",
    icon: Film,
    tone: "lime",
  },
  {
    href: "/admin/movies/custom/new",
    label: "Thêm phim thủ công",
    description: "Tạo phim và tập mới",
    icon: Sparkles,
    tone: "violet",
  },
  {
    href: "/admin/movies/sources",
    label: "Nguồn & tập phim",
    description: "Kiểm soát nguồn phát",
    icon: Database,
    tone: "blue",
  },
  {
    href: "/admin/movie-requests",
    label: "Yêu cầu phim",
    description: "Theo dõi tiến trình",
    icon: ListChecks,
    tone: "orange",
  },
  {
    href: "/admin/accounts",
    label: "Tài khoản",
    description: "Quyền và thiết bị",
    icon: Users,
    tone: "cyan",
  },
  {
    href: "/admin/special-chat",
    label: "Chat đặc quyền",
    description: "Hội thoại với người dùng",
    icon: MessagesSquare,
    tone: "rose",
  },
  {
    href: "/admin/tv",
    label: "Truyền hình & video",
    description: "Kênh live và video TV",
    icon: Tv,
    tone: "gold",
  },
  {
    href: "/admin/r2-settings",
    label: "R2 & backup",
    description: "Lưu trữ và sao lưu",
    icon: Cloud,
    tone: "slate",
  },
] as const;

function formatNumber(value: number | null | undefined) {
  return new Intl.NumberFormat("vi-VN").format(value ?? 0);
}

function formatDate(value: string | null | undefined, withTime = true) {
  if (!value) return "Chưa có";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Chưa có";
  return date.toLocaleString("vi-VN", {
    timeZone: "Asia/Ho_Chi_Minh",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    ...(withTime ? { hour: "2-digit", minute: "2-digit" } : {}),
  });
}

function formatBytes(value: number | null | undefined) {
  if (value === null || value === undefined || value < 0) return "—";
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
  if (value < 1024 * 1024 * 1024)
    return `${(value / (1024 * 1024)).toFixed(1)} MB`;
  return `${(value / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}

function statusMeta(status: string | null | undefined) {
  return (
    STATUS_META[status ?? ""] ?? { label: status || "Chưa rõ", tone: "other" }
  );
}

function backupStatusMeta(status: string | null | undefined, running: boolean) {
  if (running || status === "running")
    return { label: "Đang chạy", tone: "running" };
  if (status === "completed") return { label: "Thành công", tone: "completed" };
  if (status === "failed") return { label: "Thất bại", tone: "failed" };
  return { label: "Chưa chạy", tone: "idle" };
}

function MetricCard({ metric }: { metric: Metric }) {
  const Icon = metric.icon;
  return (
    <article
      className={`admin-dashboard-metric admin-dashboard-metric--${metric.tone}`}
    >
      <div className="admin-dashboard-metric-top">
        <span className="admin-dashboard-metric-icon">
          <Icon size={17} />
        </span>
        <span className="admin-dashboard-metric-kicker">LIVE DATA</span>
      </div>
      <strong>{formatNumber(metric.value)}</strong>
      <span className="admin-dashboard-metric-label">{metric.label}</span>
      <small>{metric.detail}</small>
    </article>
  );
}

export default function AdminDashboard() {
  const { user, loading } = useAuth();
  const [authOpen, setAuthOpen] = useState(false);
  const dashboard = trpc.adminDashboard.overview.useQuery(undefined, {
    enabled: user?.role === "admin",
    refetchInterval: 60_000,
    retry: false,
  });
  const data = dashboard.data as DashboardOverview | undefined;

  if (loading) {
    return (
      <PageShell>
        <main className="content-wrap inner-page">
          <p>Đang kiểm tra quyền truy cập…</p>
        </main>
      </PageShell>
    );
  }

  if (!user) {
    return (
      <PageShell>
        <main className="content-wrap inner-page">
          <div className="empty-state">
            <ShieldCheck size={30} />
            <h3>Cần đăng nhập admin</h3>
            <p>Đăng nhập tài khoản quản trị viên để xem tổng quan hệ thống.</p>
            <button
              className="button button-primary"
              onClick={() => setAuthOpen(true)}
            >
              Đăng nhập
            </button>
          </div>
          <AuthDialog open={authOpen} onClose={() => setAuthOpen(false)} />
        </main>
      </PageShell>
    );
  }

  if (user.role !== "admin") {
    return (
      <PageShell>
        <main className="content-wrap inner-page">
          <div className="empty-state">
            <ShieldCheck size={30} />
            <h3>Không có quyền truy cập</h3>
            <p>Khu vực này chỉ dành cho quản trị viên.</p>
          </div>
        </main>
      </PageShell>
    );
  }

  const counts = data?.counts;
  const requestTotal = counts?.requests ?? 0;
  const requestStatuses = [
    { key: "received", value: counts?.requestReceived ?? 0 },
    { key: "processing", value: counts?.requestProcessing ?? 0 },
    { key: "updated", value: counts?.requestUpdated ?? 0 },
    { key: "other", value: counts?.requestOther ?? 0 },
  ];
  const backupMeta = backupStatusMeta(
    data?.latestBackup?.status ?? data?.r2.latestStatus,
    Boolean(data?.r2.running),
  );
  const metrics: Metric[] = [
    {
      label: "Người dùng",
      value: counts?.users ?? 0,
      detail: `${formatNumber(counts?.admins)} quản trị viên`,
      icon: Users,
      tone: "lime",
    },
    {
      label: "Phim tùy chỉnh",
      value: counts?.customMovies ?? 0,
      detail: `${formatNumber(counts?.publishedMovies)} phim đã xuất bản`,
      icon: Film,
      tone: "blue",
    },
    {
      label: "Lượt xem phim tùy chỉnh",
      value: counts?.totalViews ?? 0,
      detail: `${formatNumber(counts?.episodes)} tập trong hệ thống`,
      icon: BarChart3,
      tone: "violet",
    },
    {
      label: "Yêu cầu phim",
      value: counts?.requests ?? 0,
      detail: `${formatNumber(counts?.requestProcessing)} yêu cầu đang xử lý`,
      icon: Inbox,
      tone: "orange",
    },
    {
      label: "Bình luận",
      value: counts?.comments ?? 0,
      detail: `${formatNumber(counts?.privilegedUsers)} người dùng đặc quyền`,
      icon: MessageCircle,
      tone: "rose",
    },
    {
      label: "Tin nhắn chưa đọc",
      value: counts?.unreadMessages ?? 0,
      detail: `${formatNumber(counts?.messagesFromUsers)} tin nhắn từ người dùng`,
      icon: MessagesSquare,
      tone: "cyan",
    },
    {
      label: "Kênh truyền hình",
      value: counts?.tvChannels ?? 0,
      detail: `${formatNumber(counts?.activeTvChannels)} kênh đang hoạt động`,
      icon: Tv,
      tone: "gold",
    },
    {
      label: "Video TV",
      value: counts?.tvVideos ?? 0,
      detail: `${formatNumber(counts?.activeTvVideos)} video đang hoạt động`,
      icon: Video,
      tone: "slate",
    },
  ];

  return (
    <PageShell>
      <main className="content-wrap inner-page admin-dashboard-page">
        <div className="page-topline">
          <Link href="/" className="back-link">
            ← Quay lại ứng dụng
          </Link>
          <span className="result-note">
            CINEMORA ADMIN ·{" "}
            {data?.generatedAt
              ? `cập nhật ${formatDate(data.generatedAt)}`
              : "đang đồng bộ"}
          </span>
        </div>

        <section
          className="admin-dashboard-hero"
          aria-labelledby="admin-dashboard-title"
        >
          <div className="admin-dashboard-hero-orb admin-dashboard-hero-orb--one" />
          <div className="admin-dashboard-hero-orb admin-dashboard-hero-orb--two" />
          <div className="admin-dashboard-hero-grid" />
          <div className="admin-dashboard-hero-content">
            <div className="admin-dashboard-hero-kicker">
              <span className="admin-dashboard-live-dot" /> CONTROL ROOM /
              OVERVIEW
            </div>
            <h1 id="admin-dashboard-title">
              Bảng điều khiển <em>quản trị.</em>
            </h1>
            <p>
              Theo dõi nhịp vận hành của Cinemora từ một màn hình: nội dung,
              cộng đồng, yêu cầu phim và hạ tầng lưu trữ.
            </p>
          </div>
          <div className="admin-dashboard-hero-actions">
            <span className="admin-dashboard-sync">
              <Activity size={14} /> Đồng bộ mỗi 60 giây
            </span>
            <button
              type="button"
              className="button button-ghost admin-dashboard-refresh"
              onClick={() => void dashboard.refetch()}
              disabled={dashboard.isFetching}
              title="Cập nhật dữ liệu"
            >
              <RefreshCw
                size={15}
                className={
                  dashboard.isFetching ? "admin-dashboard-refresh-spin" : ""
                }
              />{" "}
              {dashboard.isFetching ? "Đang cập nhật…" : "Cập nhật ngay"}
            </button>
          </div>
        </section>

        <div className="admin-dashboard-section-head">
          <div>
            <span className="eyebrow">SYSTEM PULSE</span>
            <h2>Những con số đáng chú ý</h2>
          </div>
          <span className="admin-dashboard-section-note">
            <Gauge size={14} /> Số liệu thực từ database
          </span>
        </div>

        {dashboard.isLoading ? (
          <section
            className="admin-dashboard-metric-grid"
            aria-label="Đang tải số liệu"
          >
            {Array.from({ length: 8 }, (_, index) => (
              <div className="admin-dashboard-metric-skeleton" key={index} />
            ))}
          </section>
        ) : dashboard.error ? (
          <section className="admin-dashboard-state admin-dashboard-state--error">
            <CircleAlert size={22} />
            <div>
              <strong>Không thể tải tổng quan</strong>
              <p>
                {dashboard.error.message || "Vui lòng thử lại sau ít phút."}
              </p>
            </div>
            <button
              type="button"
              className="button button-ghost"
              onClick={() => void dashboard.refetch()}
            >
              Thử lại
            </button>
          </section>
        ) : data ? (
          <>
            <section
              className="admin-dashboard-metric-grid"
              aria-label="Số liệu tổng quan"
            >
              {metrics.map((metric) => (
                <MetricCard key={metric.label} metric={metric} />
              ))}
            </section>

            <section className="admin-dashboard-main-grid">
              <article className="admin-dashboard-panel admin-dashboard-request-panel">
                <div className="admin-dashboard-panel-heading">
                  <div>
                    <span className="eyebrow">REQUEST FLOW</span>
                    <h2>Phân bổ yêu cầu phim</h2>
                  </div>
                  <Link
                    href="/admin/movie-requests"
                    className="admin-dashboard-panel-link"
                  >
                    Mở quản lý <ArrowUpRight size={14} />
                  </Link>
                </div>
                <div className="admin-dashboard-request-total">
                  <strong>{formatNumber(requestTotal)}</strong>
                  <span>tổng yêu cầu</span>
                </div>
                <div className="admin-dashboard-status-list">
                  {requestStatuses.map((item) => {
                    const meta = statusMeta(item.key);
                    const percentage =
                      requestTotal > 0
                        ? Math.round((item.value / requestTotal) * 100)
                        : 0;
                    return (
                      <div
                        className="admin-dashboard-status-row"
                        key={item.key}
                      >
                        <div className="admin-dashboard-status-label">
                          <span
                            className={`admin-dashboard-status-dot admin-dashboard-status-dot--${meta.tone}`}
                          />
                          <span>{meta.label}</span>
                          <strong>{formatNumber(item.value)}</strong>
                        </div>
                        <div
                          className="admin-dashboard-status-track"
                          aria-label={`${meta.label}: ${formatNumber(item.value)}`}
                        >
                          <i
                            className={`admin-dashboard-status-fill admin-dashboard-status-fill--${meta.tone}`}
                            style={{ width: `${percentage}%` }}
                          />
                        </div>
                        <span className="admin-dashboard-status-percent">
                          {percentage}%
                        </span>
                      </div>
                    );
                  })}
                </div>
                <p className="admin-dashboard-panel-foot">
                  <ListChecks size={14} /> Phân bổ theo trạng thái hiện tại,
                  không phải dữ liệu mẫu.
                </p>
              </article>

              <article className="admin-dashboard-panel admin-dashboard-backup-panel">
                <div className="admin-dashboard-panel-heading">
                  <div>
                    <span className="eyebrow">INFRASTRUCTURE</span>
                    <h2>R2 & database backup</h2>
                  </div>
                  <Link
                    href="/admin/r2-settings"
                    className="admin-dashboard-panel-link"
                  >
                    Cấu hình <Settings2 size={14} />
                  </Link>
                </div>
                <div
                  className={`admin-dashboard-backup-status admin-dashboard-backup-status--${backupMeta.tone}`}
                >
                  <span className="admin-dashboard-backup-status-icon">
                    {backupMeta.tone === "failed" ? (
                      <CircleAlert size={17} />
                    ) : backupMeta.tone === "completed" ? (
                      <CheckCircle2 size={17} />
                    ) : backupMeta.tone === "running" ? (
                      <RefreshCw
                        size={17}
                        className="admin-dashboard-refresh-spin"
                      />
                    ) : (
                      <Archive size={17} />
                    )}
                  </span>
                  <div>
                    <strong>{backupMeta.label}</strong>
                    <span>
                      {data.r2.configured
                        ? "Cloudflare R2 đã được kết nối"
                        : "Chưa cấu hình Cloudflare R2"}
                    </span>
                  </div>
                </div>
                <div className="admin-dashboard-detail-list">
                  <div>
                    <span>Lần backup gần nhất</span>
                    <strong>
                      {formatDate(
                        data.latestBackup?.completedAt ||
                          data.latestBackup?.startedAt,
                      )}
                    </strong>
                  </div>
                  <div>
                    <span>Lịch tự động</span>
                    <strong>
                      {data.r2.backupEnabled
                        ? `${data.r2.backupFrequency === "daily" ? "Hàng ngày" : "Hàng tuần"} · ${String(data.r2.scheduleHourVietnam).padStart(2, "0")}:00 giờ VN`
                        : "Đang tắt"}
                    </strong>
                  </div>
                  <div>
                    <span>Dung lượng gần nhất</span>
                    <strong>{formatBytes(data.latestBackup?.byteSize)}</strong>
                  </div>
                </div>
                {data.latestBackup?.errorMessage && (
                  <p className="admin-dashboard-backup-error">
                    <CircleAlert size={14} /> {data.latestBackup.errorMessage}
                  </p>
                )}
                <div className="admin-dashboard-backup-foot">
                  <span>
                    <Server size={13} />{" "}
                    {data.r2.latestStatus
                      ? `Trạng thái: ${backupMeta.label}`
                      : "Chưa có trạng thái backup"}
                  </span>
                  <span className="admin-dashboard-vietnam-chip">
                    <Clock3 size={12} /> Giờ Việt Nam
                  </span>
                </div>
              </article>
            </section>

            <section className="admin-dashboard-lower-grid">
              <article className="admin-dashboard-panel admin-dashboard-recent-panel">
                <div className="admin-dashboard-panel-heading">
                  <div>
                    <span className="eyebrow">INBOX</span>
                    <h2>Yêu cầu mới nhất</h2>
                  </div>
                  <Link
                    href="/admin/movie-requests"
                    className="admin-dashboard-panel-link"
                  >
                    Xem tất cả <ChevronRight size={14} />
                  </Link>
                </div>
                {data.recentRequests.length === 0 ? (
                  <div className="admin-dashboard-empty">
                    <Inbox size={20} />
                    <span>Chưa có yêu cầu phim nào.</span>
                  </div>
                ) : (
                  <div className="admin-dashboard-recent-list">
                    {data.recentRequests.map((request) => {
                      const meta = statusMeta(request.status);
                      return (
                        <Link
                          href="/admin/movie-requests"
                          className="admin-dashboard-recent-row"
                          key={request.id}
                        >
                          <span className="admin-dashboard-recent-index">
                            #{request.id}
                          </span>
                          <span className="admin-dashboard-recent-copy">
                            <strong>{request.title}</strong>
                            <small>
                              {request.requesterName || "Khách chưa đăng nhập"}{" "}
                              · {formatDate(request.createdAt)}
                            </small>
                          </span>
                          <span
                            className={`admin-dashboard-request-badge admin-dashboard-request-badge--${meta.tone}`}
                          >
                            {meta.label}
                          </span>
                          <ArrowUpRight
                            size={14}
                            className="admin-dashboard-recent-arrow"
                          />
                        </Link>
                      );
                    })}
                  </div>
                )}
              </article>

              <article className="admin-dashboard-panel admin-dashboard-ops-panel">
                <div className="admin-dashboard-panel-heading">
                  <div>
                    <span className="eyebrow">OPS SNAPSHOT</span>
                    <h2>Nhịp vận hành</h2>
                  </div>
                  <LayoutDashboard
                    size={18}
                    className="admin-dashboard-heading-icon"
                  />
                </div>
                <div className="admin-dashboard-ops-list">
                  <div>
                    <span className="admin-dashboard-ops-icon">
                      <PlaySquare size={15} />
                    </span>
                    <span>
                      <strong>{formatNumber(counts?.tvVideos)}</strong>
                      <small>
                        video TV · {formatNumber(counts?.activeTvVideos)} đang
                        bật
                      </small>
                    </span>
                  </div>
                  <div>
                    <span className="admin-dashboard-ops-icon">
                      <Database size={15} />
                    </span>
                    <span>
                      <strong>{formatNumber(counts?.backups)}</strong>
                      <small>phiên backup đã ghi nhận</small>
                    </span>
                  </div>
                  <div>
                    <span className="admin-dashboard-ops-icon">
                      <MessageCircle size={15} />
                    </span>
                    <span>
                      <strong>{formatNumber(counts?.conversations)}</strong>
                      <small>cuộc hội thoại đặc quyền</small>
                    </span>
                  </div>
                </div>
              </article>
            </section>

            <div className="admin-dashboard-section-head admin-dashboard-section-head--links">
              <div>
                <span className="eyebrow">ADMIN TOOLKIT</span>
                <h2>Đi nhanh đến mọi tính năng</h2>
              </div>
              <span className="admin-dashboard-section-note">
                8 khu vực quản trị
              </span>
            </div>
            <nav
              className="admin-dashboard-quick-links"
              aria-label="Tính năng quản trị"
            >
              {QUICK_LINKS.map((item) => {
                const Icon = item.icon;
                return (
                  <Link
                    key={item.href}
                    href={item.href}
                    className={`admin-dashboard-quick-link admin-dashboard-quick-link--${item.tone}`}
                  >
                    <span className="admin-dashboard-quick-icon">
                      <Icon size={18} />
                    </span>
                    <span>
                      <strong>{item.label}</strong>
                      <small>{item.description}</small>
                    </span>
                    <ArrowUpRight
                      size={15}
                      className="admin-dashboard-quick-arrow"
                    />
                  </Link>
                );
              })}
            </nav>
          </>
        ) : (
          <section className="admin-dashboard-state">
            <CircleAlert size={22} />
            <div>
              <strong>Chưa có dữ liệu tổng quan</strong>
              <p>Backend chưa trả về dữ liệu dashboard.</p>
            </div>
          </section>
        )}
      </main>
    </PageShell>
  );
}
