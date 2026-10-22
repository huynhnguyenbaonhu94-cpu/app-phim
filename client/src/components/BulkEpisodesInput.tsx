import { useMemo, useRef, useState } from "react";
import { Save, Trash2 } from "lucide-react";

/**
 * Ô dán danh sách nhiều tập, dùng chung cho trang "Quản lý nguồn & tập phim"
 * và khối "Nguồn & tập" trong trang thêm/sửa phim thủ công.
 *
 * Định dạng mỗi dòng: `tên tập | link m3u8 | link sub (nếu có)`.
 * Bỏ trống tên tập thì tự đánh số; dòng trống và dòng bắt đầu bằng `#` được bỏ qua.
 */

export type BulkEpisodeItem = {
  name: string;
  streamUrl: string;
  subtitleUrl: string | null;
};

type BulkRow = BulkEpisodeItem & {
  line: number;
  error: string | null;
};

type Props = {
  /** Tập đang có của nguồn, dùng để phát hiện trùng. */
  existingEpisodes: Array<{ name: string; streamUrl: string }>;
  /** Thêm một lượt nhiều tập; trả về số tập đã thêm và số dòng bị bỏ qua. */
  onSubmit: (items: BulkEpisodeItem[]) => Promise<{ added: number; skipped: number }>;
  /** Quay lại chế độ nhập từng tập. */
  onClose?: () => void;
  pending?: boolean;
};

const EXAMPLE = "Tập 01|https://v8.streamvsmov.com/video/…/master.m3u8|https://…/sub.vtt";

