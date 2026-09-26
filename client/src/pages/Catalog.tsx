import { ArrowLeft, ArrowRight, ChevronLeft, ChevronRight, Filter, Search as SearchIcon, SlidersHorizontal } from "lucide-react";
import { Link, useLocation, useSearch } from "wouter";
import { MovieCard, PageShell, SectionHeading, SkeletonCard } from "@/components/CinemaChrome";
import type { MovieCardMovie } from "@/components/CinemaChrome";
import { SearchableSelect } from "@/components/SearchableSelect";
import { trpc } from "@/lib/trpc";
import { keepPreviousData } from "@tanstack/react-query";
import { startTransition, useEffect, useState } from "react";

type CatalogKind = "latest" | "single" | "series" | "shows" | "animation" | "vietsub" | "thuyetminh" | "longtieng" | "subteam" | "theatrical";
const labels: Record<CatalogKind, string> = { latest: "Phim mới cập nhật", single: "Phim lẻ", series: "Phim bộ", shows: "Shows", animation: "Hoạt hình", vietsub: "Phim Vietsub", thuyetminh: "Phim Thuyết Minh", longtieng: "Phim Lồng Tiếng", subteam: "Subteam", theatrical: "Phim chiếu rạp" };

export function CatalogPage({ kind }: { kind: CatalogKind }) {
  const [location, navigate] = useLocation();
  const search = useSearch();
  const params = new URLSearchParams(search);
  const [filters, setFilters] = useState({ category: params.get("category") || "", country: params.get("country") || "", year: params.get("year") || "", page: params.get("page") || "1" });
  useEffect(() => { const next = new URLSearchParams(search); setFilters({ category: next.get("category") || "", country: next.get("country") || "", year: next.get("year") || "", page: next.get("page") || "1" }); }, [search]);
  const category = filters.category || undefined; const country = filters.country || undefined; const year = filters.year ? Number(filters.year) : undefined; const page = Number(filters.page || "1");
  const query = trpc.cinema.list.useQuery({ kind, page, category, country, year }, { staleTime: 120_000, placeholderData: keepPreviousData, refetchOnWindowFocus: false, refetchOnReconnect: false, retry: 1 });
  const meta = trpc.cinema.meta.useQuery(undefined, { staleTime: 300_000, refetchOnWindowFocus: false, refetchOnReconnect: false, retry: 1 });
  const items: MovieCardMovie[] = query.data?.items || [];
  const totalPages = Number(query.data?.pagination?.totalPages || query.data?.pagination?.pageRanges || 1);
  function setFilter(key: string, value: string) { const next = { ...filters, [key]: value, ...(key !== "page" ? { page: "1" } : {}) }; setFilters(next); const nextParams = new URLSearchParams(); Object.entries(next).forEach(([filterKey, filterValue]) => { if (filterValue) nextParams.set(filterKey, filterValue); }); startTransition(() => navigate(`/catalog/${kind}?${nextParams.toString()}`)); if (key === "page") window.scrollTo({ top: 0, behavior: "smooth" }); }
  return <PageShell><main className="content-wrap inner-page"><div className="page-topline"><Link href="/" className="back-link"><ArrowLeft size={15} /> Trang chủ</Link><span className="result-note">{query.isLoading ? "Đang tải thư viện..." : `${query.data?.pagination?.totalItems || items.length} tựa phim`}</span></div><SectionHeading eyebrow="THƯ VIỆN CINEMORA" title={labels[kind]} action={<div className="filter-icon"><SlidersHorizontal size={16} /> Bộ lọc</div>} /><div className="filter-row"><div className="filter-label"><Filter size={14} /> Lọc nhanh</div><SearchableSelect value={category || ""} onChange={(value) => setFilter("category", value)} placeholder="Tất cả thể loại" searchPlaceholder="Tìm thể loại..." ariaLabel="Lọc thể loại" options={(meta.data?.categories || []).map((item: { name: string; slug: string }) => ({ value: item.slug, label: item.name }))} /><SearchableSelect value={country || ""} onChange={(value) => setFilter("country", value)} placeholder="Tất cả quốc gia" searchPlaceholder="Tìm quốc gia..." ariaLabel="Lọc quốc gia" options={(meta.data?.countries || []).map((item: { name: string; slug: string }) => ({ value: item.slug, label: item.name }))} /><SearchableSelect value={year ? String(year) : ""} onChange={(value) => setFilter("year", value)} placeholder="Mọi năm" searchPlaceholder="Tìm năm..." ariaLabel="Lọc năm" options={(meta.data?.years || []).map((item: number) => ({ value: String(item), label: String(item) }))} compact includePlaceholderOption /></div>{query.isError ? <div className="empty-state"><SearchIcon size={30} /><h3>Không thể tải thư viện</h3><p>Thử tải lại sau ít phút nhé.</p></div> : <div className="movie-grid catalog-grid">{query.isLoading ? Array.from({ length: 12 }).map((_, i) => <SkeletonCard key={i} />) : items.map((movie, i) => <MovieCard key={movie.id} movie={movie} index={i} />)}</div>}{totalPages > 1 && <div className="pagination">
  <button className="pagination-button" aria-label="Trang trước" disabled={page <= 1} onClick={() => setFilter("page", String(page - 1))}><ChevronLeft size={15} /></button>
  {(() => {
    const windowSize = 6;
    const windowStart = Math.floor((page - 1) / windowSize) * windowSize + 1;
    const windowEnd = Math.min(totalPages, windowStart + windowSize - 1);
    return Array.from({ length: windowEnd - windowStart + 1 }, (_, i) => windowStart + i).map((itemPage) => (
      <button key={itemPage} aria-label={`Trang ${itemPage}`} className={`pagination-num${itemPage === page ? " active" : ""}`} onClick={() => itemPage !== page && setFilter("page", String(itemPage))}>{itemPage}</button>
    ));
  })()}
  <button className="pagination-button" aria-label="Trang sau" disabled={page >= totalPages} onClick={() => setFilter("page", String(page + 1))}><ChevronRight size={15} /></button>
</div>}</main></PageShell>;
}

