import { Film, Heart, Home, Layers, List, Menu, MonitorPlay, Play, Search, Star, TvMinimal, X } from "lucide-react";
import { FormEvent, ReactNode, useEffect, useRef, useState } from "react";
import { Link, useLocation } from "wouter";
import { trpc } from "@/lib/trpc";
import { CINEMORA_LOGO_URL } from "@/const";

export function SiteHeader() {
  const [location, navigate] = useLocation();
  const [value, setValue] = useState(location.startsWith("/search") ? new URLSearchParams(window.location.search).get("q") || "" : "");
  const [menuOpen, setMenuOpen] = useState(false);
  const [desktopMenuOpen, setDesktopMenuOpen] = useState(false);
  const [mobileSearchOpen, setMobileSearchOpen] = useState(false);
  const meta = trpc.cinema.meta.useQuery(undefined, { staleTime: 300_000, refetchOnWindowFocus: false, refetchOnReconnect: false, retry: 1 });

  const catalogLinks = [
    { href: "/catalog/latest",     label: "Phim mới",     icon: <Star size={16} /> },
    { href: "/catalog/series",     label: "Phim bộ",      icon: <TvMinimal size={16} /> },
    { href: "/catalog/single",     label: "Phim lẻ",      icon: <MonitorPlay size={16} /> },
    { href: "/catalog/shows",      label: "Shows",        icon: <TvMinimal size={16} /> },
    { href: "/catalog/animation",  label: "Hoạt hình",    icon: <Layers size={16} /> },
    { href: "/catalog/vietsub",    label: "Vietsub",      icon: <Film size={16} /> },
    { href: "/catalog/thuyet-minh", label: "Thuyết minh", icon: <Film size={16} /> },
    { href: "/catalog/long-tieng", label: "Lồng tiếng",  icon: <Film size={16} /> },
    { href: "/catalog/subteam",    label: "Subteam",      icon: <Layers size={16} /> },
    { href: "/catalog/theatrical", label: "Chiếu rạp",    icon: <MonitorPlay size={16} /> },
  ];

  useEffect(() => { setMenuOpen(false); setDesktopMenuOpen(false); setMobileSearchOpen(false); }, [location]);
  useEffect(() => {
    document.body.style.overflow = menuOpen ? "hidden" : "";
    return () => { document.body.style.overflow = ""; };
  }, [menuOpen]);

  function submit(event: FormEvent) {
    event.preventDefault();
    const q = value.trim();
    if (q) { navigate(`/search?q=${encodeURIComponent(q)}`); setMenuOpen(false); }
  }

  const navLinks: Array<{ href: string; label: string; exact?: boolean; icon: ReactNode }> = [
    { href: "/",                   label: "Khám phá",  exact: true,  icon: <Home size={16} /> },
    ...catalogLinks,
    { href: "/catalog/categories", label: `Thể loại${meta.data?.categories?.length ? ` (${meta.data.categories.length})` : ""}`, exact: false, icon: <List size={16} /> },
    { href: "/account",            label: "Thư viện",  exact: false, icon: <Heart size={16} /> },
  ];
  const currentNav = navLinks.find(item => item.exact ? location === item.href : location.startsWith(item.href)) || navLinks[0];

  return (
    <>
      <header className="site-header">
        <div className="header-inner">
          {/* Logo */}
          <Link href="/" className="brand" aria-label="Cinemora trang chủ">
            <img className="site-logo" src={CINEMORA_LOGO_URL} alt="Cinemora" />
          </Link>

          {/* Desktop nav */}
          <nav className="main-nav" aria-label="Điều hướng chính">
            <button type="button" className={`desktop-menu-toggle${desktopMenuOpen ? " is-open" : ""}`} onClick={() => setDesktopMenuOpen(v => !v)} aria-expanded={desktopMenuOpen} aria-haspopup="menu">
              <span className="desktop-menu-toggle-icon"><Menu size={13} /></span><span className="desktop-menu-current">{currentNav.label}</span><span className="desktop-menu-toggle-label">Tất cả menu</span>
            </button>
          </nav>

          <div className={`desktop-menu-popover${desktopMenuOpen ? " is-open" : ""}`} role="menu" aria-hidden={!desktopMenuOpen}>
            <div className="desktop-menu-popover-head"><span>Khám phá Cinemora</span><button type="button" onClick={() => setDesktopMenuOpen(false)} aria-label="Đóng menu"><X size={14} /></button></div>
            <div className="desktop-menu-grid">
              {navLinks.map(item => {
                const active = item.exact ? location === item.href : location.startsWith(item.href);
                return <Link key={item.href} href={item.href} role="menuitem" className={`desktop-menu-link${active ? " active" : ""}`} onClick={() => setDesktopMenuOpen(false)}><span className="desktop-menu-link-icon">{item.icon}</span><span>{item.label}</span>{active && <span className="desktop-menu-link-dot" />}</Link>;
              })}
            </div>
          </div>

          {/* Desktop search */}
          <form className="search-box" onSubmit={submit} role="search">
            <Search size={17} />
            <input value={value} onChange={e => setValue(e.target.value)} placeholder="Tìm tên phim, diễn viên..." aria-label="Tìm kiếm phim" />
            {value && <button type="button" className="icon-button" onClick={() => setValue("")} aria-label="Xóa"><X size={15} /></button>}
          </form>

          {/* Desktop library shortcut */}
          <Link
            href="/account"
            className={`header-library-link${location.startsWith("/account") ? " is-active" : ""}`}
            aria-label="Mở thư viện"
          >
            <Heart size={15} fill={location.startsWith("/account") ? "currentColor" : "none"} />
            <span>Thư viện</span>
          </Link>

          {/* Mobile search trigger — intentionally outside the hamburger menu */}
          <button
            type="button"
            className={`mobile-search-btn${mobileSearchOpen ? " is-open" : ""}`}
            onClick={() => { setMobileSearchOpen(v => !v); setMenuOpen(false); }}
            aria-label={mobileSearchOpen ? "Đóng tìm kiếm" : "Mở tìm kiếm"}
            aria-expanded={mobileSearchOpen}
          >
            <Search size={19} />
          </button>

          {/* Mobile: hamburger */}
          <button type="button" className="mobile-menu-btn" onClick={() => setMenuOpen(v => !v)} aria-label={menuOpen ? "Đóng menu" : "Mở menu"} aria-expanded={menuOpen}>
            {menuOpen ? <X size={20} /> : <Menu size={20} />}
          </button>
        </div>
      </header>

      {mobileSearchOpen && (
        <form className="mobile-search-panel" onSubmit={submit} role="search">
          <Search size={18} />
          <input autoFocus value={value} onChange={e => setValue(e.target.value)} placeholder="Tìm tên phim, diễn viên..." aria-label="Tìm kiếm phim trên mobile" />
          {value && <button type="button" className="mobile-search-clear" onClick={() => setValue("")} aria-label="Xóa"><X size={16} /></button>}
        </form>
      )}

      {/* Overlay */}
      {menuOpen && <div className="mm-overlay" onClick={() => setMenuOpen(false)} aria-hidden="true" />}

      {/* Drawer */}
      <div className={`mm-drawer${menuOpen ? " mm-drawer--open" : ""}`} role="dialog" aria-modal="true">

        {/* Header drawer: logo + nút đóng */}
        <div className="mm-header">
          <div className="mm-header-brand">
            <img className="mobile-site-logo" src={CINEMORA_LOGO_URL} alt="Cinemora" />
          </div>
          <button type="button" className="mm-close" onClick={() => setMenuOpen(false)} aria-label="Đóng menu">
            <X size={18} />
          </button>
        </div>

        {/* Nav links */}
        <nav className="mm-nav" aria-label="Điều hướng mobile">
          <span className="mm-nav-label">Khám phá</span>
          {navLinks.slice(0, 1).map(item => {
            const active = item.exact ? location === item.href : location.startsWith(item.href);
            return (
              <Link key={item.href} href={item.href} className={`mm-link${active ? " mm-link--active" : ""}`} onClick={() => setMenuOpen(false)}>
                <span className="mm-link-icon">{item.icon}</span>
                <span className="mm-link-label">{item.label}</span>
                {active && <span className="mm-link-dot" />}
              </Link>
            );
          })}
          <div className="mm-nav-divider" />
          <span className="mm-nav-label">Danh mục</span>
          {navLinks.slice(1, navLinks.length - 1).map(item => {
            const active = item.exact ? location === item.href : location.startsWith(item.href);
            return (
              <Link key={item.href} href={item.href} className={`mm-link${active ? " mm-link--active" : ""}`} onClick={() => setMenuOpen(false)}>
                <span className="mm-link-icon">{item.icon}</span>
                <span className="mm-link-label">{item.label}</span>
                {active && <span className="mm-link-dot" />}
              </Link>
            );
          })}
          <div className="mm-nav-divider" />
          {navLinks.slice(-1).map(item => {
            const active = item.exact ? location === item.href : location.startsWith(item.href);
            return (
              <Link key={item.href} href={item.href} className={`mm-link${active ? " mm-link--active" : ""}`} onClick={() => setMenuOpen(false)}>
                <span className="mm-link-icon">{item.icon}</span>
                <span className="mm-link-label">{item.label}</span>
                {active && <span className="mm-link-dot" />}
              </Link>
            );
          })}
        </nav>
      </div>
    </>
  );
}

