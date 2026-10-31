import { ArrowLeft, ArrowRight, ChevronLeft, ChevronRight, Filter, Search as SearchIcon, SlidersHorizontal } from "lucide-react";
import type { FormEvent } from "react";
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
  const pageInfo: any = query.data?.pagination || {};
  const totalPages = Number(pageInfo.totalPages || pageInfo.pageRanges || 1);
  // Bộ lọc nhiều lựa chọn không có tổng số trang: vẫn cho sang trang khi nguồn còn dữ liệu.
  const canGoNext = pageInfo.hasNextPage === true || page < totalPages;
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
  <button className="pagination-button" aria-label="Trang sau" disabled={!canGoNext} onClick={() => setFilter("page", String(page + 1))}><ChevronRight size={15} /></button>
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
  const search = useSearch();
  const keyword = new URLSearchParams(search).get("q") || "";
  const [, navigate] = useLocation();
  const [draft, setDraft] = useState(keyword);
  useEffect(() => setDraft(keyword), [keyword]);
  const query = trpc.cinema.search.useQuery(
    { keyword },
    {
      enabled: keyword.trim().length >= 2,
      staleTime: 120_000,
      refetchOnWindowFocus: false,
      refetchOnReconnect: false,
      retry: 1,
    },
  );
  const items: MovieCardMovie[] = query.data?.items || [];
  const totalResults = query.data?.pagination?.totalItems ?? items.length;

  function submitSearch(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const term = draft.trim();
    if (term.length >= 2) navigate(`/search?q=${encodeURIComponent(term)}`);
  }

  return (
    <PageShell>
      <main className="content-wrap inner-page search-page">
        <div className="page-topline">
          <Link href="/" className="back-link"><ArrowLeft size={15} /> Trang chủ</Link>
          <span className="result-note">
            {keyword.trim().length < 2 ? "Tìm phim" : query.isLoading ? "Đang tìm kiếm…" : `${totalResults} kết quả`}
          </span>
        </div>
        <SectionHeading
          eyebrow="KHÁM PHÁ CINEMORA"
          title={keyword ? `Kết quả cho “${keyword}”` : "Tìm phim bạn muốn xem"}
        />
        <form className="search-page-form" onSubmit={submitSearch} role="search" aria-label="Tìm phim">
          <div className="search-page-input">
            <SearchIcon size={19} aria-hidden="true" />
            <input
              type="search"
              inputMode="search"
              enterKeyHint="search"
              autoComplete="off"
              value={draft}
              onChange={event => setDraft(event.target.value)}
              placeholder="Tên phim hoặc diễn viên…"
              aria-label="Nhập tên phim hoặc diễn viên"
            />
            {draft && <button type="button" onClick={() => setDraft("")} aria-label="Xóa từ khóa"><span aria-hidden="true">×</span></button>}
          </div>
          <button className="search-page-submit" type="submit" disabled={draft.trim().length < 2}>
            <SearchIcon size={16} /><span>Tìm kiếm</span>
          </button>
        </form>
        <p className="search-page-hint">
          {draft.trim().length < 2 ? "Nhập ít nhất 2 ký tự để bắt đầu tìm kiếm." : "Tìm theo tên phim tiếng Việt, tên gốc hoặc diễn viên."}
        </p>

        {keyword.trim().length < 2 ? (
          <div className="empty-state search-page-empty"><SearchIcon size={30} /><h3>Nhập ít nhất 2 ký tự</h3><p>Dùng ô tìm kiếm phía trên để khám phá phim phù hợp.</p></div>
        ) : query.isError ? (
          <div className="empty-state search-page-empty"><SearchIcon size={30} /><h3>Chưa thể tải kết quả</h3><p>Kiểm tra kết nối rồi thử lại sau nhé.</p></div>
        ) : query.isLoading ? (
          <div className="movie-grid catalog-grid">{Array.from({ length: 8 }).map((_, index) => <SkeletonCard key={index} />)}</div>
        ) : items.length === 0 ? (
          <div className="empty-state search-page-empty"><SearchIcon size={30} /><h3>Chưa tìm thấy phim phù hợp</h3><p>Thử tên khác, tên gốc hoặc một từ khóa ngắn hơn.</p></div>
        ) : (
          <div className="movie-grid catalog-grid">{items.map((movie, index) => <MovieCard key={movie.id} movie={movie} index={index} />)}</div>
        )}
      </main>
    </PageShell>
  );
}
