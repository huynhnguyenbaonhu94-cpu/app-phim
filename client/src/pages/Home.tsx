import { ArrowLeft, ArrowRight, ChevronLeft, ChevronRight, Film, Filter, Play, RefreshCw, Shield, Star, Zap } from "lucide-react";
import { Link, useLocation, useSearch } from "wouter";
import { PageShell, MovieCard, SectionHeading, SkeletonCard } from "@/components/CinemaChrome";
import type { MovieCardMovie } from "@/components/CinemaChrome";
import { SearchableSelect } from "@/components/SearchableSelect";
import { trpc } from "@/lib/trpc";
import { keepPreviousData } from "@tanstack/react-query";
import { startTransition, useState, useRef, useEffect } from "react";

function Hero({ movie }: { movie: any }) {
  return <section className="hero">
    <div className="hero-backdrop" style={movie?.backdrop ? { backgroundImage: `url(${movie.backdrop})` } : undefined} />
    <div className="hero-gradient" />
    <div className="hero-content">
      <span className="hero-kicker"><span className="live-dot" /> CINEMORA PREMIERE</span>
      <h1>{movie?.name || "Điện ảnh, theo cách của bạn."}</h1>
      <p className="hero-origin">{movie?.originName || "Discover your next favorite story"}</p>
      <p className="hero-description">{movie?.description || "Khám phá những bộ phim đáng nhớ, được tuyển chọn để bạn luôn có một điều tuyệt vời tiếp theo để xem."}</p>
      <div className="hero-tags"><span>{movie?.year || "2026"}</span><span>{movie?.quality || "FHD"}</span><span>{movie?.episodeCurrent || "Full"}</span><span>{movie?.lang || "Vietsub"}</span></div>
      <div className="hero-actions"><Link className="button button-primary" href={movie?.slug ? `/movie/${movie.slug}` : "/catalog/latest"}><Play size={17} fill="currentColor" /> Xem ngay</Link><Link className="button button-ghost" href={movie?.slug ? `/movie/${movie.slug}` : "/catalog/latest"}>Xem chi tiết <ArrowRight size={16} /></Link></div>
    </div>
    <div className="hero-spotlight"><div className="spotlight-ring"><Star size={16} fill="currentColor" /><strong>{movie?.rating || "8.7"}</strong></div><span>Điểm đánh giá</span></div>
    <div className="hero-scroll">Cuộn để khám phá <ChevronRight size={14} /></div>
  </section>;
}

function FeatureStrip() {
  return (
    <section className="feature-strip">
      <div className="feature-strip-intro">
        <span className="feature-strip-label">TRẢI NGHIỆM CINEMORA</span>
        <strong>Mọi điều bạn cần cho một buổi xem phim trọn vẹn.</strong>
      </div>
      <div className="feature-strip-item">
        <span className="feature-strip-number">01</span>
        <div className="feature-strip-icon"><Shield size={22} /></div>
        <div className="feature-strip-copy">
          <strong>Kho phim khổng lồ</strong>
          <span>Hàng nghìn bộ phim tuyển chọn, đủ mọi thể loại</span>
        </div>
      </div>
      <div className="feature-strip-item">
        <span className="feature-strip-number">02</span>
        <div className="feature-strip-icon"><RefreshCw size={22} /></div>
        <div className="feature-strip-copy">
          <strong>Cập nhật liên tục</strong>
          <span>Phim mới nhất được thêm vào mỗi ngày</span>
        </div>
      </div>
      <div className="feature-strip-item">
        <span className="feature-strip-number">03</span>
        <div className="feature-strip-icon"><Zap size={22} /></div>
        <div className="feature-strip-copy">
          <strong>Xem mượt mà</strong>
          <span>Tốc độ tải nhanh, không quảng cáo làm phiền</span>
        </div>
      </div>
    </section>
  );
}

// ── Poster image với retry logic ──────────────────────────────────
function DailyPoster({ src, alt }: { src: string; alt: string }) {
  const [failed, setFailed] = useState(false);
  const retries = useRef(0);
  if (failed) return (
    <div className="daily-poster-fallback">
      <Film size={22} />
      <span>Cinemora</span>
    </div>
  );
  return (
    <img
      src={src}
      alt={alt}
      loading="lazy"
      onError={() => {
        if (retries.current === 0) {
          retries.current = 1;
          setTimeout(() => {
            const el = document.querySelector(`img[alt="${alt}"]`) as HTMLImageElement | null;
            if (el) el.src = `${src.split("?")[0]}?r=1`;
          }, 800);
        } else {
          setFailed(true);
        }
      }}
    />
  );
}