/** Đọc danh sách admin dán vào và đối chiếu trùng ngay trên trình duyệt. */
export function parseBulkEpisodes(
  text: string,
  existing: Array<{ name: string; streamUrl: string }>,
): BulkRow[] {
  const seenNames = new Set(existing.map(item => item.name.trim().toLowerCase()));
  const seenUrls = new Set(existing.map(item => item.streamUrl.trim().toLowerCase()));
  const rows: BulkRow[] = [];
  const lines = text.split(/\r?\n/);
  let autoIndex = 1;
  for (let i = 0; i < lines.length; i += 1) {
    const raw = lines[i].trim();
    if (!raw || raw.startsWith("#")) continue;
    const parts = raw.split(/\s*[|\t]\s*/);
    let name = (parts[0] || "").trim();
    let streamUrl = (parts[1] || "").trim();
    let subtitleUrl = (parts[2] || "").trim() || null;
    // Dòng chỉ có link (admin quên điền tên) vẫn nhận: tự đánh số tập.
    if (!streamUrl && /^https?:\/\//i.test(name)) {
      streamUrl = name;
      name = "";
      subtitleUrl = subtitleUrl || null;
    }
    if (!name) name = `Tập ${String(autoIndex).padStart(2, "0")}`;
    autoIndex += 1;

    let error: string | null = null;
    if (!streamUrl) error = "Thiếu link M3U8 (cột 2)";
    else if (!/^https?:\/\//i.test(streamUrl)) error = "Link M3U8 phải bắt đầu bằng http:// hoặc https://";
    else if (seenUrls.has(streamUrl.toLowerCase())) error = "Trùng link M3U8 với tập đã có";
    else if (seenNames.has(name.toLowerCase())) error = "Trùng tên tập với tập đã có";

    const row: BulkRow = { line: i + 1, name, streamUrl, subtitleUrl, error };
    if (!row.error) {
      seenNames.add(name.toLowerCase());
      seenUrls.add(streamUrl.toLowerCase());
    }
    rows.push(row);
  }
  return rows;
}

export default function BulkEpisodesInput({ existingEpisodes, onSubmit, onClose, pending = false }: Props) {
  const [text, setText] = useState("");
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [checked, setChecked] = useState(false);
  const [saving, setSaving] = useState(false);
  const rowRefs = useRef<Array<HTMLDivElement | null>>([]);

  const rows = useMemo(() => parseBulkEpisodes(text, existingEpisodes), [text, existingEpisodes]);
  const badCount = rows.filter(row => row.error).length;
  const goodCount = rows.length - badCount;

  async function submit() {
    setError(null);
    setNotice(null);
    setChecked(true);
    const firstBad = rows.findIndex(row => row.error);
    // Lướt tới đúng dòng lỗi đầu tiên để admin thấy ngay chỗ cần sửa.
    if (firstBad >= 0) {
      window.requestAnimationFrame(() => rowRefs.current[firstBad]?.scrollIntoView({ behavior: "smooth", block: "center" }));
    }
    const valid = rows.filter(row => !row.error);
    if (valid.length === 0) {
      setError(rows.length === 0 ? `Chưa có dòng nào để thêm. Mỗi dòng một tập theo mẫu: ${EXAMPLE}` : "Tất cả các dòng đều đang lỗi, xem dòng bôi đỏ bên dưới.");
      return;
    }
    setSaving(true);
    try {
      const result = await onSubmit(valid.map(row => ({ name: row.name, streamUrl: row.streamUrl, subtitleUrl: row.subtitleUrl })));
      const skipped = result.skipped + (rows.length - valid.length);
      setNotice(`Đã thêm ${result.added} tập${skipped > 0 ? `, bỏ qua ${skipped} dòng trùng hoặc lỗi` : ""}.`);
      // Giữ lại những dòng chưa thêm được để admin sửa rồi gửi tiếp.
      const remaining = rows
        .filter(row => row.error)
        .map(row => `${row.name}|${row.streamUrl}${row.subtitleUrl ? `|${row.subtitleUrl}` : ""}`)
        .join("\n");
      setText(remaining);
      setChecked(remaining.length > 0);
    } catch (submitError) {
      setError(submitError instanceof Error ? submitError.message : "Không thể thêm danh sách tập.");
    } finally {
      setSaving(false);
    }
  }

  const busy = saving || pending;

  return (
    <form
      className="admin-source-episode-form"
      onSubmit={event => {
        event.preventDefault();
        void submit();
      }}
    >
      <div className="admin-source-form-heading">
        <strong>Thêm nhiều tập cùng lúc</strong>
        {onClose && (
          <button type="button" className="admin-source-mode-switch" onClick={onClose}>
            Nhập từng tập
          </button>
        )}
      </div>
      <p className="admin-bulk-hint">
        Mỗi dòng một tập, ba cột ngăn bằng dấu <code>|</code>: <code>tập | link m3u8 | link sub (nếu có)</code>.
        Bỏ trống tên tập thì hệ thống tự đánh số, cột phụ đề có thể bỏ qua.
      </p>
      <textarea
        className="admin-bulk-input"
        value={text}
        onChange={event => {
          setText(event.target.value);
          setChecked(false);
          setNotice(null);
        }}
        rows={8}
        spellCheck={false}
        placeholder={`${EXAMPLE}\nTập 02|https://…/master.m3u8|https://…/sub.vtt`}
      />
      {rows.length > 0 && (
        <div className="admin-bulk-list-wrap">
          <div className="admin-bulk-list-head">
            <strong>{rows.length} dòng</strong>
            <span>
              {badCount > 0 ? <b className="admin-bulk-bad">{badCount} dòng lỗi hoặc trùng</b> : <b className="admin-bulk-good">Tất cả hợp lệ</b>}
            </span>
          </div>
          <div className="admin-bulk-list">
            {rows.map((row, index) => (
              <div
                key={`${row.line}-${index}`}
                ref={element => {
                  rowRefs.current[index] = element;
                }}
                className={`admin-bulk-row${row.error && checked ? " is-invalid" : ""}`}
              >
                <span className="admin-bulk-row-index">{row.line}</span>
                <div className="admin-bulk-row-main">
                  <strong>{row.name}</strong>
                  <span className="admin-bulk-row-url">{row.streamUrl}</span>
                  {row.subtitleUrl && <span className="admin-bulk-row-sub">Phụ đề: {row.subtitleUrl}</span>}
                </div>
                <span className={`admin-bulk-row-state${row.error ? " is-bad" : " is-ok"}`}>{row.error || "Hợp lệ"}</span>
              </div>
            ))}
          </div>
        </div>
      )}
      {notice && <p className="admin-tv-success">{notice}</p>}
      {error && <p className="admin-tv-error">{error}</p>}
      <div className="admin-source-form-actions">
        <button className="button button-primary" disabled={busy || rows.length === 0}>
          <Save size={14} />
          {busy ? "Đang thêm…" : goodCount > 0 ? `Thêm ${goodCount} tập` : "Thêm tập"}
        </button>
        <button
          type="button"
          className="button button-ghost"
          disabled={busy || !text}
          onClick={() => {
            setText("");
            setChecked(false);
            setNotice(null);
            setError(null);
          }}
        >
          <Trash2 size={14} /> Xoá ô nhập
        </button>
      </div>
    </form>
  );
}