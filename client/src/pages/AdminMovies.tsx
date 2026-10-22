import { memo, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Link } from "wouter";
import { Check, Database, ExternalLink, MessageCircle, Pin, Plus, RefreshCw, Search, ShieldCheck, Trash2, UserRound } from "lucide-react";
import { AuthDialog } from "@/components/AuthDialog";
import { PageShell, SectionHeading } from "@/components/CinemaChrome";
import { useAuth } from "@/_core/hooks/useAuth";
import { trpc } from "@/lib/trpc";
import { BadgeChipList, NameText, accountBadges, parseNameStyle } from "@/lib/cinemaBadges";

type MovieSummary = {
  slug: string;
  name: string;
  originName?: string | null;
  posterUrl?: string | null;
  poster?: string | null;
  year?: number | null;
  quality?: string | null;
};

type CommentItem = {
  id: string;
  parentId: string | null;
  content: string;
  createdAt: string;
  userName: string;
  userRole: string | null;
  badge: string | null;
  /** Danh sách nhãn dạng JSON (nhiều nhãn cho một tài khoản). */
  badges?: string | null;
  /** Kiểu tên người dùng dạng JSON (màu, hiệu ứng). */
  nameStyle?: string | null;
  userAvatar: string | null;
  userId: string;
  isMine: boolean;
  isPinned: boolean;
  canDelete: boolean;
  replies?: CommentItem[];
};

type CommentsResponse = { items: CommentItem[]; revision: number };
type WatchCommentsResponse = { revision: number; items: CommentItem[] | null; changed: boolean };

function moviePoster(movie: MovieSummary) {
  return movie.posterUrl || movie.poster || "";
}

function formatCommentDate(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "Vừa xong" : date.toLocaleString("vi-VN", { dateStyle: "short", timeStyle: "short" });
}

function initialOf(name: string) {
  return name.trim().charAt(0).toLocaleUpperCase("vi-VN") || "?";
}

function sortComments(items: CommentItem[]) {
  return [...items].sort((a, b) => Number(b.isPinned) - Number(a.isPinned));
}

type GroupedComment = CommentItem & { replies: CommentItem[] };

function groupComments(items: CommentItem[]): GroupedComment[] {
  const byId = new Map(items.map(comment => [comment.id, comment]));
  const roots: GroupedComment[] = items
    .filter(comment => comment.parentId === null || !byId.has(comment.parentId))
    .map(comment => ({ ...comment, replies: [] }));
  const rootsById = new Map(roots.map(comment => [comment.id, comment]));

  // Trả lời có thể nằm dưới một trả lời khác: đi ngược lên tới bình luận gốc của nhánh
  // để không bỏ sót bình luận nào khỏi danh sách quản trị.
  const rootIdOf = (comment: CommentItem): string => {
    let current = comment;
    for (let hop = 0; hop < 12; hop += 1) {
      const parentId = current.parentId;
      if (!parentId) return current.id;
      const parent = byId.get(parentId);
      if (!parent) return current.id;
      current = parent;
    }
    return current.id;
  };

  items.filter(comment => !rootsById.has(comment.id)).forEach(reply => {
    const root = rootsById.get(rootIdOf(reply));
    if (root) root.replies.push(reply);
  });
  return roots;
}

/**
 * Một dòng phim trong danh sách chọn phim.
 *
 * Tách riêng và ghi nhớ theo dữ liệu nên khi chọn phim hay gõ tìm kiếm, các dòng còn lại
 * không dựng lại; ảnh poster tải lười để danh sách dài vẫn mượt.
 */
const AdminMovieRow = memo(
  function AdminMovieRow({
    movie,
    isSelected,
    onSelect,
  }: {
    movie: MovieSummary;
    isSelected: boolean;
    onSelect: (movie: MovieSummary) => void;
  }) {
    const poster = moviePoster(movie);
    return (
      <div className="admin-movies-movie-row">
        <button
          type="button"
          className={`admin-movies-movie${isSelected ? " is-selected" : ""}`}
          onClick={() => onSelect(movie)}
        >
          <span className="admin-movies-poster">
            {poster ? <img src={poster} alt="" loading="lazy" decoding="async" /> : <span><UserRound size={16} /></span>}
          </span>
          <span className="admin-movies-movie-copy">
            <strong>{movie.name}</strong>
            <small>{movie.year || "—"} · {movie.quality || "Chưa rõ chất lượng"}</small>
          </span>
          {isSelected && <Check size={15} />}
        </button>
        <Link href={`/admin/movies/sources?slug=${encodeURIComponent(movie.slug)}`} className="admin-movies-sources-link">
          <Database size={13} /> Nguồn &amp; tập
        </Link>
      </div>
    );
  },
  (prev, next) => prev.movie === next.movie && prev.isSelected === next.isSelected,
);

