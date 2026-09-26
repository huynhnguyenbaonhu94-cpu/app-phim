import { ArrowLeft, Check, ChevronLeft, ChevronRight, Clock3, ExternalLink, Film, Heart, Info, Play, ShieldCheck, Star, Users, Eye, CalendarDays, Globe2, Clapperboard } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { Link, useLocation } from "wouter";
import { CinemaPlayer } from "@/components/CinemaPlayer";
import { PageShell, SkeletonCard } from "@/components/CinemaChrome";
import { trpc } from "@/lib/trpc";
import { isFavorite, listHistory, saveHistory, toggleFavorite } from "@/lib/localLibrary";

type Episode = { name: string; slug: string; filename: string; embedUrl: string | null; streamUrl: string | null };
type MovieDetail = { slug: string; name: string; originName: string; poster: string | null; backdrop: string | null; year: number | null; quality: string; episodeCurrent: string; episodeTotal: number | null; time: string; lang: string; type: string; description: string; rating: number | null; categories: Array<{ name: string; slug: string }>; countries: Array<{ name: string; slug: string }>; alternativeNames: string[]; actors: string[]; actorProfiles?: Array<{ name: string; image: string | null }>; directors: string[]; status: string; views: number | null; isCopyright: boolean; isTheatrical: boolean; trailerUrl: string | null; tmdbId: string | null; imdbId: string | null; createdAt: string | null; updatedAt: string | null; servers: Array<{ name: string; isAi: boolean; episodes: Episode[] }> };

function displayDate(value: string | null) { return value ? new Date(value).toLocaleDateString("vi-VN") : "Đang cập nhật"; }

type ActorProfile = { name: string; image: string | null };
function ActorGallery({ actors }: { actors: ActorProfile[] }) {
  const trackRef = useRef<HTMLDivElement>(null);
  const [canLeft, setCanLeft] = useState(false);
  const [canRight, setCanRight] = useState(false);
  const dragRef = useRef({ dragging: false, startX: 0, scrollLeft: 0 });

  const checkScroll = useCallback(() => {
    const el = trackRef.current;
    if (!el) return;
    const scrollable = el.scrollWidth - el.clientWidth;
    setCanLeft(el.scrollLeft > 2);
    setCanRight(scrollable > 2 && el.scrollLeft < scrollable - 2);
  }, []);

  useEffect(() => {
    const el = trackRef.current;
    if (!el) return;
    // Chạy nhiều lần để bắt được khi ảnh load xong
    const timers = [100, 300, 600, 1200].map(ms => setTimeout(checkScroll, ms));
    el.addEventListener("scroll", checkScroll, { passive: true });
    const ro = new ResizeObserver(checkScroll);
    ro.observe(el);
    // Recheck mỗi khi 1 ảnh load xong
    const imgs = el.querySelectorAll("img");
    imgs.forEach(img => {
      if (img.complete) { checkScroll(); }
      else { img.addEventListener("load", checkScroll, { once: true }); }
    });
    return () => {
      timers.forEach(clearTimeout);
      el.removeEventListener("scroll", checkScroll);
      ro.disconnect();
    };
  }, [checkScroll, actors]);

  const scroll = (dir: "left" | "right") => {
    const el = trackRef.current;
    if (!el) return;
    el.scrollBy({ left: dir === "left" ? -180 : 180, behavior: "smooth" });
  };

  // Mouse drag to scroll
  const onMouseDown = (e: React.MouseEvent) => {
    const el = trackRef.current;
    if (!el) return;
    dragRef.current = { dragging: true, startX: e.pageX - el.offsetLeft, scrollLeft: el.scrollLeft };
    el.style.cursor = "grabbing";
    e.preventDefault();
  };
  const onMouseMove = (e: React.MouseEvent) => {
    const el = trackRef.current;
    if (!el || !dragRef.current.dragging) return;
    const x = e.pageX - el.offsetLeft;
    el.scrollLeft = dragRef.current.scrollLeft - (x - dragRef.current.startX);
  };
  const onMouseUp = () => {
    dragRef.current.dragging = false;
    if (trackRef.current) trackRef.current.style.cursor = "grab";
  };

  return (
    <div className="actor-section">
      <div
        className="actor-gallery"
        ref={trackRef}
        onMouseDown={onMouseDown}
        onMouseMove={onMouseMove}
        onMouseUp={onMouseUp}
        onMouseLeave={onMouseUp}
      >
        {actors.map((actor) =>
          actor.image ? (
            <div className="actor-card" key={actor.name}>
              <img src={actor.image} alt={actor.name} loading="lazy" draggable={false} />
              <b>{actor.name}</b>
            </div>
          ) : (
            <b className="actor-name-only" key={actor.name}>{actor.name}</b>
          )
        )}
      </div>
      <div className="actor-nav-row">
        <button className="actor-nav" onClick={() => scroll("left")} aria-label="Cuộn trái" disabled={!canLeft}>
          <ChevronLeft size={13} />
        </button>
        <button className="actor-nav" onClick={() => scroll("right")} aria-label="Cuộn phải" disabled={!canRight}>
          <ChevronRight size={13} />
        </button>
      </div>
    </div>
  );
}

