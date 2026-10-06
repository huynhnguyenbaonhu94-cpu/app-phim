import { ArrowLeft, Clock3, Heart, Play, Trash2 } from "lucide-react";
import { Link } from "wouter";
import { MovieCard, PageShell, SectionHeading } from "@/components/CinemaChrome";
import { clearHistory, listFavorites, listHistory, removeFavorite, removeHistory, subscribeLibrary, updateHistoryPoster, type LocalHistory, type LocalMovie } from "@/lib/localLibrary";
import { trpc } from "@/lib/trpc";
import { useEffect, useRef, useState } from "react";

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
  const [favorites, setFavorites] = useState<LocalMovie[]>(() => listFavorites());
  const [history, setHistory] = useState<LocalHistory[]>(() => listHistory());
  const [confirmClear, setConfirmClear] = useState(false);

  useEffect(() => subscribeLibrary(() => {
    setFavorites(listFavorites());
    setHistory(listHistory());
  }), []);

  function remove(slug: string) { removeFavorite(slug); setFavorites(listFavorites()); }
  function refresh() { setHistory(listHistory()); }

  function handleClearHistory() {
    if (confirmClear) {
      clearHistory();
      setHistory([]);
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
          <span className="result-note">Lưu trên thiết bị này</span>
        </div>
        <section className="account-heading">
          <div className="account-heading-avatar"><Heart size={22} /></div>
          <div>
            <span className="eyebrow">LOCAL CINEMORA</span>
            <h1>Thư viện của bạn</h1>
            <p>Yêu thích và lịch sử xem được lưu trực tiếp trên trình duyệt này.</p>
          </div>
        </section>

        {/* History section */}
        <section className="account-section">
          <SectionHeading
            eyebrow="XEM TIẾP"
            title="Bạn đang xem dở"
            action={
              <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                <span className="live-sync"><span /> Đã lưu cục bộ</span>
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
    </PageShell>
  );
}