// ── Daily Updates section ──────────────────────────────────────────
function DailyUpdates() {
  const scrollRef = useRef<HTMLDivElement>(null);
  const [canScrollLeft, setCanScrollLeft] = useState(false);
  const [canScrollRight, setCanScrollRight] = useState(true);

  const queryBehavior = { refetchOnWindowFocus: false, refetchOnReconnect: false, retry: 1 } as const;
  const dailyQuery = trpc.cinema.dailyUpdates.useQuery(
    { page: 1 },
    { ...queryBehavior, staleTime: 180_000, refetchInterval: 180_000 }
  );

  const movies: MovieCardMovie[] = dailyQuery.data?.items || [];

  function updateScrollState() {
    const el = scrollRef.current;
    if (!el) return;
    setCanScrollLeft(el.scrollLeft > 8);
    setCanScrollRight(el.scrollLeft + el.clientWidth < el.scrollWidth - 8);
  }

  useEffect(() => {
    const frame = requestAnimationFrame(updateScrollState);
    const handleResize = () => updateScrollState();
    window.addEventListener("resize", handleResize);
    return () => {
      cancelAnimationFrame(frame);
      window.removeEventListener("resize", handleResize);
    };
  }, [movies.length]);

  function scrollBy(dir: "left" | "right") {
    const el = scrollRef.current;
    if (!el) return;
    // scroll 3 cards mỗi lần bấm
    const cardWidth = 150 + 14; // card width + gap
    el.scrollBy({ left: dir === "right" ? cardWidth * 3 : -cardWidth * 3, behavior: "smooth" });
  }

  return (
    <section className="daily-section">
      <div className="daily-header">
        <SectionHeading
          eyebrow="HÔM NAY"
          title="Phim mới cập nhật"
          action={
            <Link className="section-link" href="/catalog/latest">
              Xem tất cả <ArrowRight size={15} />
            </Link>
          }
        />
        <span className="daily-live-badge">
          <span className="daily-live-dot" />
          Live
        </span>
      </div>

      <div className="daily-scroll-wrap">
        {/* Nút trái */}
        <button
          type="button"
          className={`daily-nav daily-nav-left${canScrollLeft ? " visible" : ""}`}
          onClick={() => scrollBy("left")}
          aria-label="Cuộn trái"
        >
          <ChevronLeft size={19} strokeWidth={1.8} />
        </button>

        <div
          className="daily-scroll"
          ref={scrollRef}
          onScroll={updateScrollState}
        >
          {dailyQuery.isLoading
            ? Array.from({ length: 8 }).map((_, i) => (
                <div key={i} className="daily-skeleton">
                  <div className="skeleton skeleton-poster daily-skeleton-poster" />
                  <div className="skeleton skeleton-line daily-skeleton-line" />
                  <div className="skeleton skeleton-line daily-skeleton-line short" />
                </div>
              ))
            : movies.map((movie) => (
                <Link
                  key={movie.id}
                  href={`/movie/${movie.slug}`}
                  className="daily-card"
                >
                  <div className="daily-poster">
                    {movie.poster
                      ? <DailyPoster src={movie.poster} alt={movie.name} />
                      : <div className="daily-poster-fallback"><Film size={22} /><span>Cinemora</span></div>
                    }
                    <div className="daily-poster-shade" />
                    <span className="daily-ep-pill">{movie.episodeCurrent || "Mới"}</span>
                    <span className="daily-quality-pill">{movie.quality || "HD"}</span>
                    <div className="daily-play-hover">
                      <div className="daily-play-icon">
                        <Play size={14} fill="currentColor" />
                      </div>
                    </div>
                  </div>
                  <div className="daily-info">
                    <h4>{movie.name}</h4>
                    <p>{movie.originName || movie.categories?.[0]?.name || "Cinemora"}</p>
                  </div>
                </Link>
              ))}
        </div>

        {/* Nút phải */}
        <button
          type="button"
          className={`daily-nav daily-nav-right${canScrollRight ? " visible" : ""}`}
          onClick={() => scrollBy("right")}
          aria-label="Cuộn phải"
        >
          <ChevronRight size={19} strokeWidth={1.8} />
        </button>
      </div>
    </section>
  );
}