export function PageShell({ children }: { children: ReactNode }) {
  return (
    <div className="app-shell">
      <SiteHeader />
      {children}
      <footer className="site-footer">
        <div className="footer-brand"><img className="footer-site-logo" src={CINEMORA_LOGO_URL} alt="Cinemora" /></div>
        <span>Khoảnh khắc hay, khung hình đẹp.</span>
        <span className="footer-note">Trải nghiệm mượt mà hơn mỗi ngày</span>
      </footer>
    </div>
  );
}

export type MovieCardMovie = { id: string; slug: string; name: string; originName: string; poster: string | null; year: number | null; quality: string; episodeCurrent: string; rating: number | null; categories: Array<{ name: string; slug: string }> };
function PosterImg({ src, alt, priority }: { src: string; alt: string; priority: boolean }) {
  const [imgSrc, setImgSrc] = useState(src);
  const [failed, setFailed] = useState(false);
  const retries = useRef(0);
  const lastSrc = useRef(src);
  // Only sync imgSrc when src actually changes to a new value (avoid reset on re-renders)
  useEffect(() => {
    if (src !== lastSrc.current) {
      lastSrc.current = src;
      retries.current = 0;
      setFailed(false);
      setImgSrc(src);
    }
  }, [src]);
  if (failed) return null; // let poster-fallback CSS show placeholder
  return (
    <img
      src={imgSrc}
      alt={alt}
      loading={priority ? "eager" : "lazy"}
      decoding="async"
      fetchPriority={priority ? "high" : "auto"}
      onError={() => {
        if (retries.current === 0) {
          // First failure: cache-bust retry after short delay
          retries.current = 1;
          const cleanSrc = src.split("?")[0];
          setTimeout(() => setImgSrc(`${cleanSrc}?r=1`), 800);
        } else if (retries.current === 1) {
          // Second failure: try original src one more time (no cache-bust param)
          retries.current = 2;
          setTimeout(() => setImgSrc(src.split("?")[0]), 2000);
        } else {
          // All retries exhausted — hide img and let poster-fallback CSS show placeholder
          setFailed(true);
        }
      }}
    />
  );
}

