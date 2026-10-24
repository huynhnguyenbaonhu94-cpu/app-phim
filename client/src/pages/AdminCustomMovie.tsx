import { memo, useCallback, useDeferredValue, useEffect, useMemo, useRef, useState } from "react";
import {
  CalendarDays,
  Check,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  Database,
  FileText,
  Link2,
  LoaderCircle,
  Pencil,
  Plus,
  RefreshCw,
  Save,
  Search,
  ShieldCheck,
  Sparkles,
  Trash2,
  UserRound,
  X,
} from "lucide-react";
import { Link as RouterLink, useLocation } from "wouter";
import { AuthDialog } from "@/components/AuthDialog";
import { PageShell, SectionHeading } from "@/components/CinemaChrome";
import { useAuth } from "@/_core/hooks/useAuth";
import { trpc } from "@/lib/trpc";
import BulkEpisodesInput from "@/components/BulkEpisodesInput";
import ImagePicker from "@/components/ImagePicker";

/* ------------------------------------------------------------------ */
/* Kiểu dữ liệu                                                        */
/* ------------------------------------------------------------------ */

type Tag = { name: string; slug?: string };
/** `role` được giữ lại để không mất dữ liệu cũ; giao diện không còn nhập vai diễn. */
type Actor = { name: string; role?: string; image: string };
type SubtitleTrackDraft = { language: string; subtitleUrl: string; subtitleVtt: string };
type Quality = { label: string; streamUrl: string; subtitleUrl: string; subtitleLabel: string; subtitleVtt: string; subtitleTracks: SubtitleTrackDraft[] };
type SourceQuality = { label: string; streamUrl: string; subtitleUrl: string | null; subtitleLabel?: string | null; subtitleTracks?: Array<{ language: string; subtitleUrl: string }> };
type SourceEpisode = {
  id: number;
  sourceId: number;
  name: string;
  streamUrl: string;
  subtitleUrl: string | null;
  subtitleLabel: string | null;
  subtitleTracks: Array<{ language: string; subtitleUrl: string }>;
  hasUploadedSubtitle: boolean;
  qualities: SourceQuality[];
};
type Source = { id: number; movieSlug: string; name: string; sortOrder: number; episodes: SourceEpisode[] };

function subtitleURLObject(value: string) {
  try { return new URL(value, window.location.origin); } catch { return null; }
}

function isInternalSubtitleRoute(value: string | null | undefined) {
  if (!value) return false;
  const url = subtitleURLObject(value);
  return Boolean(url && url.origin === window.location.origin && (url.pathname.startsWith("/api/movies/subtitle/") || url.pathname.startsWith("/uploads/movie-subs/")));
}

function displaySubtitleURL(value: string | null | undefined) {
  if (!value) return "";
  return isInternalSubtitleRoute(value) ? new URL(value, window.location.origin).toString() : value;
}

function storedSubtitleURL(value: string | null | undefined) {
  if (!value) return value || null;
  const url = subtitleURLObject(value);
  return url && url.origin === window.location.origin && (url.pathname.startsWith("/api/movies/subtitle/") || url.pathname.startsWith("/uploads/movie-subs/")) ? `${url.pathname}${url.search}` : value;
}

function isLegacyDefaultQuality(episode?: SourceEpisode) {
  return Boolean(episode && episode.qualities.length === 1 && episode.qualities[0].label === "Mặc định" && episode.qualities[0].streamUrl === episode.streamUrl && (episode.qualities[0].subtitleTracks?.length || 0) > 0);
}

type FormState = {
  name: string;
  originName: string;
  alternativeNames: string[];
  movieType: "series" | "single";
  episodeCurrent: string;
  episodeTotal: string;
  createdDate: string;
  updatedDate: string;
  tmdbId: string;
  imdbId: string;
  categories: Tag[];
  countries: Tag[];
  rating: string;
  viewsMode: "real" | "mixed";
  viewsBase: string;
  posterUrl: string;
  thumbUrl: string;
  description: string;
  actors: Actor[];
  directors: string[];
  quality: string;
  year: string;
  lang: string;
  time: string;
  status: string;
  isPublished: boolean;
};

/* ------------------------------------------------------------------ */
/* Bản nháp cũ                                                         */
/* ------------------------------------------------------------------ */

/* Tạo phim xong là form trở về trạng thái trắng, không giữ lại thông tin
   của phim vừa lưu. Hàm dưới chỉ để dọn bản nháp mà bản cũ đã ghi trong
   localStorage của trình duyệt. */
const CUSTOM_MOVIE_DRAFT_KEY = "cinemora.custom-movie-draft.v1";

function clearCustomMovieDraft() {
  try {
    window.localStorage.removeItem(CUSTOM_MOVIE_DRAFT_KEY);
  } catch {
    /* bỏ qua */
  }
}

type CustomMovieRow = Record<string, any> & {
  id: number;
  slug: string;
  name: string;
  originName?: string | null;
  posterUrl?: string | null;
  thumbUrl?: string | null;
  year?: number | null;
  movieType?: "series" | "single";
  isPublished?: boolean;
  sources?: Source[];
};

/* ------------------------------------------------------------------ */
/* Tiện ích                                                            */
/* ------------------------------------------------------------------ */

/** "2026-10-15" (hoặc ISO đầy đủ) -> "15/10/2026" để hiển thị. */
const isoToDisplay = (value: string) => {
  const iso = (value || "").slice(0, 10);
  const parts = iso.split("-");
  if (parts.length !== 3 || parts[0].length !== 4) return "";
  return `${parts[2]}/${parts[1]}/${parts[0]}`;
};

/** "15/10/2026" -> "2026-10-15"; trả về "" nếu ngày chưa hợp lệ. */
const displayToIso = (value: string) => {
  const parts = (value || "").split("/");
  if (parts.length !== 3 || parts[2].length !== 4) return "";
  const day = Number(parts[0]);
  const month = Number(parts[1]);
  const year = Number(parts[2]);
  if (!day || !month || !year || day > 31 || month > 12) return "";
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${year}-${pad(month)}-${pad(day)}`;
};

/** Mốc thời gian bất kỳ -> "yyyy-mm-dd" theo giờ máy người dùng. */
const isoDay = (value: unknown) => {
  const raw = typeof value === "string" ? value.trim() : "";
  if (!raw) return "";
  const parsed = new Date(raw);
  if (Number.isNaN(parsed.getTime())) return raw.slice(0, 10);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${parsed.getFullYear()}-${pad(parsed.getMonth() + 1)}-${pad(parsed.getDate())}`;
};

const nowLocal = () => {
  const date = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
};
const today = () => nowLocal().slice(0, 10);

/**
 * Lựa chọn nhanh cho mục Ngôn ngữ của phim thủ công.
 *
 * "Vietsub" giữ nguyên cách viết quen dùng, hai mục còn lại viết hoa đầu từ để
 * hiển thị đồng nhất trên web và trên app.
 */
const LANG_PRESETS: Array<{ value: string; label: string }> = [
  { value: "Vietsub", label: "Vietsub" },
  { value: "Thuyết Minh", label: "Thuyết Minh" },
  { value: "Lồng Tiếng", label: "Lồng Tiếng" },
];

/** Dấu nối các kiểu âm thanh khi một phim có nhiều ngôn ngữ. */
const LANG_JOIN = " + ";

/** Bỏ dấu tiếng Việt và hạ chữ thường để so khớp ngôn ngữ đã lưu với lựa chọn nhanh. */
function foldLang(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/đ/g, "d")
    .replace(/Đ/g, "D")
    .trim()
    .toLocaleLowerCase("vi-VN");
}

/**
 * Tách chuỗi ngôn ngữ đã lưu thành các lựa chọn nhanh và phần ghi tự do.
 *
 * Phim có thể có nhiều kiểu âm thanh ("Thuyết Minh + Lồng Tiếng"), và bản cũ có thể
 * lưu "Thuyết minh" chữ thường nên phép so khớp bỏ dấu và không phân biệt hoa thường.
 */
function parseLang(value: string): { presets: string[]; custom: string } {
  const parts = value
    .split(/\s*\+\s*|\s*,\s*|\s*\/\s*/)
    .map(part => part.trim())
    .filter(Boolean);
  const presets: string[] = [];
  const rest: string[] = [];
  for (const part of parts) {
    const preset = LANG_PRESETS.find(item => foldLang(item.value) === foldLang(part));
    if (preset) {
      if (!presets.includes(preset.value)) presets.push(preset.value);
    } else {
      rest.push(part);
    }
  }
  return { presets, custom: rest.join(LANG_JOIN) };
}

/** Ghép các lựa chọn thành chuỗi lưu trong cơ sở dữ liệu, ví dụ "Thuyết Minh + Lồng Tiếng". */
function composeLang(presets: string[], custom: string): string {
  return [...presets, custom.trim()].filter(Boolean).join(LANG_JOIN);
}

const MONTH_LABELS = [
  "Tháng 1", "Tháng 2", "Tháng 3", "Tháng 4", "Tháng 5", "Tháng 6",
  "Tháng 7", "Tháng 8", "Tháng 9", "Tháng 10", "Tháng 11", "Tháng 12",
];
const WEEKDAY_LABELS = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"];

type MonthCursor = { year: number; month: number };

function pad2(value: number): string {
  return String(value).padStart(2, "0");
}

function cursorFromIso(iso: string): MonthCursor {
  const match = /^(\d{4})-(\d{2})/.exec(iso.trim());
  if (match) {
    const year = Number(match[1]);
    const month = Number(match[2]) - 1;
    if (year >= 1900 && year <= 2100 && month >= 0 && month <= 11) return { year, month };
  }
  const now = new Date();
  return { year: now.getFullYear(), month: now.getMonth() };
}

function daysInMonth(year: number, month: number): number {
  return new Date(year, month + 1, 0).getDate();
}

/** Thứ Hai là cột đầu tiên, giống lịch Việt Nam. */
function firstWeekdayMonday(year: number, month: number): number {
  return (new Date(year, month, 1).getDay() + 6) % 7;
}

function isoOf(year: number, month: number, day: number): string {
  return `${year}-${pad2(month + 1)}-${pad2(day)}`;
}

function todayIso(): string {
  const now = new Date();
  return isoOf(now.getFullYear(), now.getMonth(), now.getDate());
}

/**
 * Ô nhập ngày theo dd/mm/yyyy kèm lịch chọn ngày riêng.
 *
 * Admin vừa gõ nhanh được (tự chèn dấu "/"), vừa mở được lịch để chọn: lịch có
 * nút lùi/tiến tháng, ô chọn tháng và ô nhập năm nên nhảy nhanh tới bất kỳ mốc nào.
 * Giá trị lưu trong form vẫn là yyyy-mm-dd nên phần gửi lên máy chủ không đổi.
 */
const DateField = memo(
  function DateField({ value, onChange }: { value: string; onChange: (iso: string) => void }) {
  const [text, setText] = useState(() => isoToDisplay(value));
  const [open, setOpen] = useState(false);
  const [monthOpen, setMonthOpen] = useState(false);
  const [cursor, setCursor] = useState<MonthCursor>(() => cursorFromIso(value));
  const wrapRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setText(isoToDisplay(value));
  }, [value]);

  useEffect(() => {
    if (open) setCursor(cursorFromIso(value));
  }, [open, value]);

  // Mỗi lần mở/đóng lịch thì trả bảng tháng về trạng thái xem ngày.
  useEffect(() => {
    if (!open) setMonthOpen(false);
  }, [open]);

  // Bấm ra ngoài hoặc ấn Esc là đóng lịch.
  useEffect(() => {
    if (!open) return;
    function onPointerDown(event: MouseEvent) {
      const node = wrapRef.current;
      if (node && event.target instanceof Node && !node.contains(event.target)) setOpen(false);
    }
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") setOpen(false);
    }
    document.addEventListener("mousedown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("mousedown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [open]);

  function type(raw: string) {
    const digits = raw.replace(/\D/g, "").slice(0, 8);
    const masked = [digits.slice(0, 2), digits.slice(2, 4), digits.slice(4, 8)].filter(Boolean).join("/");
    setText(masked);
    if (digits.length === 8) {
      const iso = displayToIso(masked);
      if (iso) onChange(iso);
    }
  }

  function pick(iso: string) {
    onChange(iso);
    setText(isoToDisplay(iso));
    setOpen(false);
    setMonthOpen(false);
  }

  function shiftMonth(step: number) {
    setCursor(current => {
      const next = new Date(current.year, current.month + step, 1);
      return { year: next.getFullYear(), month: next.getMonth() };
    });
  }

  function setYear(raw: string) {
    const digits = raw.replace(/\D/g, "").slice(0, 4);
    if (!digits) return;
    const year = Math.min(Math.max(Number(digits), 1900), 2100);
    setCursor(current => ({ ...current, year }));
  }

  const cells: Array<number | null> = [];
  if (open) {
    const lead = firstWeekdayMonday(cursor.year, cursor.month);
    for (let blank = 0; blank < lead; blank += 1) cells.push(null);
    for (let day = 1; day <= daysInMonth(cursor.year, cursor.month); day += 1) cells.push(day);
  }

  const currentToday = todayIso();

  return (
    <div className="custom-date-field" ref={wrapRef}>
      <input
        value={text}
        onChange={event => type(event.target.value)}
        onBlur={() => setText(isoToDisplay(value))}
        placeholder="dd/mm/yyyy"
        inputMode="numeric"
        autoComplete="off"
      />
      <button
        type="button"
        className={open ? "custom-date-pick is-open" : "custom-date-pick"}
        onClick={() => setOpen(current => !current)}
        title="Chọn ngày từ lịch"
        aria-label="Chọn ngày từ lịch"
        aria-expanded={open}
      >
        <CalendarDays size={15} />
      </button>

      {open && (
        <div className="custom-date-pop" role="dialog" aria-label="Lịch chọn ngày">
          <div className="custom-date-pop-head">
            <button type="button" className="custom-date-nav" onClick={() => shiftMonth(-1)} aria-label="Tháng trước">
              <ChevronLeft size={15} />
            </button>
            <button
              type="button"
              className={monthOpen ? "custom-date-month-btn is-open" : "custom-date-month-btn"}
              onClick={() => setMonthOpen(current => !current)}
              aria-expanded={monthOpen}
            >
              {MONTH_LABELS[cursor.month]}
              <ChevronDown size={14} />
            </button>
            <input
              className="custom-date-year"
              value={String(cursor.year)}
              onChange={event => setYear(event.target.value)}
              inputMode="numeric"
              aria-label="Chọn năm"
            />
            <button type="button" className="custom-date-nav" onClick={() => shiftMonth(1)} aria-label="Tháng sau">
              <ChevronRight size={15} />
            </button>
          </div>

          {monthOpen ? (
            <div className="custom-date-month-grid">
              {MONTH_LABELS.map((label, index) => (
                <button
                  key={label}
                  type="button"
                  className={index === cursor.month ? "custom-date-month-cell is-selected" : "custom-date-month-cell"}
                  onClick={() => {
                    setCursor(current => ({ ...current, month: index }));
                    setMonthOpen(false);
                  }}
                >
                  {label.replace("Tháng ", "T")}
                </button>
              ))}
            </div>
          ) : (
            <>
              <div className="custom-date-week">
                {WEEKDAY_LABELS.map(label => (
                  <span key={label}>{label}</span>
                ))}
              </div>

              <div className="custom-date-grid">
                {cells.map((day, index) => {
                  if (day === null) return <span key={`blank-${index}`} className="custom-date-blank" />;
                  const iso = isoOf(cursor.year, cursor.month, day);
                  const classes = ["custom-date-day"];
                  if (iso === value) classes.push("is-selected");
                  if (iso === currentToday) classes.push("is-today");
                  return (
                    <button key={iso} type="button" className={classes.join(" ")} onClick={() => pick(iso)}>
                      {day}
                    </button>
                  );
                })}
              </div>
            </>
          )}

          <div className="custom-date-pop-foot">
            <button type="button" className="custom-date-quick" onClick={() => pick(currentToday)}>
              Hôm nay
            </button>
            <button
              type="button"
              className="custom-date-quick"
              onClick={() => {
                onChange("");
                setText("");
                setOpen(false);
              }}
            >
              Xoá ngày
            </button>
          </div>
        </div>
      )}
    </div>
  );
  },
  (prev, next) => prev.value === next.value,
);