export default function Home() {
  const [, navigate] = useLocation();
  const search = useSearch();
  const [homeCategory, setHomeCategory] = useState("");
  const [categoryPage, setCategoryPage] = useState(1);
  const page = Math.max(1, Number(new URLSearchParams(search).get("page") || "1"));
  const queryBehavior = { refetchOnWindowFocus: false, refetchOnReconnect: false, retry: 1 } as const;
  const homeQuery = trpc.cinema.home.useQuery({ page }, { ...queryBehavior, staleTime: 120_000, placeholderData: keepPreviousData });
  const categoryQuery = trpc.cinema.list.useQuery({ kind: "latest", page: categoryPage, category: homeCategory || undefined }, { ...queryBehavior, enabled: Boolean(homeCategory), staleTime: 120_000, placeholderData: keepPreviousData });
  const metaQuery = trpc.cinema.meta.useQuery(undefined, { ...queryBehavior, staleTime: 300_000 });
  const homeMovies: MovieCardMovie[] = homeQuery.data?.items || [];
  const heroMovie = homeMovies[0];
  const libraryQuery = homeCategory ? categoryQuery : homeQuery;
  const libraryMovies: MovieCardMovie[] = ((homeCategory ? categoryQuery.data?.items : homeMovies) || []) as MovieCardMovie[];
  const libraryPage = homeCategory ? categoryPage : page;
  const libraryTotalPages = Number(libraryQuery.data?.pagination?.totalPages || 1);
  const pageWindowSize = 6;
  const pageWindowStart = Math.floor((libraryPage - 1) / pageWindowSize) * pageWindowSize + 1;
  const pageWindowEnd = Math.min(libraryTotalPages, pageWindowStart + pageWindowSize - 1);
  function changeHomePage(nextPage: number) {
    if (homeCategory) {
      setCategoryPage(nextPage);
      return;
    }
    startTransition(() => navigate(nextPage > 1 ? `/?page=${nextPage}` : "/"));
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  return <PageShell>
    <main>
      <Hero movie={heroMovie} />
      <div className="content-wrap">
        <FeatureStrip />
        <DailyUpdates />
        <section className="home-categories"><SectionHeading eyebrow="DANH MỤC" title="Khám phá theo thể loại" action={<Link className="section-link" href="/catalog/categories">Tất cả thể loại <ArrowRight size={15} /></Link>} /><div className="filter-row home-category-filter"><div className="filter-label"><Filter size={14} /> Lọc nhanh</div><SearchableSelect value={homeCategory} onChange={(value) => { setHomeCategory(value); setCategoryPage(1); }} placeholder="Tất cả thể loại" searchPlaceholder="Tìm thể loại..." ariaLabel="Lọc thể loại trên trang chủ" options={(metaQuery.data?.categories || []).map((item: { name: string; slug: string }) => ({ value: item.slug, label: item.name }))} /></div></section>
        <section className="movie-section home-library"><SectionHeading eyebrow={homeCategory ? "KẾT QUẢ LỌC TRÊN TRANG CHỦ" : "PHIM TRÊN CINEMORA"} title={homeCategory ? (metaQuery.data?.categories || []).find((item: { name: string; slug: string }) => item.slug === homeCategory)?.name || "Phim đã lọc" : "Tất cả phim mới cập nhật"} /><div className={`movie-grid ${libraryQuery.isFetching ? "is-refreshing" : ""}`}>{libraryQuery.isLoading ? Array.from({ length: 24 }).map((_, i) => <SkeletonCard key={i} />) : libraryMovies.map((movie, i) => <MovieCard key={movie.id} movie={movie} index={i} />)}</div>{libraryTotalPages > 1 && <div className="pagination home-pagination"><button className="pagination-button" aria-label="Trang trước" disabled={libraryPage <= 1} onClick={() => changeHomePage(libraryPage - 1)}><ArrowLeft size={15} /></button>{Array.from({ length: pageWindowEnd - pageWindowStart + 1 }, (_, i) => pageWindowStart + i).map((itemPage) => <button key={itemPage} aria-label={`Trang ${itemPage}`} className={`pagination-num${itemPage === libraryPage ? " active" : ""}`} onClick={() => itemPage !== libraryPage && changeHomePage(itemPage)}>{itemPage}</button>)}<button className="pagination-button" aria-label="Trang sau" disabled={libraryPage >= libraryTotalPages} onClick={() => changeHomePage(libraryPage + 1)}><ArrowRight size={15} /></button></div>}</section>
      </div>
    </main>
  </PageShell>;
}