export function MovieCard({ movie, featured = false, index = 0 }: { movie: MovieCardMovie; featured?: boolean; index?: number }) { return <Link href={`/movie/${movie.slug}`} className={`movie-card ${featured ? "movie-card-featured" : ""}`} style={{ "--delay": `${index * 45}ms` } as React.CSSProperties}><div className="poster-frame">{movie.poster ? <PosterImg src={movie.poster} alt={movie.name} priority={index <= 5} /> : <div className="poster-fallback"><Film size={28} /><span>Cinemora</span></div>}<div className="poster-shade" /><span className="quality-pill">{movie.quality || "HD"}</span>{movie.rating && <span className="rating-pill"><span>★</span> {movie.rating}</span>}<span className="play-chip"><Play size={14} fill="currentColor" /></span></div><div className="movie-card-copy"><h3>{movie.name}</h3><p>{movie.originName || "Cinemora selection"}</p><div className="movie-meta"><span>{movie.year || "—"}</span><i>•</i><span>{movie.episodeCurrent || "Đang cập nhật"}</span></div></div></Link>; }
export function SkeletonCard() { return <div className="skeleton-card"><div className="skeleton skeleton-poster" /><div className="skeleton skeleton-line wide" /><div className="skeleton skeleton-line" /><div className="skeleton skeleton-line small" /></div>; }
export function SectionHeading({ eyebrow, title, action }: { eyebrow?: string; title: string; action?: ReactNode }) { return <div className="section-heading"><div>{eyebrow && <span className="eyebrow">{eyebrow}</span>}<h2>{title}</h2></div>{action}</div>; }
