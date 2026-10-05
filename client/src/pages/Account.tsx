import { ArrowLeft, Clock3, Heart, LogOut, MonitorSmartphone, Play, ShieldCheck, Trash2 } from "lucide-react";
import { Link } from "wouter";
import { MovieCard, PageShell, SectionHeading } from "@/components/CinemaChrome";
import { clearHistory, listFavorites, listHistory, removeFavorite, removeHistory, subscribeLibrary, updateHistoryPoster, type LocalHistory, type LocalMovie } from "@/lib/localLibrary";
import { trpc } from "@/lib/trpc";
import { useEffect, useRef, useState } from "react";
import { useAuth } from "@/_core/hooks/useAuth";
import { AuthDialog } from "@/components/AuthDialog";

function formatDate(value: unknown) {
  if (!value) return "Vừa xem";
  const date = new Date(value as string | number | Date);
  if (Number.isNaN(date.getTime())) return "Vừa xem";
  return date.toLocaleDateString("vi-VN", { day: "2-digit", month: "2-digit", year: "numeric" });
}

function formatTime(seconds: number) {
  if (!seconds || seconds <= 0) return null;
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);
  if (h > 0) return `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
  return `${m}:${String(s).padStart(2, "0")}`;
}

function HistoryPoster({ item }: { item: LocalHistory }) {
  const [src, setSrc] = useState(item.poster);
  const refreshTried = useRef(false);
  const detailQuery = trpc.cinema.detail.useQuery({ slug: item.slug }, { enabled: false, retry: 1, staleTime: 0 });

  useEffect(() => {
    setSrc(item.poster);
    refreshTried.current = false;
  }, [item.poster]);

  if (!src) return <Play size={18} />;
  return <img
    src={src}
    alt={item.name}
    onError={() => {
      if (refreshTried.current) return;
      refreshTried.current = true;
      detailQuery.refetch().then(({ data }) => {
        const freshPoster = (data as { poster?: string | null } | undefined)?.poster;
        if (freshPoster) {
          setSrc(freshPoster);
          updateHistoryPoster(item.slug, item.episodeSlug, freshPoster);
        } else {
          setSrc(null);
        }
      }).catch(() => setSrc(null));
    }}
  />;
}

function HistoryItem({ item, onRemove }: { item: LocalHistory; onRemove: () => void }) {
  const progress = item.durationSeconds > 0
    ? Math.min(100, Math.round((item.watchedSeconds / item.durationSeconds) * 100))
    : item.watchedSeconds > 0 ? 5 : 0;

  const timeLabel = formatTime(item.watchedSeconds);
  const durationLabel = formatTime(item.durationSeconds);

  // Link goes to the movie page — when user lands there, the player will auto-seek to watchedSeconds
  const href = `/movie/${item.slug}`;

  return (
    <div className="history-item-wrap">
      <Link href={href} className="history-item">
        <div className="history-poster">
          <HistoryPoster item={item} />
        </div>
        <div className="history-copy">
          <strong>{item.name}</strong>
          <span className="history-episode">{item.episodeName || "Phim"}</span>
          <span className="history-meta">
            {timeLabel && durationLabel
              ? `${timeLabel} / ${durationLabel} · `
              : timeLabel
              ? `Đã xem ${timeLabel} · `
              : ""}
            {formatDate(item.lastWatchedAt)}
          </span>
          <div className="progress-track">
            <i style={{ width: `${progress}%` }} />
          </div>
        </div>
        <span className="history-play"><Play size={14} fill="currentColor" /></span>
      </Link>
      <button
        className="history-remove"
        aria-label={`Xóa ${item.name} khỏi lịch sử`}
        onClick={() => { removeHistory(item.slug, item.episodeSlug); onRemove(); }}
      >
        <Trash2 size={13} />
      </button>
    </div>
  );
}

export default function AccountPage() {
  const auth = useAuth();
  const utils = trpc.useUtils();
  const [favorites, setFavorites] = useState<LocalMovie[]>(() => listFavorites());
  const [history, setHistory] = useState<LocalHistory[]>(() => listHistory());
  const [confirmClear, setConfirmClear] = useState(false);
  const [authOpen, setAuthOpen] = useState(false);
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [accountMessage, setAccountMessage] = useState("");
  const remoteFavorites = trpc.account.favorites.useQuery(undefined, { enabled: Boolean(auth.user), staleTime: 0 });
  const remoteHistory = trpc.account.history.useQuery(undefined, { enabled: Boolean(auth.user), staleTime: 0 });
  const devices = trpc.account.devices.useQuery(undefined, { enabled: Boolean(auth.user), refetchInterval: 15_000 });
  const kickDevice = trpc.account.kickDevice.useMutation({ onSuccess: async (_result, variables) => {
    if (devices.data?.some((device) => device.id === variables.sessionId && device.current)) await utils.auth.me.invalidate();
    else await devices.refetch();
  } });
  const logoutAll = trpc.account.logoutAllDevices.useMutation({ onSuccess: async () => { setAccountMessage("Đã đăng xuất tất cả thiết bị."); await utils.auth.me.invalidate(); } });
  const changePassword = trpc.auth.changePassword.useMutation();

  useEffect(() => {
    if (remoteFavorites.data) setFavorites(remoteFavorites.data.map((item) => ({
      id: item.movieSlug, slug: item.movieSlug, name: item.movieName, originName: item.originName || "",
      poster: item.posterUrl || null, year: item.year || null, quality: "", episodeCurrent: "", rating: null, categories: [],
    })));
  }, [remoteFavorites.data]);
  useEffect(() => {
    if (remoteHistory.data) setHistory(remoteHistory.data.map((item) => ({
      id: item.movieSlug, slug: item.movieSlug, name: item.movieName, originName: item.originName || "",
      poster: item.posterUrl || null, year: item.year || null, quality: "", episodeCurrent: "", rating: null, categories: [],
      episodeSlug: item.episodeSlug || "movie", episodeName: item.episodeName || "Phim",
      watchedSeconds: item.watchedSeconds, durationSeconds: item.durationSeconds, lastWatchedAt: String(item.lastWatchedAt || new Date().toISOString()),
    })));
  }, [remoteHistory.data]);

  useEffect(() => subscribeLibrary(() => {
    setFavorites(listFavorites());
    setHistory(listHistory());
  }), []);

  function remove(slug: string) { removeFavorite(slug); setFavorites(listFavorites()); void remoteFavorites.refetch(); }
  function refresh() { setHistory(listHistory()); }

  function handleClearHistory() {
    if (confirmClear) {
      clearHistory();
      setHistory([]);
      void remoteHistory.refetch();
      setConfirmClear(false);
    } else {
      setConfirmClear(true);
      setTimeout(() => setConfirmClear(false), 4000);
    }
  }

  return (
    <PageShell>
      <main className="content-wrap inner-page account-page">
        <div className="page-topline">
          <Link href="/" className="back-link"><ArrowLeft size={15} /> Trang chủ</Link>
          <span className="result-note">{auth.user ? "Đồng bộ tài khoản" : "Lưu trên thiết bị này"}</span>
        </div>
        {!auth.user ? <section className="account-section">
          <div className="account-gate">
            <div className="account-gate-icon"><ShieldCheck size={24} /></div>
            <span className="eyebrow">CINEMORA ACCOUNT</span>
            <h1>Đồng bộ <em>thư viện</em>.</h1>
            <p>Đăng nhập bằng Gmail hoặc email và mật khẩu Cinemora để lưu lịch sử xem, tập phim, tiến độ, yêu thích và cài đặt trên tài khoản của bạn.</p>
            <button className="button button-primary" onClick={() => setAuthOpen(true)}>Đăng nhập / Đăng ký</button>
          </div>
        </section> : <>
          <section className="account-heading">
            <div className="account-heading-avatar"><ShieldCheck size={22} /></div>
            <div><span className="eyebrow">TÀI KHOẢN ĐÃ ĐỒNG BỘ</span><h1>{auth.user.name || "Thư viện của bạn"}</h1><p>{auth.user.email}</p></div>
            <button className="button button-ghost" style={{ marginLeft: "auto" }} onClick={() => { void auth.logout(); }}><LogOut size={14} /> Đăng xuất</button>
          </section>
          <section className="account-section">
            <SectionHeading eyebrow="BẢO MẬT" title="Thiết bị đăng nhập" action={<span className="result-note">{devices.data?.length ?? 0} / 5 thiết bị</span>} />
            {devices.error && <div className="auth-error">{devices.error.message}</div>}
            <div className="history-list">
              {(devices.data || []).map((device) => <div className="history-item" key={device.id}>
                <MonitorSmartphone size={20} color={device.online ? "#d2f36b" : "#777"} />
                <div className="history-copy"><strong>{device.deviceName}{device.current ? " · Thiết bị này" : ""}</strong>
                  <span>{device.deviceModel || device.platform} · {device.online ? "Online" : "Ngoại tuyến"}{device.ipAddress ? ` · IP ${device.ipAddress}` : ""}</span>
                  <span className="history-meta">Hoạt động gần nhất: {formatDate(device.lastSeenAt)}</span>
                </div>
                <button className="button button-ghost" disabled={kickDevice.isPending} onClick={() => {
                  if (window.confirm(device.current ? "Đăng xuất thiết bị hiện tại?" : `Đăng xuất ${device.deviceName}?`)) {
                    kickDevice.mutate({ sessionId: device.id });
                  }
                }}>Đăng xuất</button>
              </div>)}
            </div>
            <button className="button button-danger" style={{ marginTop: 12 }} disabled={logoutAll.isPending} onClick={() => {
              if (window.confirm("Đăng xuất tất cả thiết bị đã đăng nhập, bao gồm thiết bị hiện tại?")) logoutAll.mutate({});
            }}>Đăng xuất tất cả thiết bị</button>
            <form className="account-password-form" onSubmit={async (event) => {
              event.preventDefault(); setAccountMessage("");
              try {
                await changePassword.mutateAsync({ currentPassword, newPassword, confirmPassword, logoutAll: false });
                setCurrentPassword(""); setNewPassword(""); setConfirmPassword("");
                if (window.confirm("Đổi mật khẩu thành công. Bạn có muốn đăng xuất tất cả thiết bị, kể cả thiết bị hiện tại không?")) {
                  await logoutAll.mutateAsync({});
                  await utils.auth.me.invalidate();
                } else setAccountMessage("Đổi mật khẩu thành công. Tất cả thiết bị vẫn giữ phiên đăng nhập.");
              } catch (error) { setAccountMessage(error instanceof Error ? error.message : "Không thể đổi mật khẩu."); }
            }}>
              <strong>Đổi mật khẩu</strong>
              <input required type="password" autoComplete="current-password" placeholder="Mật khẩu cũ" value={currentPassword} onChange={(e) => setCurrentPassword(e.target.value)} />
              <input required minLength={8} maxLength={128} type="password" autoComplete="new-password" placeholder="Mật khẩu mới (ít nhất 8 ký tự)" value={newPassword} onChange={(e) => setNewPassword(e.target.value)} />
              <input required minLength={8} maxLength={128} type="password" autoComplete="new-password" placeholder="Nhập lại mật khẩu mới" value={confirmPassword} onChange={(e) => setConfirmPassword(e.target.value)} />
              {accountMessage && <span className="auth-hint">{accountMessage}</span>}
              <button className="button button-primary" disabled={changePassword.isPending}>Cập nhật mật khẩu</button>
            </form>
          </section>
        </>}
        <section className="account-heading">
          <div className="account-heading-avatar"><Heart size={22} /></div>
          <div>
            <span className="eyebrow">{auth.user ? "CINEMORA CLOUD" : "LOCAL CINEMORA"}</span>
            <h1>Thư viện của bạn</h1>
            <p>{auth.user ? "Lịch sử, tập đang xem, tiến độ và yêu thích được đồng bộ trong tài khoản." : "Yêu thích và lịch sử xem được lưu trực tiếp trên trình duyệt này."}</p>
          </div>
        </section>

        {/* History section */}
        <section className="account-section">
          <SectionHeading
            eyebrow="XEM TIẾP"
            title="Bạn đang xem dở"
            action={
              <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                <span className="live-sync"><span /> {auth.user ? "Đã đồng bộ" : "Đã lưu cục bộ"}</span>
                {history.length > 0 && (
                  <button
                    className={`button ${confirmClear ? "button-danger" : "button-ghost"}`}
                    style={{ fontSize: 12, minHeight: 30, padding: "0 10px", gap: 5 }}
                    onClick={handleClearHistory}
                  >
                    <Trash2 size={13} />
                    {confirmClear ? "Xác nhận xóa tất cả?" : "Xóa lịch sử"}
                  </button>
                )}
              </div>
            }
          />
          {history.length ? (
            <div className="history-list">
              {history.slice(0, 20).map((item) => (
                <HistoryItem
                  key={`${item.slug}-${item.episodeSlug}`}
                  item={item}
                  onRemove={refresh}
                />
              ))}
            </div>
          ) : (
            <div className="account-empty">
              <Clock3 size={20} />
              <span>Chưa có lịch sử xem. Chọn một bộ phim để bắt đầu.</span>
            </div>
          )}
        </section>

        {/* Favorites section */}
        <section className="account-section">
          <SectionHeading
            eyebrow="ĐÃ LƯU"
            title="Phim yêu thích"
            action={<span className="result-note">{favorites.length} phim</span>}
          />
          {favorites.length ? (
            <div className="movie-grid">
              {favorites.map((movie, index) => (
                <div className="favorite-card-wrap" key={movie.slug}>
                  <MovieCard movie={movie} index={index} />
                  <button className="remove-favorite" onClick={() => remove(movie.slug)} aria-label={`Xóa ${movie.name} khỏi yêu thích`}>
                    <Trash2 size={13} />
                  </button>
                </div>
              ))}
            </div>
          ) : (
            <div className="account-empty">
              <Heart size={20} />
              <span>Chưa có phim yêu thích. Nhấn "Yêu thích" ở trang phim để lưu lại.</span>
            </div>
          )}
        </section>
      </main>
      <AuthDialog open={authOpen} onClose={() => setAuthOpen(false)} />
    </PageShell>
  );
}