function apiValue(value: unknown, fallback = "Đang cập nhật") {
  if (Array.isArray(value)) return value.length ? value.join(", ") : fallback;
  if (typeof value === "number") return Number.isFinite(value) ? value.toLocaleString("vi-VN") : fallback;
  if (typeof value === "string" && value.trim()) return value;
  return fallback;
}

function MovieMetadata({ movie }: { movie: MovieDetail }) {
  const categories = movie.categories?.map((item) => item.name).filter(Boolean).join(", ");
  const countries = movie.countries?.map((item) => item.name).filter(Boolean).join(", ");
  const actors = movie.actors?.length ? movie.actors : movie.actorProfiles?.map((actor) => actor.name) || [];
  const episode = movie.episodeTotal ? `${apiValue(movie.episodeCurrent)} / ${movie.episodeTotal}` : apiValue(movie.episodeCurrent);
  return <section className="detail-api-metadata" aria-label="Thông tin phim từ API">
    <div className="detail-api-heading"><span className="eyebrow">DỮ LIỆU TỪ PHIMAPI</span><strong>Thông tin phim</strong></div>
    <div className="detail-api-grid">
      <div><span>Diễn viên</span><strong>{apiValue(actors)}</strong></div>
      <div><span>Đạo diễn</span><strong>{apiValue(movie.directors)}</strong></div>
      <div><span>Thể loại</span><strong>{apiValue(categories)}</strong></div>
      <div><span>Quốc gia</span><strong>{apiValue(countries)}</strong></div>
      <div><span>Đánh giá</span><strong>{movie.rating ? `${movie.rating} / 10` : "Chưa có đánh giá"}</strong></div>
      <div><span>Lượt xem</span><strong>{apiValue(movie.views)}</strong></div>
      <div><span>Cập nhật</span><strong>{displayDate(movie.updatedAt)}</strong></div>
      <div><span>Tập hiện tại</span><strong>{episode}</strong></div>
      <div><span>Ngày tạo</span><strong>{displayDate(movie.createdAt)}</strong></div>
      <div><span>TMDB</span><strong>{apiValue(movie.tmdbId)}</strong></div>
      <div><span>IMDb</span><strong>{apiValue(movie.imdbId)}</strong></div>
    </div>
  </section>;
}