export function CategoryDirectoryPage() {
  const [location, navigate] = useLocation();
  const search = useSearch();
  const selected = new URLSearchParams(search).get("category") || "";
  const meta = trpc.cinema.meta.useQuery(undefined, { staleTime: 300_000, refetchOnWindowFocus: false, refetchOnReconnect: false, retry: 1 });
  const movies = trpc.cinema.list.useQuery({ kind: "latest", page: 1, category: selected || undefined }, { enabled: Boolean(selected), staleTime: 120_000, refetchOnWindowFocus: false, refetchOnReconnect: false, retry: 1 });
  const options = (meta.data?.categories || []) as Array<{ name: string; slug: string }>;
  const selectedName = options.find((option) => option.slug === selected)?.name || selected;
  function choose(value: string) { navigate(value ? `/catalog/categories?category=${encodeURIComponent(value)}` : "/catalog/categories"); }
  const resultItems = (movies.data?.items || []) as MovieCardMovie[];
  return <PageShell><main className="content-wrap inner-page"><div className="page-topline"><Link href="/" className="back-link"><ArrowLeft size={15} /> Trang chủ</Link><span className="result-note">{selected ? `${movies.data?.pagination?.totalItems || resultItems.length} tựa phim` : `${options.length} thể loại`}</span></div><SectionHeading eyebrow="THƯ VIỆN CINEMORA" title="Thể loại" action={<Link className="section-link" href="/catalog/latest">Mở thư viện <ArrowRight size={15} /></Link>} /><div className="filter-row category-directory-filter"><div className="filter-label"><Filter size={14} /> Chọn thể loại</div><SearchableSelect value={selected} onChange={choose} placeholder="Tất cả thể loại" searchPlaceholder="Tìm thể loại..." ariaLabel="Chọn thể loại" options={options.map((item) => ({ value: item.slug, label: item.name }))} /></div>{!selected ? <div className="category-directory-hint"><SearchIcon size={24} /><strong>Chọn một thể loại để bắt đầu</strong><span>Tìm nhanh trong danh sách hoặc mở bộ lọc phía trên để khám phá phim.</span></div> : movies.isError ? <div className="empty-state"><SearchIcon size={30} /><h3>Không thể tải phim theo thể loại</h3><p>Thử chọn thể loại khác nhé.</p></div> : <section className="directory-results category-directory-results"><SectionHeading eyebrow="KẾT QUẢ LỌC" title={selectedName} action={<Link className="section-link" href={`/catalog/latest?category=${encodeURIComponent(selected)}`}>Mở thư viện đầy đủ <ArrowRight size={15} /></Link>} /><div className="movie-grid catalog-grid">{movies.isLoading ? Array.from({ length: 6 }).map((_, i) => <SkeletonCard key={i} />) : resultItems.map((movie, i) => <MovieCard key={movie.id} movie={movie} index={i} />)}</div></section>}</main></PageShell>;
}