export default function AdminMovies() {
  const { user, loading } = useAuth();
  const [authOpen, setAuthOpen] = useState(false);
  const [searchKeyword, setSearchKeyword] = useState("");
  const [debouncedKeyword, setDebouncedKeyword] = useState("");
  const [selectedMovie, setSelectedMovie] = useState<MovieSummary | null>(null);
  const [commentItems, setCommentItems] = useState<CommentItem[]>([]);
  const [liveError, setLiveError] = useState<string | null>(null);
  const revisionRef = useRef(0);

  useEffect(() => {
    const timer = window.setTimeout(() => setDebouncedKeyword(searchKeyword.trim()), 350);
    return () => window.clearTimeout(timer);
  }, [searchKeyword]);

  const latestQuery = trpc.cinema.list.useQuery({ kind: "latest", page: 1 }, { enabled: user?.role === "admin" && debouncedKeyword.length < 2, retry: false });
  const searchQuery = trpc.cinema.search.useQuery({ keyword: debouncedKeyword, page: 1 }, { enabled: user?.role === "admin" && debouncedKeyword.length >= 2, retry: false });
  const commentsQuery = trpc.cinema.comments.useQuery({ slug: selectedMovie?.slug || "" }, { enabled: user?.role === "admin" && Boolean(selectedMovie?.slug), retry: false });
  const utils = trpc.useUtils();
  const commentsData = commentsQuery.data as unknown as CommentsResponse | undefined;
  const watchComments = (utils.cinema as unknown as { watchComments: { fetch: (input: { slug: string; since: number }) => Promise<WatchCommentsResponse> } }).watchComments;
  const pinComment = trpc.cinema.pinComment.useMutation({ onSuccess: async () => { await commentsQuery.refetch(); } });
  const deleteComment = trpc.cinema.deleteComment.useMutation({ onSuccess: async () => { await commentsQuery.refetch(); } });

  useEffect(() => {
    setCommentItems(commentsData?.items || []);
    revisionRef.current = commentsData?.revision || 0;
  }, [selectedMovie?.slug, commentsData?.revision]);

  useEffect(() => {
    const slug = selectedMovie?.slug;
    if (!slug) return;
    let stopped = false;
    const wait = (ms: number) => new Promise<void>((resolve) => window.setTimeout(resolve, ms));
    const loop = async () => {
      while (!stopped) {
        try {
          const response = await watchComments.fetch({ slug, since: revisionRef.current });
          if (stopped) return;
          setLiveError(null);
          if (response.changed && response.items) setCommentItems(response.items);
          revisionRef.current = response.revision;
        } catch {
          if (!stopped) {
            setLiveError("Không thể cập nhật bình luận trực tiếp. Hệ thống sẽ tự thử lại.");
            await wait(3000);
          }
        }
      }
    };
    loop();
    return () => { stopped = true; };
  }, [selectedMovie?.slug, watchComments]);

  const movies = useMemo(
    () =>
      ((debouncedKeyword.length >= 2 ? searchQuery.data?.items : latestQuery.data?.items) || []) as MovieSummary[],
    [debouncedKeyword, searchQuery.data, latestQuery.data],
  );
  // Nhóm và sắp xếp bình luận chỉ chạy lại khi danh sách thật sự đổi.
  const sortedComments = useMemo(() => sortComments(groupComments(commentItems)), [commentItems]);
  const selectMovie = useCallback((movie: MovieSummary) => setSelectedMovie(movie), []);
  const movieQueryError = (debouncedKeyword.length >= 2 ? searchQuery.error : latestQuery.error)?.message;

  if (loading) return <PageShell><main className="content-wrap inner-page"><p>Đang kiểm tra quyền truy cập…</p></main></PageShell>;
  if (!user) return <PageShell><main className="content-wrap inner-page"><div className="empty-state"><ShieldCheck size={30} /><h3>Cần đăng nhập admin</h3><p>Đăng nhập tài khoản quản trị viên để xem và điều hành bình luận phim.</p><button className="button button-primary" onClick={() => setAuthOpen(true)}>Đăng nhập</button></div><AuthDialog open={authOpen} onClose={() => setAuthOpen(false)} /></main></PageShell>;
  if (user.role !== "admin") return <PageShell><main className="content-wrap inner-page"><div className="empty-state"><ShieldCheck size={30} /><h3>Không có quyền truy cập</h3><p>Khu vực này chỉ dành cho quản trị viên.</p></div></main></PageShell>;

  function refreshComments() {
    if (!selectedMovie) return;
    setLiveError(null);
    void commentsQuery.refetch();
  }

  function togglePin(comment: CommentItem) {
    if (!selectedMovie) return;
    pinComment.mutate({ slug: selectedMovie.slug, id: comment.id, pinned: !comment.isPinned });
  }

  function removeComment(comment: CommentItem) {
    if (!selectedMovie || !window.confirm(`Xoá bình luận của ${comment.userName}?`)) return;
    deleteComment.mutate({ slug: selectedMovie.slug, id: comment.id });
  }

  function renderComment(comment: CommentItem, isReply = false) {
    const avatar = comment.userAvatar;
    return <article className={`admin-movies-comment${comment.isPinned ? " is-pinned" : ""}${isReply ? " is-reply" : ""}`} key={comment.id}>
      <div className="admin-movies-comment-avatar">{avatar ? <img src={avatar} alt="" loading="lazy" decoding="async" /> : <span>{initialOf(comment.userName)}</span>}</div>
      <div className="admin-movies-comment-body">
        <div className="admin-movies-comment-head"><strong><NameText name={comment.userName} style={parseNameStyle(comment.nameStyle)} /></strong><BadgeChipList badges={accountBadges(comment.badges, comment.badge)} />{comment.userRole === "admin" && <span className="admin-movies-verified" title="Quản trị viên"><Check size={11} /></span>}<time>{formatCommentDate(comment.createdAt)}</time>{comment.isPinned && <span className="admin-movies-pinned-label"><Pin size={11} /> Đã ghim</span>}</div>
        <p>{comment.content}</p>
        <div className="admin-movies-comment-actions">{!isReply && <button type="button" className="admin-movies-action" disabled={pinComment.isPending} onClick={() => togglePin(comment)}><Pin size={13} /> {comment.isPinned ? "Bỏ ghim" : "Ghim lên đầu"}</button>}{comment.canDelete && <button type="button" className="admin-movies-action is-danger" disabled={deleteComment.isPending} onClick={() => removeComment(comment)}><Trash2 size={13} /> Xoá</button>}</div>
        {!isReply && comment.replies?.map(reply => renderComment(reply, true))}
      </div>
    </article>;
  }

  return <PageShell><main className="content-wrap inner-page admin-movies-page">
    <div className="page-topline"><Link href="/" className="back-link">← Trang chủ</Link><span className="result-note"><Link href="/admin/accounts" className="text-link">Quản lý tài khoản</Link> · Quản trị viên</span></div>
    <SectionHeading eyebrow="CINEMORA ADMIN" title="Quản lý phim & bình luận" action={<Link href="/admin/movies/custom/new" className="button button-primary"><Plus size={14} /> Thêm phim thủ công</Link>} />
    <div className="admin-movies-layout">
      <section className="admin-movies-panel admin-movies-picker">
        <div className="admin-movies-panel-heading"><div><strong>Chọn phim</strong><span>Tìm phim để xem và điều hành bình luận.</span></div><MessageCircle size={19} /></div>
        <label className="admin-tv-search admin-movies-search"><Search size={15} /><input value={searchKeyword} onChange={event => setSearchKeyword(event.target.value)} placeholder="Tìm theo tên phim…" aria-label="Tìm phim" />{searchKeyword && <button type="button" onClick={() => setSearchKeyword("")} aria-label="Xoá tìm kiếm">×</button>}</label>
        {movieQueryError && <p className="admin-tv-error">Không thể tải danh sách phim: {movieQueryError}</p>}
        <div className="admin-movies-list">{(latestQuery.isLoading || searchQuery.isLoading) ? <p className="admin-movies-muted">Đang tải danh sách phim…</p> : movies.length === 0 ? <div className="admin-movies-empty"><Search size={22} /><strong>{debouncedKeyword.length >= 2 ? "Không tìm thấy phim" : "Chưa có phim để hiển thị"}</strong><span>Thử một từ khoá khác hoặc tải lại trang.</span></div> : movies.map(movie => <AdminMovieRow key={movie.slug} movie={movie} isSelected={selectedMovie?.slug === movie.slug} onSelect={selectMovie} />)}</div>
      </section>
      <section className="admin-movies-panel admin-movies-comments-panel">
        {!selectedMovie ? <div className="admin-movies-placeholder"><MessageCircle size={30} /><h3>Chọn một bộ phim</h3><p>Bình luận của phim được hiển thị tại đây và cập nhật tự động theo thời gian thực.</p></div> : <><div className="admin-movies-comments-heading"><div><strong>{selectedMovie.name}</strong><span><span className="admin-tv-live-dot" /> Đang cập nhật trực tiếp</span></div><div className="admin-movies-comment-tools"><a className="button button-ghost" href={`/movie/${selectedMovie.slug}`} target="_blank" rel="noreferrer"><ExternalLink size={14} /> Xem trên web</a><button type="button" className="admin-tv-refresh" onClick={refreshComments} disabled={commentsQuery.isFetching} title="Làm mới bình luận"><RefreshCw size={15} className={commentsQuery.isFetching ? "admin-tv-refresh-spin" : ""} /></button></div></div>{liveError && <p className="admin-tv-error">{liveError}</p>}{commentsQuery.error && <p className="admin-tv-error">Không thể tải bình luận: {commentsQuery.error.message}</p>}{commentsQuery.isLoading ? <p className="admin-movies-muted">Đang tải bình luận…</p> : sortedComments.length === 0 ? <div className="admin-movies-placeholder is-compact"><MessageCircle size={25} /><h3>Phim này chưa có bình luận</h3><p>Khi khán giả bình luận, nội dung sẽ xuất hiện tại đây.</p></div> : <div className="admin-movies-comments-list">{sortedComments.map(comment => renderComment(comment))}</div>}</>}
      </section>
    </div>
  </main></PageShell>;
}