const emptyForm = (): FormState => ({
  name: "",
  originName: "",
  alternativeNames: [],
  movieType: "series",
  episodeCurrent: "",
  episodeTotal: "",
  createdDate: today(),
  updatedDate: today(),
  tmdbId: "",
  imdbId: "",
  categories: [],
  countries: [],
  rating: "",
  viewsMode: "real",
  viewsBase: "0",
  posterUrl: "",
  thumbUrl: "",
  description: "",
  actors: [],
  directors: [],
  quality: "FHD",
  lang: "Vietsub",
  time: "",
  year: "",
  status: "",
  isPublished: true,
});

function stringValue(value: unknown) {
  return value === null || value === undefined ? "" : String(value);
}

function parseJson<T>(value: unknown, fallback: T): T {
  if (Array.isArray(value)) return value as T;
  if (typeof value !== "string") return fallback;
  try {
    const parsed = JSON.parse(value);
    return parsed as T;
  } catch {
    return fallback;
  }
}

function slugify(value: string) {
  return value
    .toLocaleLowerCase("vi-VN")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/đ/gi, "d")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function formFromMovie(movie: CustomMovieRow): FormState {
  const fallback = emptyForm();
  return {
    ...fallback,
    name: movie.name || "",
    originName: stringValue(movie.originName),
    alternativeNames: parseJson<string[]>(movie.alternativeNames, []).map(String),
    movieType: movie.movieType === "single" ? "single" : "series",
    episodeCurrent: stringValue(movie.episodeCurrent),
    episodeTotal:
      movie.episodeTotal === null || movie.episodeTotal === undefined ? "" : String(movie.episodeTotal),
    createdDate: isoDay(movie.createdDate) || isoDay(movie.createdAt),
    // Ngày cập nhật luôn lấy mốc mới nhất của máy chủ, không cho sửa tay.
    updatedDate: isoDay(movie.updatedAt) || isoDay(movie.updatedDate),
    tmdbId: stringValue(movie.tmdbId),
    imdbId: stringValue(movie.imdbId),
    categories: parseJson<Tag[]>(movie.categories, []),
    countries: parseJson<Tag[]>(movie.countries, []),
    rating: stringValue(movie.rating),
    viewsMode: movie.viewsMode === "mixed" ? "mixed" : "real",
    viewsBase: stringValue(movie.viewsBase || 0),
    posterUrl: stringValue(movie.posterUrl),
    thumbUrl: stringValue(movie.thumbUrl),
    description: stringValue(movie.description),
    actors: parseJson<Actor[]>(movie.actors, []).map(actor => ({
      name: stringValue(actor.name),
      role: stringValue(actor.role),
      image: stringValue(actor.image),
    })),
    directors: parseJson<string[]>(movie.directors, []).map(String),
    quality: stringValue(movie.quality) || "FHD",
    year: movie.year ? String(movie.year) : "",
    lang: stringValue(movie.lang) || "Vietsub",
    time: stringValue(movie.time),
    status: stringValue(movie.status),
    isPublished: movie.isPublished !== false,
  };
}

function readBase64(file: File) {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = typeof reader.result === "string" ? reader.result : "";
      resolve(result.includes(",") ? result.slice(result.indexOf(",") + 1) : result);
    };
    reader.onerror = () => reject(new Error("Không thể đọc tệp phụ đề."));
    reader.readAsDataURL(file);
  });
}

/* ------------------------------------------------------------------ */
/* Ô chọn dạng danh sách (thay cho <select> mặc định)                  */
/* ------------------------------------------------------------------ */

type SelectOption<T extends string> = { value: T; label: string; hint?: string };