export default function DetailPage({ slug }: { slug: string }) {
  const [, navigate] = useLocation();
  const query = trpc.cinema.detail.useQuery({ slug }, { staleTime: 60_000 });
  const movie = query.data as MovieDetail | undefined;
  const [serverIndex, setServerIndex] = useState(0);
  const [episodeIndex, setEpisodeIndex] = useState(0);
  const [favorite, setFavorite] = useState(() => isFavorite(slug));
  const [adLocked, setAdLocked] = useState(false);
  const [autoNext, setAutoNext] = useState(() => {
    try { return localStorage.getItem("cinemora_autonext") !== "off"; } catch { return true; }
  });

  useEffect(() => { setServerIndex(0); setEpisodeIndex(0); }, [slug]);
  useEffect(() => { setFavorite(isFavorite(slug)); }, [slug]);
  useEffect(() => { setAdLocked(false); }, [slug]);

  const server = movie?.servers?.[serverIndex];
  const episode = server?.episodes?.[episodeIndex];
  const canPlayEpisode = Boolean(episode?.streamUrl || episode?.embedUrl);

  // Look up saved progress for this episode
  const savedProgress = episode
    ? listHistory().find((h) => h.slug === slug && h.episodeSlug === episode.slug)
    : undefined;
  const startAt = savedProgress && savedProgress.watchedSeconds > 10 ? savedProgress.watchedSeconds : undefined;

  // onProgress callback - receives real currentTime & duration from the player
  const handleProgress = useCallback((currentTime: number, duration: number) => {
    if (!movie || !episode) return;
    saveHistory({
      id: movie.slug,
      slug: movie.slug,
      name: movie.name,
      originName: movie.originName,
      poster: movie.poster,
      year: movie.year,
      quality: movie.quality,
      episodeCurrent: movie.episodeCurrent,
      rating: movie.rating,
      categories: movie.categories,
      episodeSlug: episode.slug,
      episodeName: episode.name,
      watchedSeconds: Math.floor(currentTime),
      durationSeconds: Math.floor(duration),
    });
  }, [episode, movie]);

  // Save initial history entry when episode changes
  useEffect(() => {
    if (!movie || !episode) return;
    saveHistory({
      id: movie.slug,
      slug: movie.slug,
      name: movie.name,
      originName: movie.originName,
      poster: movie.poster,
      year: movie.year,
      quality: movie.quality,
      episodeCurrent: movie.episodeCurrent,
      rating: movie.rating,
      categories: movie.categories,
      episodeSlug: episode.slug,
      episodeName: episode.name,
      watchedSeconds: savedProgress?.watchedSeconds ?? 0,
      durationSeconds: savedProgress?.durationSeconds ?? 0,
    });
  // Only run when episode changes, not on every savedProgress update
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [episode?.slug, movie?.slug]);

  function selectEpisode(nextServerIndex: number, nextEpisodeIndex: number) {
    if (adLocked) return;
    setServerIndex(nextServerIndex);
    setEpisodeIndex(nextEpisodeIndex);
    window.setTimeout(() => document.getElementById("watch")?.scrollIntoView({ behavior: "smooth", block: "start" }), 0);
  }

  // Tính tập tiếp theo trong cùng server
  const nextEpisode = server?.episodes?.[episodeIndex + 1];
  const nextEpisodeLabel = nextEpisode?.name;

  function handleNextEpisode() {
    if (adLocked) return;
    if (!nextEpisode) return;
    selectEpisode(serverIndex, episodeIndex + 1);
  }

  // handleEnded is intentionally a no-op: CinemaPlayer handles the
  // auto-next countdown internally via its own "ended" listener and
  // will call onNextEpisode() after the countdown. If we also called
  // handleNextEpisode() here we'd get a double-trigger (skip 2 eps).
  function handleEnded() {
    // nothing — let the player's countdown drive navigation
  }

  function toggleAutoNext() {
    setAutoNext((v) => {
      const next = !v;
      try { localStorage.setItem("cinemora_autonext", next ? "on" : "off"); } catch {}
      return next;
    });
  }

  function handleFavorite() {
    if (!movie) return;
    setFavorite(toggleFavorite({ id: movie.slug, slug: movie.slug, name: movie.name, originName: movie.originName, poster: movie.poster, year: movie.year, quality: movie.quality, episodeCurrent: movie.episodeCurrent, rating: movie.rating, categories: movie.categories }));
  }

  if (query.isLoading) return <PageShell><main className="content-wrap inner-page detail-loading"><div className="detail-backdrop-skeleton skeleton" /><div className="detail-loading-grid"><SkeletonCard /><div><div className="skeleton skeleton-line wide" /><div className="skeleton skeleton-line" /><div className="skeleton skeleton-line wide" /></div></div></main></PageShell>;
  if (query.isError || !movie) return <PageShell><main className="content-wrap inner-page"><div className="empty-state"><Info size={30} /><h3>Không tìm thấy bộ phim</h3><p>Bộ phim có thể đã được cập nhật hoặc tạm thời không khả dụng.</p><button className="button button-primary" onClick={() => navigate("/")}><ArrowLeft size={16} /> Về trang chủ</button></div></main></PageShell>;

  const totalEpisodes = movie.servers.reduce((total, item) => total + item.episodes.length, 0);

  return <PageShell><main className="detail-page"><section className="detail-hero"><div className="detail-backdrop" style={movie.backdrop ? { backgroundImage: `url(${movie.backdrop})` } : undefined} /><div className="detail-overlay" /><div className="detail-inner content-wrap"><Link href="/" className="back-link detail-back"><ArrowLeft size={15} /> Trở về khám phá</Link><div className="detail-copy"><div className="detail-poster">{movie.poster ? <img src={movie.poster} alt={movie.name} /> : <Film size={40} />}</div><div className="detail-info"><span className="hero-kicker">CINEMORA FEATURE</span><h1>{movie.name}</h1><p className="detail-origin">{movie.originName}</p><div className="hero-tags"><span>{movie.year || "—"}</span><span>{movie.quality}</span><span>{movie.lang}</span><span>{movie.time || "Full"}</span><span>{movie.status || "Đang cập nhật"}</span>{movie.isTheatrical && <span>Chiếu rạp</span>}</div><p className="detail-description">{movie.description}</p><div className="detail-actions">{canPlayEpisode ? <a className="button button-primary" href="#watch"><Play size={16} fill="currentColor" /> Xem ngay</a> : <span className="button button-muted"><Clock3 size={16} /> Chưa có nguồn phát</span>}<button className={`button ${favorite ? "button-favorite-active" : "button-ghost"}`} onClick={handleFavorite}><Heart size={16} fill={favorite ? "currentColor" : "none"} /> {favorite ? "Đã yêu thích" : "Yêu thích"}</button>{movie.trailerUrl && <a className="button button-ghost" href={movie.trailerUrl} target="_blank" rel="noreferrer"><ExternalLink size={15} /> Trailer</a>}</div><span className="auth-hint">Yêu thích và lịch sử được lưu trên thiết bị này.</span><MovieMetadata movie={movie} /></div></div></div></section>
    <section className="content-wrap detail-body"><div className="detail-main"><div id="watch" className="watch-card">{canPlayEpisode ? <CinemaPlayer streamUrl={episode?.streamUrl || undefined} fallbackEmbedUrl={episode?.embedUrl || undefined} title={`${movie.name} - ${episode?.name || "Tập phim"}`} posterUrl={movie.poster || undefined} startAt={startAt} onProgress={handleProgress} onEnded={handleEnded} onAdStateChange={setAdLocked} onNextEpisode={nextEpisode ? handleNextEpisode : undefined} nextEpisodeLabel={nextEpisodeLabel} autoNextEnabled={autoNext} onAutoNextToggle={toggleAutoNext} /> : <div className="player-empty"><Play size={32} /><strong>Nguồn phim đang được cập nhật</strong><span>Hãy quay lại sau nhé.</span></div>}</div>{movie.servers.length > 0 && <div className="episode-panel"><div className="episode-head"><div><span className="eyebrow">CHỌN TẬP</span><h2>Tất cả tập phim</h2></div><span>{totalEpisodes} tập · {movie.servers.length} nguồn</span></div>{movie.servers.map((serverItem, currentServerIndex) => {
          return <div className="episode-server" key={`${serverItem.name}-${currentServerIndex}`}>
            <div className="episode-server-heading"><strong>{serverItem.name}</strong>{serverItem.isAi && <span>AI Vietsub</span>}</div>
            <div className="episode-list">{serverItem.episodes.map((item, idx) => <button disabled={adLocked} key={`${item.slug}-${idx}`} className={`${currentServerIndex === serverIndex && idx === episodeIndex ? "active" : ""}${adLocked ? " ad-locked" : ""}`} onClick={() => selectEpisode(currentServerIndex, idx)}><span>{currentServerIndex === serverIndex && idx === episodeIndex ? <Check size={13} /> : null}</span>{item.name}</button>)}</div>
          </div>;
        })}</div>}
        <section className="movie-about aside-card" aria-labelledby="movie-about-title"><div className="movie-about-heading"><span className="eyebrow">NỘI DUNG</span><h2 id="movie-about-title">Về bộ phim</h2></div><p>{movie.description || "Nội dung phim đang được cập nhật."}</p></section>
      </div>
      <aside className="detail-aside"><div className="aside-card"><span className="eyebrow">THÔNG TIN PHIM</span><div className="fact-list"><div className="fact-actor-row"><Users size={16} /><span>Diễn viên</span></div>{movie.actorProfiles?.some((actor) => actor.image) ? <ActorGallery actors={movie.actorProfiles} /> : <div className="fact-actor-names"><strong>{movie.actors?.length ? movie.actors.join(", ") : (movie.actorProfiles?.map((actor) => actor.name).join(", ") || "Đang cập nhật")}</strong></div>}<div><Clapperboard size={16} /><span>Đạo diễn<strong>{movie.directors?.length ? movie.directors.join(", ") : "Đang cập nhật"}</strong></span></div><div><Film size={16} /><span>Thể loại<strong className="fact-links">{movie.categories?.length ? movie.categories.map((item) => <Link key={item.slug} href={`/catalog/categories?category=${encodeURIComponent(item.slug)}`}>{item.name}</Link>) : "Đang cập nhật"}</strong></span></div><div><Globe2 size={16} /><span>Quốc gia<strong className="fact-links">{movie.countries?.length ? movie.countries.map((item) => <Link key={item.slug} href={`/catalog/countries?country=${encodeURIComponent(item.slug)}`}>{item.name}</Link>) : "Đang cập nhật"}</strong></span></div><div><Star size={16} /><span>Đánh giá<strong>{movie.rating ? `${movie.rating} / 10` : "Chưa có đánh giá"}</strong></span></div><div><Eye size={16} /><span>Lượt xem<strong>{movie.views?.toLocaleString("vi-VN") || "Đang cập nhật"}</strong></span></div><div><CalendarDays size={16} /><span>Cập nhật<strong>{displayDate(movie.updatedAt)}</strong></span></div><div><Film size={16} /><span>Tập hiện tại<strong>{movie.episodeCurrent}{movie.episodeTotal ? ` / ${movie.episodeTotal}` : ""}</strong></span></div><div><CalendarDays size={16} /><span>Ngày tạo<strong>{displayDate(movie.createdAt)}</strong></span></div><div><Clapperboard size={16} /><span>TMDB<strong>{movie.tmdbId || "Đang cập nhật"}</strong></span></div><div><Clapperboard size={16} /><span>IMDb<strong>{movie.imdbId || "Đang cập nhật"}</strong></span></div></div></div><div className="aside-card detail-extra"><span className="eyebrow">THÔNG TIN BỔ SUNG</span><dl><dt>Tên khác</dt><dd>{movie.alternativeNames.length ? movie.alternativeNames.join(" · ") : "Không có"}</dd><dt>Loại</dt><dd>{movie.type || "Đang cập nhật"}</dd><dt>Tập hiện tại</dt><dd>{movie.episodeCurrent} / {movie.episodeTotal || "?"}</dd><dt>Nguồn dữ liệu</dt><dd>PhimAPI</dd></dl></div><div className="aside-card aside-note"><ShieldCheck size={18} /><div><strong>{movie.isCopyright ? "Nội dung có bản quyền" : "Không gian xem an tâm"}</strong><p>Cinemora hiển thị dữ liệu phim từ API và bảo vệ nguồn ảnh/video qua proxy.</p></div></div></aside></section>
  </main></PageShell>;
}