export function DirectoryPage({ dimension }: { dimension: "categories" | "countries" | "years" }) {
  const [, navigate] = useLocation(); const search = useSearch(); const params = new URLSearchParams(search); const selected = params.get(dimension === "categories" ? "category" : dimension === "countries" ? "country" : "year") || "";
  const meta = trpc.cinema.meta.useQuery(undefined, { staleTime: 300_000, refetchOnWindowFocus: false, refetchOnReconnect: false, retry: 1 });
  const filter = dimension === "categories" ? { category: selected || undefined } : dimension === "countries" ? { country: selected || undefined } : { year: selected ? Number(selected) : undefined };
  const movies = trpc.cinema.list.useQuery({ kind: "latest" as const, page: 1, ...filter }, { enabled: Boolean(selected), staleTime: 120_000, refetchOnWindowFocus: false, refetchOnReconnect: false, retry: 1 });
  const title = dimension === "categories" ? "Tất cả thể loại" : dimension === "countries" ? "Tất cả quốc gia" : "Tất cả năm phát hành";
  type DirectoryOption = { name: string; slug: string };
  const options: DirectoryOption[] = dimension === "categories" ? (meta.data?.categories || []) : dimension === "countries" ? (meta.data?.countries || []) : (meta.data?.years || []).map((year: number) => ({ name: String(year), slug: String(year) }));
  function choose(value: string) { const key = dimension === "categories" ? "category" : dimension === "countries" ? "country" : "year"; navigate(`/catalog/latest?${key}=${encodeURIComponent(value)}`); }
  const resultItems = (movies.data?.items || []) as MovieCardMovie[];
  return <PageShell><main className="content-wrap inner-page"><div className="page-topline"><Link href="/" className="back-link"><ArrowLeft size={15} /> Trang chủ</Link><span className="result-note">{options.length} lựa chọn</span></div><SectionHeading eyebrow="KHÁM PHÁ THEO DANH MỤC" title={title} /><div className="directory-grid">{options.map((option: DirectoryOption) => <button type="button" key={option.slug} className={`directory-card ${selected === option.slug ? "active" : ""}`} onClick={() => choose(option.slug)}><strong>{option.name}</strong><span>{selected === option.slug ? "Đang chọn · xem phim bên dưới" : "Xem danh sách phim"}</span><ArrowRight size={15} /></button>)}</div>{selected && <section className="directory-results"><SectionHeading eyebrow="KẾT QUẢ LỌC" title={`${options.find((option: DirectoryOption) => option.slug === selected)?.name || selected}`} action={<Link href={`/catalog/${dimension === "categories" ? "latest?category" : dimension === "countries" ? "latest?country" : "latest?year"}=${encodeURIComponent(selected)}`} className="section-link">Mở thư viện đầy đủ <ArrowRight size={15} /></Link>} /><div className="movie-grid catalog-grid">{movies.isLoading ? Array.from({ length: 6 }).map((_, i) => <SkeletonCard key={i} />) : resultItems.map((movie: MovieCardMovie, i: number) => <MovieCard key={movie.id} movie={movie} index={i} />)}</div></section>}</main></PageShell>;
}

export function SearchPage() {
  const search = useSearch(); const keyword = new URLSearchParams(search).get("q") || ""; const query = trpc.cinema.search.useQuery({ keyword }, { enabled: keyword.trim().length >= 2, staleTime: 120_000, refetchOnWindowFocus: false, refetchOnReconnect: false, retry: 1 }); const items: MovieCardMovie[] = query.data?.items || [];
  return <PageShell><main className="content-wrap inner-page"><div className="page-topline"><Link href="/" className="back-link"><ArrowLeft size={15} /> Trang chủ</Link><span className="result-note">{query.isLoading ? "Đang tìm kiếm..." : `${query.data?.pagination?.totalItems || items.length} kết quả`}</span></div><SectionHeading eyebrow="KẾT QUẢ TÌM KIẾM" title={keyword ? `“${keyword}”` : "Bạn đang tìm gì?"} />{keyword.length < 2 ? <div className="empty-state"><SearchIcon size={30} /><h3>Nhập ít nhất 2 ký tự</h3><p>Tìm theo tên phim tiếng Việt hoặc tên gốc.</p></div> : query.isError ? <div className="empty-state"><SearchIcon size={30} /><h3>Không tìm thấy kết quả</h3><p>Thử một từ khóa khác nhé.</p></div> : <div className="movie-grid catalog-grid">{query.isLoading ? Array.from({ length: 12 }).map((_, i) => <SkeletonCard key={i} />) : items.map((movie, i) => <MovieCard key={movie.id} movie={movie} index={i} />)}</div>}</main></PageShell>;
}