function SelectField<T extends string>({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: T;
  options: Array<SelectOption<T>>;
  onChange: (next: T) => void;
}) {
  const [open, setOpen] = useState(false);
  const boxRef = useRef<HTMLDivElement | null>(null);
  const current = options.find(option => option.value === value);

  useEffect(() => {
    if (!open) return;
    function handlePointer(event: MouseEvent) {
      if (!boxRef.current?.contains(event.target as Node)) setOpen(false);
    }
    function handleKey(event: KeyboardEvent) {
      if (event.key === "Escape") setOpen(false);
    }
    document.addEventListener("mousedown", handlePointer);
    document.addEventListener("keydown", handleKey);
    return () => {
      document.removeEventListener("mousedown", handlePointer);
      document.removeEventListener("keydown", handleKey);
    };
  }, [open]);

  return (
    <div className="custom-select" ref={boxRef}>
      <span className="custom-label">{label}</span>
      <button
        type="button"
        className={open ? "custom-select-trigger is-open" : "custom-select-trigger"}
        onClick={() => setOpen(current => !current)}
        aria-haspopup="listbox"
        aria-expanded={open}
      >
        <span className="custom-select-value">
          <strong>{current?.label || "Chọn"}</strong>
          {current?.hint && <small>{current.hint}</small>}
        </span>
        <ChevronDown size={15} className="custom-select-caret" />
      </button>
      {open && (
        <div className="custom-select-menu" role="listbox">
          {options.map(option => (
            <button
              key={option.value}
              type="button"
              role="option"
              aria-selected={option.value === value}
              className={option.value === value ? "is-selected" : ""}
              onClick={() => {
                onChange(option.value);
                setOpen(false);
              }}
            >
              <span>
                <strong>{option.label}</strong>
                {option.hint && <small>{option.hint}</small>}
              </span>
              {option.value === value && <Check size={14} />}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Nhập nhiều giá trị dạng chip (tên khác, đạo diễn)                   */
/* ------------------------------------------------------------------ */

function ChipField({
  label,
  hint,
  placeholder,
  values,
  onAdd,
  onRemove,
}: {
  label: string;
  hint?: string;
  placeholder: string;
  values: string[];
  onAdd: (value: string) => void;
  onRemove: (value: string) => void;
}) {
  const [draft, setDraft] = useState("");

  function commit() {
    if (!draft.trim()) return;
    onAdd(draft);
    setDraft("");
  }

  return (
    <div className="custom-chip-field">
      <div className="custom-field-heading">
        <strong>{label}</strong>
        {hint && <span>{hint}</span>}
      </div>
      <div className="custom-chip-input">
        {values.length > 0 && (
          <div className="custom-chips">
            {values.map(name => (
              <span key={name}>
                {name}
                <button type="button" onClick={() => onRemove(name)} aria-label={`Xoá ${name}`}>
                  <X size={12} />
                </button>
              </span>
            ))}
          </div>
        )}
        <input
          value={draft}
          onChange={event => setDraft(event.target.value)}
          onKeyDown={event => {
            if (event.key === "Enter") {
              event.preventDefault();
              commit();
            }
          }}
          onBlur={commit}
          placeholder={placeholder}
        />
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Chọn nhiều thể loại / quốc gia                                      */
/* ------------------------------------------------------------------ */

/* ------------------------------------------------------------------ */
/* Tìm diễn viên trực tiếp từ trình duyệt                              */
/* Dùng khi máy chủ hosting bị chặn api.themoviedb.org / wikidata.org. */
/* ------------------------------------------------------------------ */

/* Ghi nhớ việc máy chủ hosting không gọi được nguồn để lần sau tìm thẳng từ trình duyệt. */
const ACTOR_SERVER_FLAG = "cinemora.actorSearch.serverUnavailable";
const ACTOR_FLAG_TTL = 24 * 60 * 60 * 1000;

function readActorServerFlag(): boolean {
  try {
    const raw = window.localStorage.getItem(ACTOR_SERVER_FLAG);
    if (!raw) return false;
    const at = Number(raw);
    return Number.isFinite(at) && Date.now() - at < ACTOR_FLAG_TTL;
  } catch {
    return false;
  }
}

type BrowserActor = {
  name: string;
  image: string;
  description: string;
  imdbId: string;
  tmdbId: number | null;
  source: "tmdb" | "wikidata";
};

/**
 * Chuẩn hoá tên để so trùng: bỏ dấu, bỏ khoảng trắng và dấu câu nhưng GIỮ chữ của
 * mọi hệ chữ. Bản cũ chỉ giữ [a-z0-9] nên tên chữ Hán/Hàn/Nhật bị rút thành chuỗi
 * rỗng và bị coi là trùng với nhau, khiến TMDB trả về diễn viên mà không thêm được ai.
 */
function normalizeActorName(value: string) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/đ/g, "d")
    .replace(/Đ/g, "D")
    .toLocaleLowerCase("vi-VN")
    .replace(/[\s.,'’"“”\-–—_:;!?()\[\]{}·•/\\|@#$%^&*+=~`<>]+/g, "");
}

function isLatinActorName(value: string) {
  return value.length > 0 && /^[\x20-\x7E]+$/.test(value);
}

/** TMDB gọi thẳng từ trình duyệt (TMDB có mở CORS). */
async function browserSearchTmdb(query: string, key: string): Promise<BrowserActor[]> {
  const authHeaders: Record<string, string> = key.length > 40 ? { authorization: `Bearer ${key}` } : {};
  const build = (path: string, extra: Record<string, string> = {}) => {
    const params = new URLSearchParams(extra);
    if (key.length <= 40) params.set("api_key", key);
    return `https://api.themoviedb.org/3${path}?${params.toString()}`;
  };

  const response = await fetch(build("/search/person", { query, language: "vi-VN", include_adult: "false", page: "1" }), {
    headers: authHeaders,
  });
  if (!response.ok) throw new Error(`TMDB trả về mã ${response.status}`);
  const payload = await response.json();
  const people: Array<Record<string, unknown>> = (Array.isArray(payload?.results) ? payload.results : []).filter(
    (person: Record<string, unknown>) => !person?.known_for_department || person.known_for_department === "Acting",
  );
  const wanted = normalizeActorName(query);

  return Promise.all(
    people.slice(0, 6).map(async person => {
      let name = String(person?.name ?? "");
      let imdbId = "";
      let image = person?.profile_path ? `https://image.tmdb.org/t/p/w185${String(person.profile_path)}` : "";
      if (person?.id) {
        try {
          const detailResponse = await fetch(build(`/person/${String(person.id)}`, { language: "vi-VN" }), { headers: authHeaders });
          if (detailResponse.ok) {
            const detail = await detailResponse.json();
            imdbId = String(detail?.imdb_id ?? "");
            const aliases: string[] = Array.isArray(detail?.also_known_as) ? detail.also_known_as.map(String) : [];
            const latin = aliases.find(alias => isLatinActorName(alias) && alias.length > 2 && !/\d/.test(alias)) ?? "";
            if (!isLatinActorName(name)) name = aliases.find(alias => normalizeActorName(alias) === wanted) ?? latin ?? name;
            if (!image && detail?.profile_path) image = `https://image.tmdb.org/t/p/w185${String(detail.profile_path)}`;
          }
        } catch {
          /* giữ dữ liệu từ bước tìm kiếm */
        }
      }
      return {
        name,
        image,
        description: "",
        imdbId,
        tmdbId: typeof person?.id === "number" ? person.id : null,
        source: "tmdb" as const,
      };
    }),
  ).then(items => items.filter(item => item.name.length > 0));
}

/** Wikidata gọi thẳng từ trình duyệt (kèm origin=* để được phép CORS). */
async function browserSearchWikidata(query: string): Promise<BrowserActor[]> {
  const searchUrl = `https://www.wikidata.org/w/api.php?action=wbsearchentities&search=${encodeURIComponent(
    query,
  )}&language=vi&uselang=vi&format=json&limit=6&origin=*`;
  const response = await fetch(searchUrl);
  if (!response.ok) throw new Error(`Wikidata trả về mã ${response.status}`);
  const payload = await response.json();
  const hits: Array<{ id?: string; label?: string; description?: string }> = Array.isArray(payload?.search) ? payload.search : [];

  const items = await Promise.all(
    hits.slice(0, 5).map(async hit => {
      let image = "";
      let imdbId = "";
      if (hit.id) {
        try {
          const entityResponse = await fetch(`https://www.wikidata.org/wiki/Special:EntityData/${hit.id}.json?origin=*`);
          if (entityResponse.ok) {
            const data = await entityResponse.json();
            const claims = data?.entities?.[hit.id]?.claims ?? {};
            const imageName = claims?.P18?.[0]?.mainsnak?.datavalue?.value;
            if (typeof imageName === "string") {
              image = `https://commons.wikimedia.org/wiki/Special:FilePath/${encodeURIComponent(imageName)}?width=320`;
            }
            const imdb = claims?.P345?.[0]?.mainsnak?.datavalue?.value;
            if (typeof imdb === "string") imdbId = imdb;
          }
        } catch {
          /* bỏ qua ảnh/mã IMDb nếu lỗi */
        }
      }
      return {
        name: String(hit.label ?? ""),
        image,
        description: String(hit.description ?? ""),
        imdbId,
        tmdbId: null,
        source: "wikidata" as const,
      };
    }),
  );
  return items.filter(item => item.name.length > 0);
}

/**
 * Lấy diễn viên + đạo diễn từ trình duyệt khi máy chủ hosting không gọi được TMDB.
 *
 * TMDB ID dùng thẳng; IMDB ID được đổi sang TMDB ID qua endpoint find.
 */
async function browserFetchMovieCredits(
  tmdbId: string,
  imdbId: string,
  key: string,
  movieType: "series" | "single" | null,
  wantedTitle: string,
  limit = 30,
): Promise<{ title: string; directors: string[]; actors: Array<{ name: string; image: string }> }> {
  const authHeaders: Record<string, string> = key.length > 40 ? { authorization: `Bearer ${key}` } : {};
  const build = (path: string, extra: Record<string, string> = {}) => {
    const params = new URLSearchParams(extra);
    if (key.length <= 40) params.set("api_key", key);
    return `https://api.themoviedb.org/3${path}?${params.toString()}`;
  };
  const getJson = async (url: string): Promise<any> => {
    const response = await fetch(url, { headers: authHeaders });
    if (!response.ok) throw new Error(`TMDB trả về mã ${response.status}`);
    return response.json();
  };

  let id = tmdbId.replace(/[^0-9]/g, "");
  let preferred: "movie" | "tv" | null = null;
  if (!id && imdbId) {
    const found = await getJson(build(`/find/${encodeURIComponent(imdbId)}`, { external_source: "imdb_id" }));
    const movieId = found?.movie_results?.[0]?.id;
    const tvId = found?.tv_results?.[0]?.id;
    if (movieId) {
      id = String(movieId);
      preferred = "movie";
    } else if (tvId) {
      id = String(tvId);
      preferred = "tv";
    }
  }
  if (!id) throw new Error("Không tìm thấy phim trên TMDB");

  // Phim bộ của form thì ưu tiên nhánh TV: mã số có thể trùng nhau giữa hai nhánh TMDB.
  if (!preferred && movieType) preferred = movieType === "series" ? "tv" : "movie";
  const order: Array<"movie" | "tv"> = preferred
    ? [preferred, preferred === "movie" ? "tv" : "movie"]
    : ["movie", "tv"];

  const loaded: Array<{ title: string; directors: string[]; actors: Array<{ name: string; image: string }> }> = [];
  for (const mediaType of order) {
    try {
      // Phim bộ: /credits chỉ trả vài người, danh sách đầy đủ nằm ở /aggregate_credits.
      const creditPaths =
        mediaType === "tv"
          ? [`/${mediaType}/${id}/aggregate_credits`, `/${mediaType}/${id}/credits`]
          : [`/${mediaType}/${id}/credits`];
      let credits: any = null;
      for (const path of creditPaths) {
        try {
          // en-US để tên diễn viên ở dạng Latin, dễ đọc và dễ tra lại.
          const payload = await getJson(build(path, { language: "en-US" }));
          if (!payload) continue;
          if (!credits || (payload?.cast ?? []).length > (credits?.cast ?? []).length) credits = payload;
        } catch {
          /* thử đường còn lại */
        }
      }
      if (!credits) continue;
      // Phim bộ gom đạo diễn mọi tập: cân theo số tập rồi chỉ giữ nhóm chính.
      const rankedDirectors: Array<{ name: string; weight: number }> = [];
      for (const person of credits?.crew ?? []) {
        const jobs: string[] = (person?.jobs ?? []).map((item: any) => String(item?.job ?? ""));
        const isCreator = person?.job === "Creator" || jobs.includes("Creator");
        const isDirector = person?.job === "Director" || jobs.includes("Director") || isCreator;
        if (!isDirector) continue;
        const name = String(person?.name ?? "").trim();
        if (!name) continue;
        const episodes = Number(person?.total_episode_count ?? 0) || 0;
        const weight = isCreator ? episodes + 1000 : episodes;
        const existing = rankedDirectors.find(item => item.name === name);
        if (existing) existing.weight = Math.max(existing.weight, weight);
        else rankedDirectors.push({ name, weight });
      }
      const directors: string[] = rankedDirectors
        .sort((a, b) => b.weight - a.weight)
        .slice(0, 6)
        .map(item => item.name);
      const actors = (credits?.cast ?? [])
        .slice(0, limit)
        .map((person: any) => ({
          name: String(person?.name ?? person?.original_name ?? "").trim(),
          image: person?.profile_path ? `https://image.tmdb.org/t/p/w185${person.profile_path}` : "",
        }))
        .filter((person: { name: string }) => person.name.length > 0);
      let title = "";
      try {
        // Tiêu đề đối chiếu dùng bản tiếng Anh cho khớp tên quốc tế nhập ở ô Tên phim.
        const detail = await getJson(build(`/${mediaType}/${id}`, { language: "en-US" }));
        title = String(detail?.title ?? detail?.name ?? "");
        for (const person of detail?.created_by ?? []) {
          const name = String(person?.name ?? "").trim();
          if (name && !directors.includes(name)) directors.unshift(name);
        }
        directors.splice(6);
      } catch {
        /* chỉ cần credits */
      }
      if (actors.length > 0 || directors.length > 0) loaded.push({ title, directors, actors });
    } catch {
      /* thử nhánh còn lại */
    }
  }
  if (loaded.length === 0) throw new Error("TMDB không có dữ liệu diễn viên cho phim này");

  // Mã số trùng nhau giữa phim lẻ và phim bộ: chọn bản khớp tên phim nhất.
  const wanted = normalizeTitle(wantedTitle);
  if (wanted) {
    let best = loaded[0];
    let bestScore = titleScore(best.title, wantedTitle);
    for (const item of loaded.slice(1)) {
      const score = titleScore(item.title, wantedTitle);
      if (score > bestScore) {
        best = item;
        bestScore = score;
      }
    }
    if (bestScore > 0) return best;
  }

  // Không đối chiếu được tên thì chọn nhánh đầy đủ dữ liệu hơn hẳn: mã số TMDB có thể
  // trùng giữa phim lẻ và phim bộ, nhánh ưu tiên có khi chỉ là phim khác cùng số.
  const preferredFirst = loaded[0];
  const richest = [...loaded].sort((a, b) => b.actors.length - a.actors.length)[0];
  if (richest !== preferredFirst && richest.actors.length >= Math.max(5, preferredFirst.actors.length * 3)) {
    return richest;
  }
  return preferredFirst;
}

/** Rút gọn tiêu đề để so khớp (bỏ dấu, khoảng trắng và dấu câu, giữ mọi hệ chữ). */
function normalizeTitle(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/đ/g, "d")
    .replace(/Đ/g, "D")
    .toLocaleLowerCase("vi-VN")
    .replace(/[\s.,'’"“”\-–—_:;!?()\[\]{}·•/\\|@#$%^&*+=~`<>]+/g, "");
}

/** Điểm khớp tiêu đề: trùng hẳn 3, chứa nhau 2, không khớp 0. */
function titleScore(candidate: string, wanted: string): number {
  const a = normalizeTitle(candidate);
  const b = normalizeTitle(wanted);
  if (!a || !b) return 0;
  if (a === b) return 3;
  if (a.includes(b) || b.includes(a)) return 2;
  return 0;
}

/** Tìm diễn viên từ trình duyệt: TMDB trước, không có kết quả thì sang Wikidata. */
async function browserSearchActors(query: string, tmdbKey: string): Promise<{ items: BrowserActor[]; source: "tmdb" | "wikidata" }> {
  if (tmdbKey) {
    const items = await browserSearchTmdb(query, tmdbKey);
    if (items.length > 0) return { items, source: "tmdb" };
  }
  return { items: await browserSearchWikidata(query), source: "wikidata" };
}

function TagPicker({
  label,
  options,
  selected,
  onChange,
}: {
  label: string;
  options: Tag[];
  selected: Tag[];
  onChange: (next: Tag[]) => void;
}) {
  const [search, setSearch] = useState("");
  const keyword = search.trim().toLocaleLowerCase("vi-VN");
  const filtered = useMemo(
    () => options.filter(option => option.name.toLocaleLowerCase("vi-VN").includes(keyword)),
    [options, keyword],
  );
  const selectedKeys = useMemo(
    () => new Set(selected.map(item => item.slug || item.name)),
    [selected],
  );

  function toggle(option: Tag) {
    const key = option.slug || option.name;
    if (selectedKeys.has(key)) {
      onChange(selected.filter(item => (item.slug || item.name) !== key));
      return;
    }
    onChange([...selected, { name: option.name, slug: option.slug || slugify(option.name) }]);
  }

  function selectAllFiltered() {
    const additions = filtered
      .filter(option => !selectedKeys.has(option.slug || option.name))
      .map(option => ({ name: option.name, slug: option.slug || slugify(option.name) }));
    if (additions.length) onChange([...selected, ...additions]);
  }

  /**
   * Thêm mục ngoài danh sách: admin gõ tên rồi ấn Enter.
   *
   * Nếu tên trùng một lựa chọn có sẵn thì chọn luôn lựa chọn đó, còn không thì
   * tạo mục riêng với slug sinh từ tên.
   */
  function addCustom(raw: string) {
    const name = raw.trim().replace(/\s+/g, " ");
    if (!name) return;
    const key = name.toLocaleLowerCase("vi-VN");
    const existed = options.find(option => option.name.toLocaleLowerCase("vi-VN") === key);
    const entry = existed
      ? { name: existed.name, slug: existed.slug || slugify(existed.name) }
      : { name, slug: slugify(name) };
    const entryKey = entry.slug || entry.name;
    if (!selectedKeys.has(entryKey)) onChange([...selected, entry]);
    setSearch("");
  }

  // Có chữ trong ô tìm kiếm mà chưa trùng lựa chọn nào thì gợi ý thêm mới.
  const canAddCustom =
    keyword.length > 0 && !options.some(option => option.name.toLocaleLowerCase("vi-VN") === keyword);

  return (
    <div className="custom-tag-picker">
      <div className="custom-field-heading">
        <strong>{label}</strong>
        <span className={selected.length ? "is-active" : ""}>
          {selected.length ? `${selected.length} đã chọn` : "Chưa chọn"}
        </span>
      </div>

      {selected.length > 0 && (
        <div className="custom-tag-selected">
          {selected.map(item => (
            <button
              key={item.slug || item.name}
              type="button"
              onClick={() => onChange(selected.filter(entry => (entry.slug || entry.name) !== (item.slug || item.name)))}
              title={`Bỏ chọn ${item.name}`}
            >
              {item.name}
              <X size={11} />
            </button>
          ))}
        </div>
      )}

      <div className="custom-tag-toolbar">
        <label className="custom-search">
          <Search size={14} />
          <input
            value={search}
            onChange={event => setSearch(event.target.value)}
            onKeyDown={event => {
              if (event.key !== "Enter") return;
              event.preventDefault();
              addCustom(search);
            }}
            placeholder={`Tìm hoặc gõ mới rồi ấn Enter…`}
          />
          {search && (
            <button type="button" onClick={() => setSearch("")} aria-label="Xoá tìm kiếm">
              <X size={12} />
            </button>
          )}
        </label>
        <div className="custom-tag-actions">
          {canAddCustom && (
            <button type="button" className="is-add" onClick={() => addCustom(search)}>
              <Plus size={12} /> Thêm “{search.trim()}”
            </button>
          )}
          <button type="button" onClick={selectAllFiltered} disabled={filtered.length === 0}>
            Chọn tất cả
          </button>
          <button type="button" onClick={() => onChange([])} disabled={selected.length === 0}>
            Bỏ chọn hết
          </button>
        </div>
      </div>

      <div className="custom-tag-grid">
        {filtered.map(option => {
          const isSelected = selectedKeys.has(option.slug || option.name);
          return (
            <button
              key={option.slug || option.name}
              type="button"
              className={isSelected ? "is-selected" : ""}
              onClick={() => toggle(option)}
            >
              <span>{option.name}</span>
              {isSelected && <Check size={12} />}
            </button>
          );
        })}
        {filtered.length === 0 && (
          <span className="custom-muted">
            {canAddCustom
              ? `Chưa có trong danh sách — ấn Enter để thêm “${search.trim()}”.`
              : "Không tìm thấy lựa chọn phù hợp."}
          </span>
        )}
      </div>

      <p className="custom-tag-hint">
        Gõ tên rồi ấn Enter để thêm mục riêng ngoài danh sách. Mục tự thêm cũng nằm trong danh sách đã chọn ở
        trên và bỏ chọn được như bình thường.
      </p>
    </div>
  );
}
/* ------------------------------------------------------------------ */
/* Trình soạn tập phim (kèm nhiều chất lượng)                          */
/* ------------------------------------------------------------------ */

type EpisodePayload = {
  name: string;
  streamUrl: string;
  subtitleUrl?: string | null;
  subtitleLabel?: string | null;
  subtitleVtt?: string | null;
  subtitleTracks?: Array<{ language: string; subtitleUrl?: string | null; subtitleVtt?: string | null }>;
  qualities?: Array<{ label: string; streamUrl: string; subtitleUrl?: string | null; subtitleLabel?: string | null; subtitleVtt?: string | null; subtitleTracks?: Array<{ language: string; subtitleUrl?: string | null; subtitleVtt?: string | null }> }>;
};

function SourceEpisodeEditor({
  initial,
  onSubmit,
  onCancel,
  pending,
}: {
  initial?: SourceEpisode;
  onSubmit: (payload: EpisodePayload) => Promise<void>;
  onCancel?: () => void;
  pending?: boolean;
}) {
  const uploadSubtitle = trpc.movieSources.uploadSubtitle.useMutation();
  const initialSubtitleRoute = isInternalSubtitleRoute(initial?.subtitleUrl) ? displaySubtitleURL(initial?.subtitleUrl) : "";
  const [name, setName] = useState(initial?.name || "");
  const [streamUrl, setStreamUrl] = useState(initial?.streamUrl || "");
  const [subtitleUrl, setSubtitleUrl] = useState(initialSubtitleRoute || displaySubtitleURL(initial?.subtitleUrl));
  const [subtitleLabel, setSubtitleLabel] = useState(initial?.subtitleLabel || "");
  const [subtitleVtt, setSubtitleVtt] = useState("");
  const [preserveExistingSubtitle, setPreserveExistingSubtitle] = useState(isInternalSubtitleRoute(initial?.subtitleUrl));
  const [episodeSubtitleTracks, setEpisodeSubtitleTracks] = useState<SubtitleTrackDraft[]>(() => {
    const legacyTracks = isLegacyDefaultQuality(initial) ? initial?.qualities[0]?.subtitleTracks || [] : [];
    return (initial?.subtitleTracks?.length ? initial.subtitleTracks : legacyTracks).map(track => ({ language: track.language, subtitleUrl: displaySubtitleURL(track.subtitleUrl), subtitleVtt: "" }));
  });
  const [qualities, setQualities] = useState<Quality[]>(
    (initial?.qualities || []).filter(item => !isLegacyDefaultQuality(initial) || item.label !== "Mặc định").map(item => ({
      label: item.label,
      streamUrl: item.streamUrl,
      subtitleUrl: displaySubtitleURL(item.subtitleUrl),
      subtitleLabel: item.subtitleLabel || "",
      subtitleVtt: "",
      subtitleTracks: (item.subtitleTracks || []).map(track => ({ language: track.language, subtitleUrl: displaySubtitleURL(track.subtitleUrl), subtitleVtt: "" })),
    })),
  );
  const [error, setError] = useState<string | null>(null);

  function updateQuality(index: number, patch: Partial<Quality>) {
    setQualities(current =>
      current.map((quality, itemIndex) => (itemIndex === index ? { ...quality, ...patch } : quality)),
    );
  }

  async function uploadQualitySubtitle(index: number, file: File | undefined) {
    if (!file) return;
    try {
      const base64 = await readBase64(file);
      const result = await uploadSubtitle.mutateAsync({ base64, filename: file.name });
      updateQuality(index, { subtitleUrl: result.url, subtitleVtt: "" });
    } catch (uploadError) {
      setError(uploadError instanceof Error ? uploadError.message : "Không thể tải phụ đề lên.");
    }
  }

  async function uploadEpisodeSubtitle(file: File | undefined) {
    if (!file) return;
    try {
      const base64 = await readBase64(file);
      const result = await uploadSubtitle.mutateAsync({ base64, filename: file.name });
      setSubtitleUrl(displaySubtitleURL(result.url));
      setSubtitleVtt(result.content);
      setPreserveExistingSubtitle(false);
    } catch (uploadError) {
      setError(uploadError instanceof Error ? uploadError.message : "Không thể tải phụ đề lên.");
    }
  }

  async function uploadEpisodeTrack(index: number, file: File | undefined) {
    if (!file) return;
    try {
      const base64 = await readBase64(file);
      const result = await uploadSubtitle.mutateAsync({ base64, filename: file.name });
      setEpisodeSubtitleTracks(current => current.map((track, trackIndex) => trackIndex === index ? { ...track, subtitleUrl: displaySubtitleURL(result.url), subtitleVtt: result.content } : track));
    } catch (uploadError) {
      setError(uploadError instanceof Error ? uploadError.message : "Không thể tải phụ đề lên.");
    }
  }

  async function uploadQualityTrack(index: number, trackIndex: number, file: File | undefined) {
    if (!file) return;
    try {
      const base64 = await readBase64(file);
      const result = await uploadSubtitle.mutateAsync({ base64, filename: file.name });
      updateQuality(index, {
        subtitleTracks: qualities[index].subtitleTracks.map((track, currentIndex) => currentIndex === trackIndex
          ? { ...track, subtitleUrl: displaySubtitleURL(result.url), subtitleVtt: result.content }
          : track),
      });
    } catch (uploadError) {
      setError(uploadError instanceof Error ? uploadError.message : "Không thể tải phụ đề lên.");
    }
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setError(null);
    if (!name.trim()) return setError("Vui lòng nhập tên tập.");
    try {
      new URL(streamUrl.trim());
    } catch {
      return setError("Link M3U8 phải là một URL hợp lệ.");
    }
    for (const quality of qualities) {
      if (!quality.label.trim() || !quality.streamUrl.trim()) {
        return setError("Mỗi chất lượng cần nhãn và link M3U8.");
      }
      try {
        new URL(quality.streamUrl.trim());
      } catch {
        return setError("Link M3U8 của chất lượng phải là URL hợp lệ.");
      }
    }
    const keepExistingSubtitle = preserveExistingSubtitle && initialSubtitleRoute === subtitleUrl.trim() && !subtitleVtt;
    await onSubmit({
      name: name.trim(),
      streamUrl: streamUrl.trim(),
      subtitleUrl: keepExistingSubtitle ? undefined : storedSubtitleURL(subtitleUrl.trim()),
      subtitleLabel: subtitleLabel.trim() || null,
      subtitleVtt: keepExistingSubtitle ? undefined : (subtitleVtt || null),
      subtitleTracks: episodeSubtitleTracks.map(track => ({
        language: track.language.trim(),
        subtitleUrl: storedSubtitleURL(track.subtitleUrl.trim()),
        subtitleVtt: track.subtitleVtt || null,
      })).filter(track => track.language && (track.subtitleUrl || track.subtitleVtt)),
      qualities: qualities.length ? qualities.map(item => ({
        label: item.label.trim(),
        streamUrl: item.streamUrl.trim(),
        subtitleUrl: storedSubtitleURL(item.subtitleUrl.trim()),
        subtitleLabel: item.subtitleLabel.trim() || null,
        subtitleVtt: item.subtitleVtt || null,
        subtitleTracks: item.subtitleTracks.map(track => ({
          language: track.language.trim(),
          subtitleUrl: storedSubtitleURL(track.subtitleUrl.trim()),
          subtitleVtt: track.subtitleVtt || null,
        })).filter(track => track.language && (track.subtitleUrl || track.subtitleVtt)),
      })) : undefined,
    });
  }

  return (
    <form className="custom-episode-editor" onSubmit={submit}>
      <div className="custom-editor-heading">
        <strong>{initial ? "Chỉnh sửa tập" : "Thêm tập mới"}</strong>
        {onCancel && (
          <button type="button" className="custom-icon-button" onClick={onCancel} aria-label="Đóng">
            <X size={15} />
          </button>
        )}
      </div>

      <div className="custom-form-grid two">
        <label>
          Tên tập
          <input value={name} onChange={event => setName(event.target.value)} placeholder="Ví dụ: Tập 01" required />
        </label>
        <label>
          Link M3U8
          <input
            type="url"
            value={streamUrl}
            onChange={event => setStreamUrl(event.target.value)}
            placeholder="https://…/playlist.m3u8"
            required
          />
        </label>
      </div>

      <fieldset className="custom-subtitle-fieldset">
        <legend>Phụ đề tập (tuỳ chọn)</legend>
        <div className="custom-form-grid three custom-subtitle-main-grid">
          <label>
            Link phụ đề
            <input
              type={isInternalSubtitleRoute(subtitleUrl) ? "text" : "url"}
              value={subtitleUrl}
              onChange={event => {
                setSubtitleUrl(event.target.value);
                setSubtitleVtt("");
                setPreserveExistingSubtitle(false);
              }}
              placeholder="https://…/subtitle.vtt"
            />
          </label>
          <label className="custom-file-label">
            Hoặc tải tệp .vtt/.srt
            <input
              type="file"
              accept=".vtt,.srt,text/vtt,application/x-subrip"
              onChange={event => {
                void uploadEpisodeSubtitle(event.target.files?.[0]);
                event.currentTarget.value = "";
              }}
            />
          </label>
          <label className="custom-subtitle-label-field">
            Ngôn ngữ phụ đề
            <input value={subtitleLabel} onChange={event => setSubtitleLabel(event.target.value)} placeholder="Ví dụ: Tiếng Việt / English" maxLength={80} />
          </label>
        </div>
        <textarea
          value={subtitleVtt}
          onChange={event => { setSubtitleVtt(event.target.value); setPreserveExistingSubtitle(false); }}
          placeholder="Hoặc dán nội dung WebVTT…"
          rows={3}
        />
      </fieldset>

      <div className="custom-episode-tracks">
        <div className="custom-quality-tracks-heading">
          <div><strong>Subtitle theo ngôn ngữ của tập</strong><span>Thêm nhiều ngôn ngữ mà không cần tạo quality riêng.</span></div>
          <button type="button" className="button button-muted" onClick={() => setEpisodeSubtitleTracks(current => [...current, { language: "English", subtitleUrl: "", subtitleVtt: "" }])}><Plus size={13} /> Thêm ngôn ngữ</button>
        </div>
        {episodeSubtitleTracks.map((track, trackIndex) => <div className="custom-quality-track-row" key={`episode-${trackIndex}`}>
          <input value={track.language} placeholder="Tiếng Việt / English / 한국어" aria-label="Ngôn ngữ subtitle của tập" onChange={event => setEpisodeSubtitleTracks(current => current.map((item, index) => index === trackIndex ? { ...item, language: event.target.value } : item))} />
          <input type="url" value={track.subtitleUrl} placeholder="URL .vtt của ngôn ngữ này" onChange={event => setEpisodeSubtitleTracks(current => current.map((item, index) => index === trackIndex ? { ...item, subtitleUrl: event.target.value, subtitleVtt: "" } : item))} />
          <label className="subtitle-track-file-picker"><span>{track.subtitleVtt ? "Đã tải file" : "Chọn .vtt/.srt"}</span><input type="file" accept=".vtt,.srt,text/vtt,application/x-subrip" aria-label="Upload subtitle của tập" onChange={event => { void uploadEpisodeTrack(trackIndex, event.target.files?.[0]); event.currentTarget.value = ""; }} /></label>
          <button type="button" className="custom-icon-danger" onClick={() => setEpisodeSubtitleTracks(current => current.filter((_, index) => index !== trackIndex))} aria-label="Xóa subtitle"><Trash2 size={14} /></button>
        </div>)}
      </div>

      <div className="custom-quality-heading">
        <div>
          <strong>Chất lượng của tập</strong>
          <span>Mỗi dòng có link M3U8 và phụ đề riêng. Không thêm dòng nào thì dùng link của tập.</span>
        </div>
        <button
          type="button"
          className="button button-ghost"
          onClick={() =>
            setQualities(current => [...current, { label: "1080p", streamUrl: "", subtitleUrl: "", subtitleLabel: "", subtitleVtt: "", subtitleTracks: [] }])
          }
          disabled={qualities.length >= 20}
        >
          <Plus size={14} /> Thêm chất lượng
        </button>
      </div>

      {qualities.map((quality, index) => (
        <div className="custom-quality-row" key={`${index}-${quality.label}`}>
          <div className="custom-quality-row-head">
            <strong>Chất lượng {index + 1}</strong>
            <button
              type="button"
              className="custom-icon-danger"
              onClick={() => setQualities(current => current.filter((_, itemIndex) => itemIndex !== index))}
              aria-label="Xoá chất lượng"
            >
              <Trash2 size={14} />
            </button>
          </div>
          <div className="custom-form-grid three">
            <label>
              Nhãn
              <input
                value={quality.label}
                onChange={event => updateQuality(index, { label: event.target.value })}
                placeholder="1080p"
              />
            </label>
            <label className="wide">
              Link M3U8
              <input
                type="url"
                value={quality.streamUrl}
                onChange={event => updateQuality(index, { streamUrl: event.target.value })}
                placeholder="https://…/1080p.m3u8"
              />
            </label>
            <label>
              Phụ đề URL
              <input
                type="url"
                value={quality.subtitleUrl}
                onChange={event => updateQuality(index, { subtitleUrl: event.target.value, subtitleVtt: "" })}
                placeholder="https://…/sub.vtt"
              />
            </label>
            <label>
              Tên subtitle
              <input value={quality.subtitleLabel} onChange={event => updateQuality(index, { subtitleLabel: event.target.value })} placeholder="Tiếng Việt / English" maxLength={80} />
            </label>
          </div>
          <div className="custom-quality-subtitle-tools">
            <label className="custom-file-label">
              Tải tệp phụ đề riêng
              <input
                type="file"
                accept=".vtt,.srt,text/vtt,application/x-subrip"
                onChange={event => {
                  void uploadQualitySubtitle(index, event.target.files?.[0]);
                  event.currentTarget.value = "";
                }}
              />
            </label>
            <textarea
              value={quality.subtitleVtt}
              onChange={event => updateQuality(index, { subtitleVtt: event.target.value, subtitleUrl: "" })}
              placeholder="Hoặc dán VTT cho chất lượng này…"
              rows={2}
            />
            <div className="custom-quality-tracks-heading">
              <strong>Subtitle theo ngôn ngữ</strong>
              <button type="button" className="button button-muted" onClick={() => updateQuality(index, { subtitleTracks: [...quality.subtitleTracks, { language: "English", subtitleUrl: "", subtitleVtt: "" }] })}><Plus size={13} /> Thêm ngôn ngữ</button>
            </div>
            {quality.subtitleTracks.map((track, trackIndex) => <div className="custom-quality-track-row" key={`${index}-${trackIndex}`}>
              <input value={track.language} placeholder="Tiếng Việt / English / 한국어" aria-label="Ngôn ngữ subtitle" onChange={event => updateQuality(index, { subtitleTracks: quality.subtitleTracks.map((item, currentIndex) => currentIndex === trackIndex ? { ...item, language: event.target.value } : item) })} />
              <input type="url" value={track.subtitleUrl} placeholder="URL .vtt của ngôn ngữ này" onChange={event => updateQuality(index, { subtitleTracks: quality.subtitleTracks.map((item, currentIndex) => currentIndex === trackIndex ? { ...item, subtitleUrl: event.target.value, subtitleVtt: "" } : item) })} />
              <label className="subtitle-track-file-picker"><span>{track.subtitleVtt ? "Đã tải file" : "Chọn .vtt/.srt"}</span><input type="file" accept=".vtt,.srt,text/vtt,application/x-subrip" aria-label="Upload subtitle" onChange={event => { void uploadQualityTrack(index, trackIndex, event.target.files?.[0]); event.currentTarget.value = ""; }} /></label>
              <button type="button" className="custom-icon-danger" onClick={() => updateQuality(index, { subtitleTracks: quality.subtitleTracks.filter((_, currentIndex) => currentIndex !== trackIndex) })} aria-label="Xoá subtitle"><Trash2 size={14} /></button>
            </div>)}
          </div>
        </div>
      ))}

      {error && <p className="admin-tv-error">{error}</p>}
      <div className="custom-editor-actions">
        <button className="button button-primary" disabled={pending || uploadSubtitle.isPending}>
          <Save size={14} />
          {pending || uploadSubtitle.isPending ? "Đang lưu…" : initial ? "Lưu tập" : "Thêm tập"}
        </button>
        {onCancel && (
          <button type="button" className="button button-ghost" onClick={onCancel}>
            Huỷ
          </button>
        )}
      </div>
    </form>
  );
}

/* ------------------------------------------------------------------ */
/* Quản lý nguồn & tập của phim                                        */
/* ------------------------------------------------------------------ */

/** Cuộn tới đúng tập vừa mở form sửa để không bị khuất trong danh sách có thanh cuộn. */
function scrollEpisodeIntoView(id: number) {
  window.requestAnimationFrame(() => {
    const node = document.querySelector(`[data-episode-id="${id}"]`);
    node?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  });
}

const SourcesManager = memo(function SourcesManager({ slug }: { slug: string }) {
  const [sourceName, setSourceName] = useState("");
  const [addingSource, setAddingSource] = useState(false);
  const [editingSource, setEditingSource] = useState<number | null>(null);
  const [sourceDraft, setSourceDraft] = useState("");
  const [editingEpisode, setEditingEpisode] = useState<number | null>(null);
  // Nguồn đang mở ô "dán danh sách nhiều tập".
  const [bulkSourceId, setBulkSourceId] = useState<number | null>(null);
  const [addEpisodeRevision, setAddEpisodeRevision] = useState<Record<number, number>>({});
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const sourcesQuery = trpc.movieSources.list.useQuery({ slug }, { retry: false });
  const sources = (sourcesQuery.data || []) as Source[];

  const addSource = trpc.movieSources.addSource.useMutation({
    onSuccess: async () => {
      setSourceName("");
      setAddingSource(false);
      await sourcesQuery.refetch();
      setMessage("Đã thêm nguồn.");
    },
    onError: item => setError(item.message),
  });
  const renameSource = trpc.movieSources.renameSource.useMutation({
    onSuccess: async () => {
      setEditingSource(null);
      await sourcesQuery.refetch();
      setMessage("Đã đổi tên nguồn.");
    },
    onError: item => setError(item.message),
  });
  const removeSource = trpc.movieSources.removeSource.useMutation({
    onSuccess: async () => {
      await sourcesQuery.refetch();
      setMessage("Đã xoá nguồn và tập.");
    },
    onError: item => setError(item.message),
  });
  const addEpisode = trpc.movieSources.addEpisode.useMutation({
    onSuccess: async (_episode, variables) => {
      setAddEpisodeRevision(current => ({ ...current, [variables.sourceId]: (current[variables.sourceId] || 0) + 1 }));
      await sourcesQuery.refetch();
      setMessage("Đã thêm tập.");
    },
    onError: item => setError(item.message),
  });
  const addEpisodes = trpc.movieSources.addEpisodes.useMutation({ onError: item => setError(item.message) });
  const updateEpisode = trpc.movieSources.updateEpisode.useMutation({
    onSuccess: async () => {
      setEditingEpisode(null);
      await sourcesQuery.refetch();
      setMessage("Đã cập nhật tập.");
    },
    onError: item => setError(item.message),
  });
  const removeEpisode = trpc.movieSources.removeEpisode.useMutation({
    onSuccess: async () => {
      await sourcesQuery.refetch();
      setMessage("Đã xoá tập.");
    },
    onError: item => setError(item.message),
  });

  const pending =
    addSource.isPending ||
    renameSource.isPending ||
    removeSource.isPending ||
    addEpisode.isPending ||
    addEpisodes.isPending ||
    updateEpisode.isPending ||
    removeEpisode.isPending;

  function submitSource(event: React.FormEvent) {
    event.preventDefault();
    const name = sourceName.trim();
    if (name) addSource.mutate({ slug, name });
  }

  return (
    <section className="admin-source-panel custom-sources-panel">
      <div className="admin-source-panel-heading">
        <div>
          <strong>Nguồn &amp; tập</strong>
          <span>Thêm nguồn thủ công, tập phim và nhiều chất lượng phát cho từng tập.</span>
        </div>
        <Database size={19} />
      </div>

      {(error || sourcesQuery.error) && (
        <p className="admin-tv-error">{error || `Không thể tải nguồn: ${sourcesQuery.error?.message}`}</p>
      )}
      {message && !error && <p className="admin-tv-success">{message}</p>}

      <div className="custom-source-toolbar">
        <button
          type="button"
          className="button button-primary"
          onClick={() => {
            setAddingSource(current => !current);
            setError(null);
          }}
          disabled={pending}
        >
          <Plus size={14} /> Thêm nguồn
        </button>
        <button
          type="button"
          className="custom-icon-button"
          onClick={() => {
            void sourcesQuery.refetch();
          }}
          disabled={sourcesQuery.isFetching}
          title="Làm mới"
        >
          <RefreshCw size={15} />
        </button>
      </div>

      {addingSource && (
        <form className="admin-add-source-form" onSubmit={submitSource}>
          <input
            value={sourceName}
            onChange={event => setSourceName(event.target.value)}
            placeholder="Tên nguồn, ví dụ: Lồng tiếng"
            autoFocus
            required
          />
          <button className="button button-primary" disabled={addSource.isPending}>
            <Save size={14} /> Tạo nguồn
          </button>
          <button type="button" className="button button-ghost" onClick={() => setAddingSource(false)}>
            Huỷ
          </button>
        </form>
      )}

      {sourcesQuery.isLoading ? (
        <p className="admin-movies-muted">Đang tải nguồn…</p>
      ) : sources.length === 0 ? (
        <div className="admin-source-empty">
          <Database size={23} />
          <strong>Chưa có nguồn thủ công</strong>
          <span>Tạo nguồn đầu tiên để thêm tập cho phim này.</span>
        </div>
      ) : (
        <div className="custom-source-list">
          {sources.map(source => (
            <article className="admin-manual-source-card" key={source.id}>
              <div className="admin-manual-source-heading">
                <div className="admin-manual-source-name">
                  {editingSource === source.id ? (
                    <input value={sourceDraft} onChange={event => setSourceDraft(event.target.value)} autoFocus />
                  ) : (
                    <strong>{source.name}</strong>
                  )}
                  {editingSource === source.id ? (
                    <button
                      type="button"
                      className="button button-ghost"
                      onClick={() => {
                        if (sourceDraft.trim()) renameSource.mutate({ id: source.id, name: sourceDraft.trim() });
                      }}
                    >
                      Lưu tên
                    </button>
                  ) : (
                    <button
                      type="button"
                      className="admin-movies-action"
                      onClick={() => {
                        setEditingSource(source.id);
                        setSourceDraft(source.name);
                      }}
                    >
                      <Pencil size={13} /> Đổi tên
                    </button>
                  )}
                </div>
                <button
                  type="button"
                  className="button button-danger"
                  disabled={pending}
                  onClick={() => {
                    if (window.confirm(`Xoá nguồn “${source.name}” và toàn bộ tập?`)) removeSource.mutate({ id: source.id });
                  }}
                >
                  <Trash2 size={14} /> Xoá nguồn
                </button>
              </div>
              <div className="admin-manual-source-meta">{source.episodes.length} tập</div>

              <div className="admin-episode-list">
                {source.episodes.map(episode => (
                  <div className="admin-manual-episode-wrap" key={episode.id} data-episode-id={episode.id}>
                    <article className="admin-manual-episode">
                      <div className="admin-manual-episode-copy">
                        <strong>{episode.name}</strong>
                        <a href={episode.streamUrl} target="_blank" rel="noreferrer">
                          <Link2 size={12} /> {episode.streamUrl}
                        </a>
                        <span className="custom-quality-summary">
                          {episode.qualities.length
                            ? `${episode.qualities.length} chất lượng: ${episode.qualities.map(item => item.label).join(", ")}`
                            : "Dùng chất lượng mặc định của tập"}
                        </span>
                        {episode.subtitleUrl ? (
                          <a className="admin-subtitle-link" href={episode.subtitleUrl} target="_blank" rel="noreferrer">
                            <FileText size={12} /> Phụ đề
                          </a>
                        ) : (
                          <span className="admin-no-subtitle">Chưa có phụ đề</span>
                        )}
                      </div>
                      <div className="admin-episode-actions">
                        <button
                          type="button"
                          className="admin-movies-action"
                          disabled={pending}
                          onClick={() => { const next = editingEpisode === episode.id ? null : episode.id; setEditingEpisode(next); if (next) scrollEpisodeIntoView(episode.id); }}
                        >
                          <Pencil size={13} /> Sửa
                        </button>
                        <button
                          type="button"
                          className="admin-movies-action is-danger"
                          disabled={pending}
                          onClick={() => {
                            if (window.confirm(`Xoá tập “${episode.name}”?`)) removeEpisode.mutate({ id: episode.id });
                          }}
                        >
                          <Trash2 size={13} /> Xoá
                        </button>
                      </div>
                    </article>
                    {editingEpisode === episode.id && (
                      <SourceEpisodeEditor
                        initial={episode}
                        pending={updateEpisode.isPending}
                        onCancel={() => setEditingEpisode(null)}
                        onSubmit={payload => updateEpisode.mutateAsync({ id: episode.id, ...payload })}
                      />
                    )}
                  </div>
                ))}
              </div>

              {bulkSourceId === source.id ? (
                <BulkEpisodesInput
                  existingEpisodes={source.episodes.map(episode => ({ name: episode.name, streamUrl: episode.streamUrl }))}
                  pending={addEpisodes.isPending}
                  onClose={() => setBulkSourceId(null)}
                  onSubmit={async items => {
                    const result = await addEpisodes.mutateAsync({
                      sourceId: source.id,
                      episodes: items.map(item => ({ name: item.name, streamUrl: item.streamUrl, subtitleUrl: item.subtitleUrl, subtitleVtt: null })),
                    });
                    await sourcesQuery.refetch();
                    setMessage(`Đã thêm ${result.added} tập.`);
                    return { added: result.added, skipped: result.skipped.length };
                  }}
                />
              ) : (
                <>
                  <div className="custom-bulk-toggle">
                    <button type="button" className="admin-source-mode-switch" onClick={() => setBulkSourceId(source.id)} disabled={pending}>
                      Dán danh sách nhiều tập
                    </button>
                  </div>
                  <SourceEpisodeEditor
                    key={`add-${source.id}-${addEpisodeRevision[source.id] || 0}`}
                    pending={addEpisode.isPending}
                    onSubmit={async payload => {
                      await addEpisode.mutateAsync({ sourceId: source.id, ...payload });
                    }}
                  />
                </>
              )}
            </article>
          ))}
        </div>
      )}
    </section>
  );
});
/* ------------------------------------------------------------------ */
/* Trang chính: thêm / sửa phim thủ công                               */
/* ------------------------------------------------------------------ */

/**
 * Danh sách phim thủ công trong khung riêng.
 *
 * Trước đây danh sách nằm thẳng trong cột phải nên càng nhiều phim trang càng dài;
 * nay có ô tìm nhanh và khung cuộn riêng, ảnh poster tải lười. Bộ so sánh của `memo`
 * chỉ xét dữ liệu nên gõ trong form không dựng lại cả danh sách.
 */
const CustomMovieListPanel = memo(
  function CustomMovieListPanel({
    movies,
    currentId,
    removing,
    onRemove,
  }: {
    movies: CustomMovieRow[];
    currentId: number | null;
    removing: boolean;
    onRemove: (movie: CustomMovieRow) => void;
  }) {
    const [query, setQuery] = useState("");
    const deferredQuery = useDeferredValue(query);
    const visible = useMemo(() => {
      const needle = foldLang(deferredQuery);
      if (!needle) return movies;
      return movies.filter(
        movie => foldLang(movie.name).includes(needle) || foldLang(movie.slug).includes(needle),
      );
    }, [movies, deferredQuery]);

    return (
      <>
        <label className="custom-list-search">
          <Search size={14} />
          <input
            value={query}
            onChange={event => setQuery(event.target.value)}
            placeholder="Tìm phim thủ công…"
            aria-label="Tìm phim thủ công"
          />
          {query && (
            <button type="button" onClick={() => setQuery("")} aria-label="Xoá tìm kiếm">
              ×
            </button>
          )}
        </label>
        {visible.length === 0 ? (
          <p className="custom-muted">
            {movies.length === 0 ? "Chưa có phim thủ công." : "Không tìm thấy phim phù hợp."}
          </p>
        ) : (
          <div className="custom-movie-list">
            {visible.map(movie => (
              <article className={currentId === movie.id ? "is-current" : ""} key={movie.id}>
                <div className="custom-list-poster">
                  {movie.posterUrl || movie.thumbUrl ? (
                    <img src={movie.posterUrl || movie.thumbUrl || ""} alt="" loading="lazy" decoding="async" />
                  ) : (
                    <Database size={15} />
                  )}
                </div>
                <div>
                  <strong>{movie.name}</strong>
                  <span>
                    {movie.year || "—"} · {movie.movieType === "single" ? "Phim lẻ" : "Phim bộ"}
                  </span>
                </div>
                <RouterLink href={`/admin/movies/custom/${movie.id}`} aria-label={`Sửa ${movie.name}`}>
                  <Pencil size={14} />
                </RouterLink>
                <button
                  type="button"
                  onClick={() => onRemove(movie)}
                  disabled={removing}
                  aria-label={`Xoá ${movie.name}`}
                >
                  <Trash2 size={14} />
                </button>
              </article>
            ))}
          </div>
        )}
      </>
    );
  },
  (prev, next) =>
    prev.movies === next.movies && prev.currentId === next.currentId && prev.removing === next.removing,
);


export default function AdminCustomMovie({ params }: { params?: Record<string, string | undefined> }) {
  const id = params?.id;
  const { user, loading } = useAuth();
  const [authOpen, setAuthOpen] = useState(false);
  const [, navigate] = useLocation();
  const movieId = id ? Number(id) : null;
  const editing = Number.isInteger(movieId) && (movieId || 0) > 0;

  const [form, setForm] = useState<FormState>(emptyForm);
  const [status, setStatus] = useState<string | null>(null);
  const [savedMovieId, setSavedMovieId] = useState<number | null>(null);
  const [formError, setFormError] = useState<string | null>(null);
  const [actorQuery, setActorQuery] = useState("");
  const [actorResults, setActorResults] = useState<Array<{ name: string; image: string; description: string; imdbId: string; tmdbId: number | null }>>([]);
  const [actorSearching, setActorSearching] = useState(false);
  const [actorSearched, setActorSearched] = useState(false);
  const [actorNotice, setActorNotice] = useState<string | null>(null);
  const actorSearch = trpc.customMovies.searchActors.useMutation();
  const actorCredentials = trpc.customMovies.actorSearchCredentials.useMutation();
  const creditsMutation = trpc.customMovies.fetchCredits.useMutation();
  const [langOther, setLangOther] = useState(false);
  const [langOpen, setLangOpen] = useState(false);
  const langWrapRef = useRef<HTMLDivElement>(null);
  const [creditsLoading, setCreditsLoading] = useState(false);
  const [creditsFromBrowser, setCreditsFromBrowser] = useState(false);
  const [actorFromBrowser, setActorFromBrowser] = useState(false);
  const actorServerDisabled = useRef(false);
  const actorBrowserCache = useRef(new Map<string, BrowserActor[]>());
  const actorTimer = useRef<number | null>(null);

  useEffect(() => {
    actorServerDisabled.current = readActorServerFlag();
  }, []);

  // Mở phim đã lưu mà ngôn ngữ có phần ghi tự do thì hiện luôn ô nhập tương ứng.
  useEffect(() => {
    if (parseLang(form.lang).custom) setLangOther(true);
  }, [form.lang]);

  // Bấm ra ngoài hoặc Esc thì đóng danh sách Ngôn ngữ.
  useEffect(() => {
    if (!langOpen) return;
    function onPointerDown(event: MouseEvent | TouchEvent) {
      if (!langWrapRef.current?.contains(event.target as Node)) setLangOpen(false);
    }
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") setLangOpen(false);
    }
    document.addEventListener("mousedown", onPointerDown);
    document.addEventListener("touchstart", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("mousedown", onPointerDown);
      document.removeEventListener("touchstart", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [langOpen]);

  const parsedLang = parseLang(form.lang);
  const langLabel = form.lang.trim() || "Chưa chọn";
  const showLangCustom = langOther || Boolean(parsedLang.custom);

  /** Bật/tắt một kiểu âm thanh; chọn được nhiều mục cùng lúc nên danh sách không tự đóng. */
  function toggleLangPreset(value: string) {
    const picked = parsedLang.presets.includes(value)
      ? parsedLang.presets.filter(item => item !== value)
      : [...parsedLang.presets, value];
    setField("lang", composeLang(picked, parsedLang.custom));
  }

  /** Ghi tự do (ví dụ "Vietsub AI"): vẫn giữ các lựa chọn nhanh đang tick. */
  function setLangCustom(value: string) {
    setField("lang", composeLang(parsedLang.presets, value));
  }

  function clearLang() {
    setLangOther(false);
    setField("lang", "");
  }

  function markActorServerDisabled() {
    actorServerDisabled.current = true;
    try {
      window.localStorage.setItem(ACTOR_SERVER_FLAG, String(Date.now()));
    } catch {
      /* bỏ qua nếu trình duyệt chặn localStorage */
    }
  }

  const [initializedId, setInitializedId] = useState<number | null>(null);

  const listQuery = trpc.customMovies.list.useQuery(undefined, {
    enabled: user?.role === "admin",
    retry: false,
  });
  const movieQuery = trpc.customMovies.get.useQuery(
    { id: movieId as number },
    { enabled: user?.role === "admin" && editing, retry: false },
  );
  const metaQuery = trpc.cinema.meta.useQuery();

  const createMovie = trpc.customMovies.create.useMutation();
  const updateMovie = trpc.customMovies.update.useMutation();
  const removeMovie = trpc.customMovies.remove.useMutation();
  /** Xoá phim thủ công rồi làm mới danh sách; nếu đang sửa chính phim đó thì về form trắng. */
  const handleRemoveMovie = useCallback(
    (movie: CustomMovieRow) => {
      if (!window.confirm(`Xoá phim “${movie.name}”?`)) return;
      removeMovie.mutate(
        { id: movie.id },
        {
          onSuccess: async () => {
            await listQuery.refetch();
            if (editing && movie.id === movieId) navigate("/admin/movies/custom/new");
          },
        },
      );
    },
    [editing, movieId, navigate, removeMovie, listQuery],
  );


  // Thông báo tự ẩn sau ít giây nên mở lại phim để sửa sẽ không thấy thông báo cũ.
  useEffect(() => {
    if (!status) return;
    const timer = window.setTimeout(() => {
      setStatus(null);
      setSavedMovieId(null);
    }, 6000);
    return () => window.clearTimeout(timer);
  }, [status]);

  useEffect(() => {
    if (movieQuery.data && initializedId !== movieQuery.data.id) {
      setForm(formFromMovie(movieQuery.data as unknown as CustomMovieRow));
      setInitializedId(movieQuery.data.id);
    }
  }, [movieQuery.data, initializedId]);

  useEffect(() => {
    if (!editing) {
      // Tạo phim mới: luôn là form trắng, kể cả sau khi F5 hay bấm “Phim mới”,
      // và dọn luôn bản nháp mà bản cũ còn để lại trong trình duyệt.
      clearCustomMovieDraft();
      setForm(emptyForm());
      setInitializedId(null);
    }
  }, [editing]);

  const categories = (metaQuery.data?.categories || []) as Tag[];
  const countries = (metaQuery.data?.countries || []) as Tag[];
  const customMovies = useMemo(() => (listQuery.data || []) as CustomMovieRow[], [listQuery.data]);
  const isAdmin = user?.role === "admin";
  const saving = createMovie.isPending || updateMovie.isPending;

  function setField<K extends keyof FormState>(key: K, value: FormState[K]) {
    setForm(current => ({ ...current, [key]: value }));
    setStatus(null);
    setFormError(null);
  }

  /** Gõ tên diễn viên: tự tìm sau 0,45 giây và hiện gợi ý kèm ảnh. */
  function handleActorQuery(value: string) {
    setActorQuery(value);
    if (actorTimer.current) window.clearTimeout(actorTimer.current);
    const query = value.trim();
    if (query.length < 2) {
      setActorResults([]);
      setActorSearched(false);
      setActorNotice(null);
      setActorSearching(false);
      return;
    }
    setActorSearching(true);
    actorTimer.current = window.setTimeout(() => {
      void (async () => {
        const cacheKey = query.toLocaleLowerCase("vi-VN");
        const cached = actorBrowserCache.current.get(cacheKey);

        /** Tìm từ trình duyệt (đã có cache thì dùng ngay). */
        async function searchFromBrowser(): Promise<BrowserActor[]> {
          if (cached) return cached;
          const credentials = await actorCredentials.mutateAsync();
          const direct = await browserSearchActors(query, credentials.tmdbKey);
          if (direct.items.length > 0) actorBrowserCache.current.set(cacheKey, direct.items);
          return direct.items;
        }

        // Máy chủ hosting đã biết là không gọi được nguồn → tìm thẳng từ trình duyệt cho nhanh.
        if (actorServerDisabled.current) {
          try {
            const items = await searchFromBrowser();
            setActorResults(items);
            setActorNotice(null);
            setActorFromBrowser(items.length > 0);
            if (items.length === 0) setActorNotice("Không tìm thấy diễn viên phù hợp.");
          } catch (error) {
            setActorResults([]);
            setActorFromBrowser(false);
            setActorNotice(`Không tìm được diễn viên: ${error instanceof Error ? error.message : "lỗi không xác định"}.`);
          } finally {
            setActorSearched(true);
            setActorSearching(false);
          }
          return;
        }

        try {
          const result = await actorSearch.mutateAsync({ query, limit: 8 });
          setActorResults(result.items);
          setActorNotice(result.notice);
          setActorFromBrowser(false);
        } catch (error) {
          // Máy chủ hosting bị chặn TMDB/Wikidata → ghi nhớ và tìm trực tiếp từ trình duyệt.
          markActorServerDisabled();
          try {
            const items = await searchFromBrowser();
            if (items.length === 0) throw error;
            setActorResults(items);
            setActorNotice(null);
            setActorFromBrowser(true);
          } catch {
            setActorResults([]);
            setActorFromBrowser(false);
            setActorNotice(
              `Không tìm được diễn viên: ${error instanceof Error && error.message ? error.message : "lỗi không xác định"}.`,
            );
          }
        } finally {
          setActorSearched(true);
          setActorSearching(false);
        }
      })();
    }, 450);
  }

  /** Chọn một gợi ý: thêm diễn viên kèm ảnh, bỏ qua nếu đã có trong danh sách. */
  function addActorSuggestion(item: { name: string; image: string }) {
    const exists = form.actors.some(actor => actor.name.trim().toLocaleLowerCase("vi-VN") === item.name.toLocaleLowerCase("vi-VN"));
    if (exists) {
      setStatus(`${item.name} đã có trong danh sách diễn viên.`);
      return;
    }
    setField("actors", [...form.actors, { name: item.name, role: "", image: item.image }]);
    setStatus(`Đã thêm diễn viên ${item.name}.`);
    setActorQuery("");
    setActorResults([]);
    setActorSearched(false);
    setActorNotice(null);
    setActorFromBrowser(false);
  }

  /**
   * Lấy diễn viên và đạo diễn theo TMDB ID / IMDB ID rồi ghép vào danh sách.
   *
   * Ưu tiên gọi qua máy chủ; nếu hosting không ra được Internet thì lấy thẳng từ
   * trình duyệt (TMDB mở CORS) để nút vẫn dùng được.
   */
  async function handleFetchCredits() {
    const tmdbId = form.tmdbId.trim();
    const imdbId = form.imdbId.trim();
    if (!tmdbId && !imdbId) {
      setStatus("Nhập TMDB ID hoặc IMDB ID ở mục Thông tin phim trước khi lấy diễn viên và đạo diễn.");
      return;
    }

    setCreditsLoading(true);
    setStatus("Đang lấy diễn viên và đạo diễn từ TMDB…");
    try {
      // Luôn thử máy chủ trước: chỉ khi máy chủ lỗi mới nhờ trình duyệt.
      let serverError: unknown = null;
      try {
        const result = await creditsMutation.mutateAsync({
          tmdbId: tmdbId || null,
          imdbId: imdbId || null,
          limit: 30,
          movieType: form.movieType,
          title: form.name.trim() || null,
        });
        applyCredits(result, false);
        return;
      } catch (error) {
        serverError = error;
      }

      let browserError: unknown = null;
      try {
        const credentials = await actorCredentials.mutateAsync();
        const key = (credentials?.tmdbKey ?? "").trim();
        if (!key) throw new Error("Máy chủ chưa có khoá TMDB nên không lấy được từ trình duyệt");
        const result = await browserFetchMovieCredits(tmdbId, imdbId, key, form.movieType, form.name);
        applyCredits(result, true);
        return;
      } catch (error) {
        browserError = error;
      }

      const first = message(errorText(serverError));
      const second = message(errorText(browserError));
      setStatus(`Không lấy được diễn viên và đạo diễn. Máy chủ: ${first} · Trình duyệt: ${second}`);
    } catch (error) {
      setStatus(`Không lấy được diễn viên và đạo diễn: ${errorText(error)}.`);
    } finally {
      setCreditsLoading(false);
    }
  }

  /** Lấy câu thông báo ngắn gọn từ lỗi (tRPC trả về object nên phải đọc .message). */
function errorText(error: unknown): string {
  if (!error) return "không rõ lỗi";
  if (error instanceof Error) return error.message;
  if (typeof error === "object") {
    const shape = error as { message?: unknown; data?: { message?: unknown } };
    const direct = typeof shape.message === "string" ? shape.message : "";
    const nested = typeof shape.data?.message === "string" ? shape.data.message : "";
    const text = direct || nested;
    if (text) return text;
  }
  return String(error);
}

/** Rút gọn thông báo lỗi cho vừa một dòng trạng thái. */
function message(text: string): string {
  const trimmed = text.replace(/^\s+|\s+$/g, "");
  return trimmed.length > 110 ? `${trimmed.slice(0, 107)}…` : trimmed;
}

/** Ghép kết quả TMDB vào form, bỏ qua người đã có sẵn trong danh sách. */
  function applyCredits(
    result: { title: string; directors: string[]; actors: Array<{ name: string; image: string }> },
    fromBrowser: boolean,
  ) {
    const seen = new Set(form.actors.map(actor => normalizeActorName(actor.name)).filter(Boolean));
    const nextActors = [...form.actors];
    let addedActors = 0;
    for (const actor of result.actors) {
      const raw = actor.name.trim();
      if (!raw) continue;
      // Tên không rút gọn được (chữ tượng hình…) vẫn dùng chính tên gốc làm khoá.
      const key = normalizeActorName(raw) || raw.toLocaleLowerCase("vi-VN");
      if (seen.has(key)) continue;
      seen.add(key);
      nextActors.push({ name: actor.name, role: "", image: actor.image });
      addedActors += 1;
      if (nextActors.length >= 60) break;
    }

    const nextDirectors = [...form.directors];
    let addedDirectors = 0;
    for (const name of result.directors) {
      const trimmed = name.trim();
      if (!trimmed) continue;
      if (nextDirectors.some(item => normalizeActorName(item) === normalizeActorName(trimmed))) continue;
      nextDirectors.push(trimmed);
      addedDirectors += 1;
    }

    setField("actors", nextActors);
    setField("directors", nextDirectors);
    setCreditsFromBrowser(fromBrowser);

    const found = `TMDB trả về ${result.actors.length} diễn viên và ${result.directors.length} đạo diễn`;
    const parts: string[] = [];
    if (addedActors) parts.push(`${addedActors} diễn viên`);
    if (addedDirectors) parts.push(`${addedDirectors} đạo diễn`);
    if (parts.length === 0) {
      if (result.actors.length === 0 && result.directors.length === 0) {
        setStatus(`TMDB không trả về diễn viên hay đạo diễn nào cho mã đã nhập. Kiểm tra lại TMDB ID / IMDB ID.`);
        return;
      }
      setStatus(`${found}, nhưng tất cả đã có trong danh sách nên không thêm gì.`);
      return;
    }
    setStatus(`Đã thêm ${parts.join(" và ")} từ TMDB${result.title ? ` cho phim “${result.title}”` : ""} (${found.toLowerCase()}).`);
  }

  function addChip(kind: "alternativeNames" | "directors", value: string) {
    const trimmed = value.trim();
    if (!trimmed) return;
    const current = form[kind] as string[];
    if (current.some(item => item.toLocaleLowerCase("vi-VN") === trimmed.toLocaleLowerCase("vi-VN"))) return;
    setField(kind, [...current, trimmed]);
  }

  function validateUrl(value: string, label: string) {
    const trimmed = value.trim();
    if (!trimmed) return true;
    // Ảnh đã tải về máy chủ (/uploads/…) hoặc đường dẫn nội bộ của web là hợp lệ.
    if (/^\/(uploads|api)\//i.test(trimmed)) return true;
    try {
      new URL(trimmed);
      return true;
    } catch {
      setFormError(`${label} phải là URL hợp lệ.`);
      return false;
    }
  }

  async function save(event: React.FormEvent) {
    event.preventDefault();
    setFormError(null);
    setStatus(null);
    if (!form.name.trim()) return setFormError("Vui lòng nhập tên phim.");
    if (!validateUrl(form.posterUrl, "Poster") || !validateUrl(form.thumbUrl, "Thumbnail")) return;
    if (form.actors.some(actor => !actor.name.trim())) return setFormError("Mỗi diễn viên cần có tên.");

    const payload = {
      name: form.name.trim(),
      originName: form.originName.trim() || null,
      alternativeNames: form.alternativeNames,
      episodeCurrent: form.episodeCurrent.trim() || null,
      episodeTotal: form.episodeTotal.trim() ? Number(form.episodeTotal) : null,
      createdDate: form.createdDate || null,
      // Không gửi ngày cập nhật: máy chủ tự dùng mốc cập nhật thật của bản ghi,
      // nhờ vậy sửa phim xong là ngày cập nhật đổi ngay.
      updatedDate: null,
      tmdbId: form.tmdbId.trim() || null,
      imdbId: form.imdbId.trim() || null,
      categories: form.categories,
      countries: form.countries,
      rating: form.rating.trim() || null,
      viewsMode: form.viewsMode,
      viewsBase: form.viewsMode === "mixed" ? Math.max(0, Number(form.viewsBase) || 0) : 0,
      posterUrl: form.posterUrl.trim() || null,
      thumbUrl: form.thumbUrl.trim() || null,
      description: form.description || null,
      quality: form.quality.trim() || null,
      year: form.year.trim() ? Number(form.year) : null,
      lang: form.lang.trim() || null,
      time: form.time.trim() || null,
      status: form.status.trim() || null,
      movieType: form.movieType,
      actors: form.actors.map(actor => ({
        name: actor.name.trim(),
        role: actor.role?.trim() || null,
        image: actor.image.trim() || null,
      })),
      directors: form.directors,
      isPublished: form.isPublished,
    };

    try {
      const saved =
        editing && movieId
          ? await updateMovie.mutateAsync({ id: movieId, ...payload })
          : await createMovie.mutateAsync(payload);
      // Xong là dọn sạch form: không giữ lại thông tin phim vừa lưu.
      clearCustomMovieDraft();
      await listQuery.refetch();
      setSavedMovieId(saved.id);
      setInitializedId(null);
      setForm(emptyForm());
      setStatus(
        editing
          ? "Đã lưu thay đổi và làm mới form. Vào danh sách phim để sửa tiếp nếu cần."
          : "Đã tạo phim và làm mới form. Thêm nguồn, tập phim cho phim vừa tạo khi cần.",
      );
      navigate("/admin/movies/custom/new");
    } catch (saveError) {
      setFormError(saveError instanceof Error ? saveError.message : "Không thể lưu phim.");
    }
  }

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
            <p>Đăng nhập tài khoản quản trị viên để thêm phim thủ công.</p>
            <button className="button button-primary" onClick={() => setAuthOpen(true)}>
              Đăng nhập
            </button>
          </div>
          <AuthDialog open={authOpen} onClose={() => setAuthOpen(false)} />
        </main>
      </PageShell>
    );
  }

  if (!isAdmin) {
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

  if (editing && movieQuery.isLoading) {
    return (
      <PageShell>
        <main className="content-wrap inner-page">
          <p>Đang tải thông tin phim…</p>
        </main>
      </PageShell>
    );
  }

  if (editing && movieQuery.error) {
    return (
      <PageShell>
        <main className="content-wrap inner-page">
          <p className="admin-tv-error">Không thể tải phim: {movieQuery.error.message}</p>
          <RouterLink href="/admin/movies/custom/new" className="button button-primary">
            Thêm phim mới
          </RouterLink>
        </main>
      </PageShell>
    );
  }

  return (
    <PageShell>
      <main className="content-wrap inner-page admin-custom-movie-page">
        <div className="page-topline">
          <RouterLink href="/admin/movies" className="back-link">
            ← Quản lý phim
          </RouterLink>
          <span className="result-note">
            CINEMORA ADMIN · {editing ? `Đang sửa #${movieId}` : "Phim thủ công"}
          </span>
        </div>

        <SectionHeading
          eyebrow="CINEMORA ADMIN"
          title={editing ? "Chỉnh sửa phim thủ công" : "Thêm phim thủ công"}
          action={
            <RouterLink className="button button-ghost" href="/admin/movies/custom/new">
              <Plus size={14} /> Phim mới
            </RouterLink>
          }
        />

        {(formError || movieQuery.error || metaQuery.error) && (
          <p className="admin-tv-error">
            {formError || `Không thể tải dữ liệu: ${movieQuery.error?.message || metaQuery.error?.message}`}
          </p>
        )}
        {status && (
          <div className="admin-toast" role="status">
            <Check size={15} />
            <span className="admin-toast-text">{status}</span>
            {savedMovieId && (
              <RouterLink href={`/admin/movies/custom/${savedMovieId}`} className="admin-toast-link">
                Thêm nguồn &amp; tập
              </RouterLink>
            )}
            <button
              type="button"
              className="admin-toast-close"
              onClick={() => {
                setStatus(null);
                setSavedMovieId(null);
              }}
              aria-label="Đóng thông báo"
            >
              <X size={14} />
            </button>
          </div>
        )}

        <div className="custom-movie-layout">
          <form className="custom-movie-form" onSubmit={save}>
            {/* 01 — Thông tin phim */}
            <section className="admin-source-panel custom-form-section">
              <div className="custom-section-heading">
                <div>
                  <span className="admin-source-eyebrow">01</span>
                  <strong>Thông tin phim</strong>
                  <small>Tên, metadata và các bộ lọc hiển thị trên trang phim.</small>
                </div>
              </div>

              <div className="custom-form-grid two">
                <label>
                  Tên phim
                  <input
                    value={form.name}
                    onChange={event => setField("name", event.target.value)}
                    required
                    placeholder="Ví dụ: Mùa hè rực rỡ"
                  />
                </label>
                <label>
                  Tên tiếng Anh
                  <input
                    value={form.originName}
                    onChange={event => setField("originName", event.target.value)}
                    placeholder="English title"
                  />
                </label>
              </div>

              <ChipField
                label="Tên khác"
                hint="Gõ xong ấn Enter để thêm tiếp"
                placeholder="Gõ tên khác rồi ấn Enter…"
                values={form.alternativeNames}
                onAdd={value => addChip("alternativeNames", value)}
                onRemove={value => setField("alternativeNames", form.alternativeNames.filter(item => item !== value))}
              />

              <div className="custom-form-grid three">
                <SelectField
                  label="Loại phim"
                  value={form.movieType}
                  options={[
                    { value: "series", label: "Phim bộ", hint: "Nhiều tập" },
                    { value: "single", label: "Phim lẻ", hint: "Một tập" },
                  ]}
                  onChange={next => setField("movieType", next)}
                />
                <label>
                  Tập hiện tại
                  <input
                    value={form.episodeCurrent}
                    onChange={event => setField("episodeCurrent", event.target.value)}
                    placeholder={form.movieType === "single" ? "Full" : "Tập 5"}
                  />
                </label>
                <label>
                  Tổng số tập
                  <input
                    type="number"
                    min="0"
                    value={form.episodeTotal}
                    onChange={event => setField("episodeTotal", event.target.value)}
                    placeholder="Tuỳ chọn"
                  />
                </label>
              </div>

              <div className="custom-form-grid two">
                <label>
                  Ngày tạo
                  <DateField value={form.createdDate} onChange={next => setField("createdDate", next)} />
                </label>
                <label>
                  Ngày cập nhật
                  <input className="custom-date-readonly" value={isoToDisplay(form.updatedDate)} readOnly />
                  <small className="custom-date-hint">Tự đổi sang ngày hôm nay khi bạn lưu thay đổi</small>
                </label>
              </div>

              <div className="custom-form-grid four">
                <label>
                  TMDB ID
                  <input value={form.tmdbId} onChange={event => setField("tmdbId", event.target.value)} />
                </label>
                <label>
                  IMDB ID
                  <input value={form.imdbId} onChange={event => setField("imdbId", event.target.value)} />
                </label>
                <label>
                  Đánh giá
                  <span className="input-suffix">
                    <input
                      value={form.rating}
                      onChange={event => setField("rating", event.target.value)}
                      placeholder="8.0"
                    />
                    <i>/10</i>
                  </span>
                </label>
                <label>
                  Năm
                  <input
                    type="number"
                    min="1900"
                    max="2100"
                    value={form.year}
                    onChange={event => setField("year", event.target.value)}
                    placeholder="2025"
                  />
                </label>
              </div>

              <div className="custom-form-grid two custom-tag-grid-two">
                <TagPicker
                  label="Thể loại"
                  options={categories}
                  selected={form.categories}
                  onChange={next => setField("categories", next)}
                />
                <TagPicker
                  label="Quốc gia"
                  options={countries}
                  selected={form.countries}
                  onChange={next => setField("countries", next)}
                />
              </div>

              <div className="custom-form-grid three">
                <label>
                  Chất lượng
                  <input value={form.quality} onChange={event => setField("quality", event.target.value)} placeholder="FHD" />
                </label>
                <label>
                  Ngôn ngữ
                  <div className="custom-lang-select" ref={langWrapRef}>
                    <button
                      type="button"
                      className={langOpen ? "custom-lang-trigger is-open" : "custom-lang-trigger"}
                      onClick={() => setLangOpen(current => !current)}
                      aria-expanded={langOpen}
                      aria-haspopup="listbox"
                    >
                      <span>{langLabel}</span>
                      <ChevronDown size={15} />
                    </button>
                    {langOpen && (
                      <div className="custom-lang-pop" role="listbox" aria-multiselectable="true">
                        {LANG_PRESETS.map(item => {
                          const picked = parsedLang.presets.includes(item.value);
                          return (
                            <button
                              key={item.value}
                              type="button"
                              className={picked ? "custom-lang-option is-selected" : "custom-lang-option"}
                              onClick={() => toggleLangPreset(item.value)}
                              role="option"
                              aria-selected={picked}
                            >
                              <span className="custom-lang-tick" aria-hidden="true">{picked ? "✓" : ""}</span>
                              {item.label}
                            </button>
                          );
                        })}
                        <button
                          type="button"
                          className={showLangCustom ? "custom-lang-option is-selected" : "custom-lang-option"}
                          onClick={() => setLangOther(current => !current)}
                          role="option"
                          aria-selected={showLangCustom}
                        >
                          <span className="custom-lang-tick" aria-hidden="true">{showLangCustom ? "✓" : ""}</span>
                          Khác…
                        </button>
                        <button type="button" className="custom-lang-option is-muted" onClick={clearLang}>
                          Bỏ chọn tất cả
                        </button>
                      </div>
                    )}
                  </div>
                  <span className="custom-lang-hint">Chọn được nhiều mục cùng lúc — ví dụ Thuyết Minh + Lồng Tiếng.</span>
                </label>
                <label>
                  Thời lượng
                  <input value={form.time} onChange={event => setField("time", event.target.value)} placeholder="120 phút" />
                </label>
              </div>

              {showLangCustom && (
                <label className="custom-lang-custom">
                  Ngôn ngữ khác
                  <input
                    value={parsedLang.custom}
                    onChange={event => setLangCustom(event.target.value)}
                    placeholder="Ví dụ: Vietsub AI, Thuyết Minh AI…"
                  />
                  <span className="custom-lang-hint">
                    Ghi rõ kiểu ngôn ngữ để phim vẫn nằm đúng danh sách lọc — “Vietsub AI” được tính là Vietsub.
                  </span>
                </label>
              )}

              <label>
                Trạng thái
                <input
                  value={form.status}
                  onChange={event => setField("status", event.target.value)}
                  placeholder="Đang chiếu / Hoàn tất"
                />
              </label>

              <div className="custom-field-block">
                <span className="custom-label">Lượt xem</span>
                <div className="custom-segmented">
                  <button
                    type="button"
                    className={form.viewsMode === "real" ? "is-active" : ""}
                    onClick={() => setField("viewsMode", "real")}
                  >
                    Chỉ lượt xem thật
                  </button>
                  <button
                    type="button"
                    className={form.viewsMode === "mixed" ? "is-active" : ""}
                    onClick={() => setField("viewsMode", "mixed")}
                  >
                    Thật + ảo
                  </button>
                </div>
                {form.viewsMode === "mixed" && (
                  <label className="custom-inline-field">
                    Số ảo cộng thêm
                    <input
                      type="number"
                      min="0"
                      value={form.viewsBase}
                      onChange={event => setField("viewsBase", event.target.value)}
                    />
                  </label>
                )}
                <small className="custom-hint">Lượt xem thật tự đếm khi có người mở phim.</small>
              </div>

              <label className="custom-checkbox">
                <input
                  type="checkbox"
                  checked={form.isPublished}
                  onChange={event => setField("isPublished", event.target.checked)}
                />
                Hiển thị phim trên website và app
              </label>
            </section>

            {/* 02 — Hình ảnh */}
            <section className="admin-source-panel custom-form-section">
              <div className="custom-section-heading">
                <div>
                  <span className="admin-source-eyebrow">02</span>
                  <strong>Hình ảnh</strong>
                  <small>Ảnh được lưu lên máy chủ sau khi cắt; link ngoài được giữ nguyên.</small>
                </div>
              </div>
              <div className="custom-image-grid">
                <ImagePicker
                  label="Poster phim"
                  value={form.posterUrl}
                  onChange={value => setField("posterUrl", value)}
                  aspect="poster"
                  hint="Tỉ lệ khuyến nghị 2:3"
                />
                <ImagePicker
                  label="Thumbnail"
                  value={form.thumbUrl}
                  onChange={value => setField("thumbUrl", value)}
                  aspect="thumbnail"
                  hint="Ảnh ngang 16:9 trong trang chi tiết"
                />
              </div>
            </section>

            {/* 03 — Nội dung */}
            <section className="admin-source-panel custom-form-section">
              <div className="custom-section-heading">
                <div>
                  <span className="admin-source-eyebrow">03</span>
                  <strong>Nội dung</strong>
                  <small>Tóm tắt hiển thị ở trang chi tiết phim.</small>
                </div>
              </div>
              <label>
                Nội dung phim
                <textarea
                  rows={8}
                  value={form.description}
                  onChange={event => setField("description", event.target.value)}
                  placeholder="Tóm tắt nội dung phim…"
                />
              </label>
            </section>

            {/* 04 — Diễn viên & đạo diễn */}
            <section className="admin-source-panel custom-form-section">
              <div className="custom-section-heading">
                <div>
                  <span className="admin-source-eyebrow">04</span>
                  <strong>Diễn viên &amp; đạo diễn</strong>
                  <small>Chỉ cần tên và ảnh (nếu có) cho mỗi diễn viên.</small>
                </div>
                <div className="custom-section-actions">
                  <button
                    type="button"
                    className="button button-ghost"
                    onClick={() => void handleFetchCredits()}
                    disabled={creditsLoading}
                    title="Điền TMDB ID hoặc IMDB ID ở mục Thông tin phim rồi bấm để lấy diễn viên và đạo diễn"
                  >
                    {creditsLoading ? <LoaderCircle size={14} className="spin" /> : <Sparkles size={14} />} Lấy từ TMDB/IMDB
                  </button>
                  <button
                    type="button"
                    className="button button-ghost"
                    onClick={() => setField("actors", [...form.actors, { name: "", role: "", image: "" }])}
                  >
                    <Plus size={14} /> Thêm diễn viên
                  </button>
                </div>
              </div>

              <ChipField
                label="Đạo diễn"
                hint="Gõ xong ấn Enter để thêm tiếp"
                placeholder="Gõ tên đạo diễn rồi ấn Enter…"
                values={form.directors}
                onAdd={value => addChip("directors", value)}
                onRemove={value => setField("directors", form.directors.filter(item => item !== value))}
              />

              <div className="actor-search">
                <label className="actor-search-field">
                  <span>Tìm diễn viên từ TMDB / Wikidata</span>
                  <div className="actor-search-input">
                    <Search size={14} />
                    <input
                      value={actorQuery}
                      onChange={event => handleActorQuery(event.target.value)}
                      placeholder="Nhập tên diễn viên, ví dụ: Trần Bảo Sơn…"
                    />
                    {actorSearching && <LoaderCircle size={14} className="spin" />}
                  </div>
                </label>
                {creditsFromBrowser && (
                  <p className="custom-muted actor-search-notice">
                    Danh sách diễn viên được lấy trực tiếp từ trình duyệt của bạn vì máy chủ hosting không gọi được TMDB.
                  </p>
                )}
                {actorNotice && <p className="custom-muted actor-search-notice">{actorNotice}</p>}
                {actorFromBrowser && (
                  <p className="custom-muted actor-search-notice">
                    Máy chủ hosting không gọi được TMDB/Wikidata nên kết quả được lấy trực tiếp từ trình duyệt của bạn.
                  </p>
                )}
                {actorResults.length > 0 && (
                  <ul className="actor-suggestions">
                    {actorResults.map(item => (
                      <li key={`${item.name}-${item.tmdbId ?? item.imdbId ?? item.image}`}>
                        <button type="button" onClick={() => addActorSuggestion(item)}>
                          <span className="actor-suggestion-avatar">
                            {item.image ? <img src={item.image} alt="" /> : <UserRound size={16} />}
                          </span>
                          <span className="actor-suggestion-body">
                            <strong>{item.name}</strong>
                          </span>
                          <Plus size={14} />
                        </button>
                      </li>
                    ))}
                  </ul>
                )}
                {actorSearched && !actorSearching && actorResults.length === 0 && (
                  <p className="custom-muted actor-search-notice">Không tìm thấy gợi ý nào. Bạn vẫn có thể thêm thủ công bên dưới.</p>
                )}
              </div>

              <div className="custom-actor-list">
                {form.actors.map((actor, index) => (
                  <article className="custom-actor-card" key={index}>
                    <div className="custom-actor-avatar">
                      {actor.image ? <img src={actor.image} alt="" /> : <span>{index + 1}</span>}
                    </div>
                    <div className="custom-actor-body">
                      <div className="custom-actor-card-head">
                        <strong>Diễn viên {index + 1}</strong>
                        <button
                          type="button"
                          className="custom-icon-danger"
                          onClick={() => setField("actors", form.actors.filter((_, itemIndex) => itemIndex !== index))}
                        >
                          <Trash2 size={13} /> Xoá
                        </button>
                      </div>
                      <label>
                        Tên diễn viên
                        <input
                          value={actor.name}
                          onChange={event =>
                            setField(
                              "actors",
                              form.actors.map((item, itemIndex) =>
                                itemIndex === index ? { ...item, name: event.target.value } : item,
                              ),
                            )
                          }
                          placeholder="Ví dụ: Trần Bảo Sơn"
                          required
                        />
                      </label>
                      <ImagePicker
                        label="Ảnh diễn viên"
                        value={actor.image}
                        onChange={value =>
                          setField(
                            "actors",
                            form.actors.map((item, itemIndex) =>
                              itemIndex === index ? { ...item, image: value } : item,
                            ),
                          )
                        }
                        aspect="actor"
                        hint="Không bắt buộc"
                      />
                    </div>
                  </article>
                ))}
                {form.actors.length === 0 && (
                  <p className="custom-muted">Chưa có diễn viên. Bấm “Thêm diễn viên” để bắt đầu.</p>
                )}
              </div>
            </section>

            <div className="custom-save-bar">
              <button type="submit" className="button button-primary" disabled={saving}>
                <Save size={15} /> {saving ? "Đang lưu…" : editing ? "Lưu thay đổi" : "Tạo phim"}
              </button>
              {editing ? (
                <span>
                  Slug: <code>{movieQuery.data?.slug}</code>
                </span>
              ) : (
                <span>Lưu phim trước, sau đó thêm nguồn và tập ở khung bên phải.</span>
              )}
            </div>
          </form>

          <aside className="custom-movie-sidebar">
            <section className="admin-source-panel custom-list-panel">
              <div className="admin-source-panel-heading">
                <div>
                  <strong>Phim thủ công</strong>
                  <span>{customMovies.length} phim đã thêm · cuộn trong khung</span>
                </div>
                <Database size={18} />
              </div>
              {listQuery.isLoading ? (
                <p className="admin-movies-muted">Đang tải…</p>
              ) : (
                <CustomMovieListPanel
                  movies={customMovies}
                  currentId={editing ? movieId : null}
                  removing={removeMovie.isPending}
                  onRemove={handleRemoveMovie}
                />
              )}
            </section>

            {editing && movieQuery.data?.slug ? (
              <SourcesManager slug={movieQuery.data.slug} />
            ) : (
              <section className="admin-source-panel custom-sources-panel">
                <div className="admin-source-panel-heading">
                  <div>
                    <strong>Nguồn &amp; tập</strong>
                    <span>Thêm nguồn, tập phim và chất lượng phát.</span>
                  </div>
                  <Database size={19} />
                </div>
                <div className="admin-source-empty">
                  <Database size={23} />
                  <strong>Lưu phim trước</strong>
                  <span>Sau khi bấm “Tạo phim”, khung này sẽ cho bạn thêm nguồn và tập phim.</span>
                </div>
              </section>
            )}
          </aside>
        </div>
      </main>
    </PageShell>
  );
}
