import { memo, useEffect, useMemo, useRef, useState } from "react";
import { Check, Crop, Image as ImageIcon, LoaderCircle, Maximize, RotateCcw, Upload, X, ZoomIn } from "lucide-react";
import { trpc } from "@/lib/trpc";

type CropAspect = "poster" | "thumbnail" | "actor" | "free";

type Point = { x: number; y: number };
/** Hình chữ nhật trong hệ toạ độ của khung cắt. */
type Rect = { x: number; y: number; width: number; height: number };
/** Vùng ảnh đang hiển thị trong khung cắt. */
type Box = Rect & { scale: number };
type Handle = "nw" | "n" | "ne" | "e" | "se" | "s" | "sw" | "w";

export type ImagePickerProps = {
  value: string;
  onChange: (value: string) => void;
  label?: string;
  aspect?: CropAspect;
  hint?: string;
  className?: string;
};

const aspectValues: Record<Exclude<CropAspect, "free">, number> = { poster: 2 / 3, thumbnail: 16 / 9, actor: 1 };
const aspectLabels: Array<{ key: CropAspect; label: string }> = [
  { key: "poster", label: "Poster 2:3" },
  { key: "thumbnail", label: "Thumbnail 16:9" },
  { key: "actor", label: "Diễn viên 1:1" },
  { key: "free", label: "Tự do" },
];
/** Tay nắm quanh vùng chọn: 4 góc và 4 cạnh. */
const handles: Handle[] = ["nw", "n", "ne", "e", "se", "s", "sw", "w"];
/** Vùng chọn nhỏ nhất (điểm ảnh trên màn hình). */
const MIN_SIZE = 44;

/** Thời gian chờ sau khi dán link trước khi tải ảnh về máy chủ. */
const LINK_IMPORT_DELAY = 700;

function isRemoteLink(value: string) {
  return /^https?:\/\/\S+$/i.test(value.trim());
}

function readFile(file: File) {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(typeof reader.result === "string" ? reader.result : "");
    reader.onerror = () => reject(new Error("Không thể đọc tệp ảnh."));
    reader.readAsDataURL(file);
  });
}

function clamp(value: number, min: number, max: number) {
  return Math.max(min, Math.min(max, value));
}

function ratioOf(aspect: CropAspect) {
  return aspect === "free" ? null : aspectValues[aspect];
}

/** Vùng chọn mặc định: gần kín ảnh, đúng tỉ lệ đang chọn. */
function initialCrop(box: Box, ratio: number | null): Rect {
  let width = box.width * 0.88;
  let height = box.height * 0.88;
  if (ratio) {
    if (width / height > ratio) width = height * ratio;
    else height = width / ratio;
  }
  return { x: box.x + (box.width - width) / 2, y: box.y + (box.height - height) / 2, width, height };
}

/** Giữ nguyên vùng đang chọn nhưng thu lại vừa khung ảnh (khi đổi mức phóng to). */
function fitInto(rect: Rect, box: Box): Rect {
  const factor = Math.min(1, box.width / rect.width, box.height / rect.height);
  const width = rect.width * factor;
  const height = rect.height * factor;
  const centerX = rect.x + rect.width / 2;
  const centerY = rect.y + rect.height / 2;
  return {
    x: clamp(centerX - width / 2, box.x, box.x + box.width - width),
    y: clamp(centerY - height / 2, box.y, box.y + box.height - height),
    width,
    height,
  };
}

/** Đổi sang tỉ lệ khác nhưng vẫn giữ vùng đang xem ở giữa. */
function applyRatio(rect: Rect, ratio: number | null, box: Box): Rect {
  if (!ratio) return fitInto(rect, box);
  const centerX = rect.x + rect.width / 2;
  const centerY = rect.y + rect.height / 2;
  let width = rect.width;
  let height = width / ratio;
  if (height > rect.height) {
    height = rect.height;
    width = height * ratio;
  }
  const factor = Math.min(1, box.width / width, box.height / height);
  width *= factor;
  height *= factor;
  return {
    x: clamp(centerX - width / 2, box.x, box.x + box.width - width),
    y: clamp(centerY - height / 2, box.y, box.y + box.height - height),
    width,
    height,
  };
}

/** Khi tỉ lệ bị khoá: suy chiều còn lại rồi neo vào cạnh/góc đối diện. */
function lockRatio(rect: Rect, handle: Handle, ratio: number, box: Box): Rect {
  const right = rect.x + rect.width;
  const bottom = rect.y + rect.height;
  let { x, y, width, height } = rect;

  if (handle === "n" || handle === "s") {
    width = height * ratio;
    x = rect.x + (rect.width - width) / 2;
  } else if (handle === "e" || handle === "w") {
    height = width / ratio;
    y = rect.y + (rect.height - height) / 2;
  } else {
    // Kéo góc: lấy chiều biến động mạnh hơn làm chuẩn.
    const byWidth = { width, height: width / ratio };
    const byHeight = { width: height * ratio, height };
    const deltaWidth = Math.abs(byWidth.width - rect.width) + Math.abs(byWidth.height - rect.height);
    const deltaHeight = Math.abs(byHeight.width - rect.width) + Math.abs(byHeight.height - rect.height);
    const picked = deltaWidth >= deltaHeight ? byWidth : byHeight;
    width = picked.width;
    height = picked.height;
  }

  if (handle.includes("w")) x = right - width;
  if (handle.includes("n")) y = bottom - height;

  const factor = Math.min(1, box.width / width, box.height / height);
  width *= factor;
  height *= factor;
  x = clamp(x, box.x, box.x + box.width - width);
  y = clamp(y, box.y, box.y + box.height - height);
  return { x, y, width, height };
}

/** Áp thao tác kéo vào vùng chọn. */
function applyDrag(
  origin: Rect,
  handle: Handle | "move",
  dx: number,
  dy: number,
  ratio: number | null,
  box: Box,
): Rect {
  if (handle === "move") {
    return {
      ...origin,
      x: clamp(origin.x + dx, box.x, box.x + box.width - origin.width),
      y: clamp(origin.y + dy, box.y, box.y + box.height - origin.height),
    };
  }

  let left = origin.x;
  let top = origin.y;
  let right = origin.x + origin.width;
  let bottom = origin.y + origin.height;
  if (handle.includes("w")) left = clamp(origin.x + dx, box.x, right - MIN_SIZE);
  if (handle.includes("e")) right = clamp(origin.x + origin.width + dx, left + MIN_SIZE, box.x + box.width);
  if (handle.includes("n")) top = clamp(origin.y + dy, box.y, bottom - MIN_SIZE);
  if (handle.includes("s")) bottom = clamp(origin.y + origin.height + dy, top + MIN_SIZE, box.y + box.height);

  const rect: Rect = { x: left, y: top, width: right - left, height: bottom - top };
  return ratio ? lockRatio(rect, handle, ratio, box) : rect;
}

function ImagePicker({
  value,
  onChange,
  label = "Ảnh",
  aspect = "free",
  hint,
  className = "",
}: ImagePickerProps) {
  const uploadImage = trpc.customMovies.uploadImage.useMutation();
  const importImage = trpc.customMovies.importImage.useMutation();
  const fileInput = useRef<HTMLInputElement>(null);
  const stageRef = useRef<HTMLDivElement>(null);
  const importTimer = useRef<number | null>(null);

  const [source, setSource] = useState(value);
  const [sourceName, setSourceName] = useState("");
  const [linkDraft, setLinkDraft] = useState("");
  const [linkState, setLinkState] = useState<"idle" | "loading" | "importing" | "ready" | "error">("idle");
  const [note, setNote] = useState<string | null>(null);
  const [previewFailed, setPreviewFailed] = useState(false);
  const [previewNonce, setPreviewNonce] = useState(() => Date.now());

  const [cropOpen, setCropOpen] = useState(false);
  const [cropAspect, setCropAspect] = useState<CropAspect>(aspect);
  const [natural, setNatural] = useState({ width: 0, height: 0 });
  const [stage, setStage] = useState({ width: 0, height: 0 });
  const [crop, setCrop] = useState<Rect | null>(null);
  const [zoom, setZoom] = useState(1);
  const [drag, setDrag] = useState<{ handle: Handle | "move"; start: Point; origin: Rect } | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setSource(value);
    setLinkDraft(isRemoteLink(value) ? value : "");
    setPreviewFailed(false);
    setPreviewNonce(Date.now());
  }, [value]);

  useEffect(
    () => () => {
      if (importTimer.current) window.clearTimeout(importTimer.current);
    },
    [],
  );

  // Đo khung cắt để tính vùng ảnh hiển thị (đổi kích thước cửa sổ vẫn đúng).
  useEffect(() => {
    const element = stageRef.current;
    if (!cropOpen || !element) return;
    const measure = () => setStage({ width: element.clientWidth, height: element.clientHeight });
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, [cropOpen]);

  const imageBox = useMemo<Box | null>(() => {
    if (!natural.width || !natural.height || !stage.width || !stage.height) return null;
    const fit = Math.min(stage.width / natural.width, stage.height / natural.height);
    const scale = fit * zoom;
    const width = natural.width * scale;
    const height = natural.height * scale;
    return { x: (stage.width - width) / 2, y: (stage.height - height) / 2, width, height, scale };
  }, [natural, stage, zoom]);

  // Vùng chọn luôn nằm trong khung ảnh: khởi tạo khi mở, thu lại khi phóng to.
  useEffect(() => {
    if (!cropOpen || !imageBox) return;
    setCrop(current => (current ? fitInto(current, imageBox) : initialCrop(imageBox, ratioOf(cropAspect))));
    // cropAspect cố ý không nằm trong danh sách phụ thuộc: đổi tỉ lệ xử lý ở chooseAspect.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cropOpen, imageBox]);

  const sourceIsLocal = source.startsWith("data:");
  const busy = uploadImage.isPending || linkState === "loading" || linkState === "importing";
  const linkFieldValue = sourceIsLocal ? "" : linkDraft || value;

  /** Tải ảnh từ link về máy chủ để xem trước và cắt ảnh luôn hoạt động. */
  async function importLink(link: string) {
    importTimer.current = null;
    setLinkState("importing");
    try {
      const result = await importImage.mutateAsync({ url: link });
      onChange(result.url);
      setSource(result.url);
      setLinkState("ready");
      setNote("Đã tải ảnh về máy chủ — bấm “Chỉnh sửa” nếu cần cắt lại.");
    } catch (importError) {
      setLinkState("error");
      // Máy chủ không tải được ảnh (ví dụ hosting chặn tên miền nước ngoài) thì vẫn giữ link gốc.
      onChange(link);
      setSource(link);
      setNote(
        importError instanceof Error && importError.message
          ? `${importError.message}. Ảnh vẫn dùng link gốc nhưng có thể không cắt được.`
          : "Không tải được ảnh về máy chủ. Ảnh vẫn dùng link gốc nhưng có thể không cắt được.",
      );
    }
  }

  function scheduleImport(link: string, immediate = false) {
    if (importTimer.current) window.clearTimeout(importTimer.current);
    setNote(null);
    setLinkState("loading");
    importTimer.current = window.setTimeout(
      () => {
        void importLink(link);
      },
      immediate ? 0 : LINK_IMPORT_DELAY,
    );
  }

  function cancelImport() {
    if (importTimer.current) window.clearTimeout(importTimer.current);
    importTimer.current = null;
    setLinkState("idle");
    setNote(null);
  }

  /** Người dùng gõ hoặc dán link: lưu giá trị ngay, sau đó hẹn tải ảnh về máy chủ. */
  function handleLinkInput(next: string) {
    setLinkDraft(next);
    setError(null);
    setPreviewFailed(false);
    onChange(next);
    setSource(next);
    if (isRemoteLink(next)) scheduleImport(next.trim());
    else cancelImport();
  }

  function openCrop() {
    if (!source) {
      setError("Hãy chọn ảnh hoặc dán link trước.");
      return;
    }
    if (busy) {
      setError("Đang tải ảnh, chờ một chút rồi thử lại.");
      return;
    }
    setError(null);
    setCropAspect(aspect);
    setZoom(1);
    setCrop(null);
    setCropOpen(true);
  }

  function chooseAspect(next: CropAspect) {
    setCropAspect(next);
    if (imageBox) setCrop(current => (current ? applyRatio(current, ratioOf(next), imageBox) : initialCrop(imageBox, ratioOf(next))));
  }

  function selectWholeImage() {
    if (!imageBox) return;
    setCropAspect("free");
    setZoom(1);
    setCrop({ x: imageBox.x, y: imageBox.y, width: imageBox.width, height: imageBox.height });
  }

  function resetCrop() {
    if (!imageBox) return;
    setZoom(1);
    setCrop(initialCrop(imageBox, ratioOf(cropAspect)));
  }

  function stagePoint(event: React.PointerEvent): Point {
    const element = stageRef.current;
    if (!element) return { x: 0, y: 0 };
    const rect = element.getBoundingClientRect();
    return { x: event.clientX - rect.left, y: event.clientY - rect.top };
  }

  function startDrag(handle: Handle | "move", event: React.PointerEvent) {
    if (!crop) return;
    event.preventDefault();
    event.stopPropagation();
    stageRef.current?.setPointerCapture(event.pointerId);
    setDrag({ handle, start: stagePoint(event), origin: crop });
  }

  function moveDrag(event: React.PointerEvent) {
    if (!drag || !imageBox) return;
    const current = stagePoint(event);
    const next = applyDrag(
      drag.origin,
      drag.handle,
      current.x - drag.start.x,
      current.y - drag.start.y,
      ratioOf(cropAspect),
      imageBox,
    );
    setCrop(next);
  }

  function endDrag() {
    setDrag(null);
  }

  function cropImage() {
    if (!crop || !imageBox || !natural.width || !stageRef.current) return;
    const element = stageRef.current.querySelector("img");
    if (!element) return;
    const sx = clamp((crop.x - imageBox.x) / imageBox.scale, 0, natural.width);
    const sy = clamp((crop.y - imageBox.y) / imageBox.scale, 0, natural.height);
    const sw = clamp(crop.width / imageBox.scale, 1, natural.width - sx);
    const sh = clamp(crop.height / imageBox.scale, 1, natural.height - sy);
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(sw));
    canvas.height = Math.max(1, Math.round(sh));
    const context = canvas.getContext("2d");
    if (!context) {
      setError("Trình duyệt không hỗ trợ cắt ảnh.");
      return;
    }
    try {
      context.drawImage(element, sx, sy, sw, sh, 0, 0, canvas.width, canvas.height);
      const mimeType =
        /png/i.test(sourceName) || /^data:image\/png/i.test(source) || /\.png($|\?)/i.test(source)
          ? "image/png"
          : "image/jpeg";
      const base64 = canvas.toDataURL(mimeType, 0.9);
      setCropOpen(false);
      void uploadCropped(base64, mimeType);
    } catch {
      setError("Không thể cắt ảnh từ link ngoài này. Hãy tải tệp ảnh về rồi chọn lại.");
    }
  }

  async function uploadCropped(base64: string, mimeType: string) {
    setError(null);
    try {
      const result = await uploadImage.mutateAsync({
        base64,
        filename: sourceName || `movie-image.${mimeType === "image/png" ? "png" : "jpg"}`,
        mimeType,
      });
      onChange(result.url);
      setSource(result.url);
      setNote("Đã lưu ảnh đã cắt lên máy chủ.");
    } catch (uploadError) {
      setError(uploadError instanceof Error ? uploadError.message : "Không thể tải ảnh lên.");
    }
  }

  async function handleFile(file: File | undefined) {
    if (!file) return;
    if (!file.type.startsWith("image/")) {
      setError("Vui lòng chọn tệp ảnh JPEG, PNG hoặc WebP.");
      return;
    }
    if (file.size > 8 * 1024 * 1024) {
      setError("Ảnh không được vượt quá 8MB.");
      return;
    }
    try {
      setSourceName(file.name);
      const dataUrl = await readFile(file);
      setSource(dataUrl);
      setError(null);
      setNote(null);
      setCrop(null);
      setNatural({ width: 0, height: 0 });
      setZoom(1);
      setCropAspect(aspect);
      setCropOpen(true);
    } catch (fileError) {
      setError(fileError instanceof Error ? fileError.message : "Không thể đọc ảnh.");
    }
  }

  const showPreview = Boolean(source) && !previewFailed;
  const previewSource = useMemo(() => {
    if (!source || source.startsWith("data:")) return source;
    try {
      const previewUrl = new URL(source, window.location.origin);
      if (previewUrl.pathname.startsWith("/uploads/movie-images/")) {
        // Bust legacy image cache so deleted local files do not look valid in
        // the editor just because the admin browser still has an old copy.
        previewUrl.searchParams.set("_cinemora_preview", String(previewNonce));
        return previewUrl.toString();
      }
    } catch { /* Keep the original URL; the image error handler remains authoritative. */ }
    return source;
  }, [source, previewNonce]);

  return (
    <div className={`image-picker ${className}`}>
      <div className="image-picker-label">
        <strong>{label}</strong>
        <span>{hint || "Tải ảnh lên hoặc dán link"}</span>
      </div>
      <div className="image-picker-row">
        <div className={busy ? "image-picker-preview is-loading" : "image-picker-preview"}>
          {showPreview ? (
            <img
              src={previewSource}
              alt="Xem trước"
              key={previewSource}
              onError={() => setPreviewFailed(true)}
            />
          ) : (
            <ImageIcon size={23} />
          )}
          {busy && (
            <span className="image-picker-preview-status">
              <LoaderCircle size={16} className="spin" />
            </span>
          )}
        </div>
        <div className="image-picker-controls">
          <div className="image-picker-link-row">
            <input
              value={linkFieldValue}
              onChange={event => handleLinkInput(event.target.value)}
              onBlur={() => {
                if (isRemoteLink(linkDraft)) scheduleImport(linkDraft.trim(), true);
              }}
              placeholder="Dán link ảnh, ví dụ: https://…/poster.jpg"
              aria-label={`${label} URL`}
            />
            <button type="button" className="button button-ghost image-picker-upload" onClick={() => fileInput.current?.click()}>
              <Upload size={14} /> Chọn ảnh
            </button>
            <input
              ref={fileInput}
              type="file"
              accept="image/jpeg,image/png,image/webp"
              hidden
              onChange={event => {
                void handleFile(event.target.files?.[0]);
                event.currentTarget.value = "";
              }}
            />
          </div>
          <div className="image-picker-actions">
            {source && !previewFailed && (
              <button type="button" className="button button-ghost" onClick={openCrop} disabled={busy}>
                <Crop size={14} /> Chỉnh sửa
              </button>
            )}
            {busy && (
              <span className="image-picker-uploading">
                <LoaderCircle size={14} className="spin" />{" "}
                {uploadImage.isPending ? "Đang lưu ảnh…" : "Đang tải ảnh từ link…"}
              </span>
            )}
            {!busy && linkState === "ready" && (
              <span className="image-picker-ok">
                <Check size={13} /> Sẵn sàng
              </span>
            )}
          </div>
        </div>
      </div>

      {previewFailed && source && (
        <p className="image-picker-error">Không tải được ảnh từ máy chủ. Nếu đây là ảnh cũ trong /uploads, tệp có thể đã bị thiếu — hãy chọn lại ảnh gốc để tải lên.</p>
      )}
      {note && !error && <p className="image-picker-note">{note}</p>}
      {error && <p className="image-picker-error">{error}</p>}

      {cropOpen && (
        <div
          className="crop-dialog-backdrop"
          role="presentation"
          onMouseDown={event => {
            if (event.target === event.currentTarget && !uploadImage.isPending) setCropOpen(false);
          }}
        >
          <div className="crop-dialog" role="dialog" aria-modal="true" aria-label={`Chỉnh sửa ${label}`}>
            <div className="crop-dialog-heading">
              <div>
                <strong>Chỉnh sửa {label.toLocaleLowerCase("vi-VN")}</strong>
                <span>Kéo ảnh để chọn vùng, kéo tay nắm để thay đổi kích thước</span>
              </div>
              <button
                type="button"
                className="custom-icon-button"
                onClick={() => setCropOpen(false)}
                disabled={uploadImage.isPending}
                aria-label="Đóng"
              >
                <X size={16} />
              </button>
            </div>
            <div className="crop-toolbar">
              {aspectLabels.map(item => (
                <button
                  key={item.key}
                  type="button"
                  className={cropAspect === item.key ? "is-active" : ""}
                  onClick={() => chooseAspect(item.key)}
                >
                  {item.label}
                </button>
              ))}
              <button type="button" onClick={selectWholeImage} title="Lấy toàn bộ ảnh, không cắt">
                <Maximize size={13} /> Toàn bộ ảnh
              </button>
              <button type="button" onClick={resetCrop} title="Đặt lại vùng chọn">
                <RotateCcw size={13} /> Đặt lại
              </button>
              <label className="crop-zoom">
                <ZoomIn size={14} />
                <input
                  type="range"
                  min="1"
                  max="3"
                  step=".05"
                  value={zoom}
                  onChange={event => setZoom(Number(event.target.value))}
                />
                {zoom.toFixed(2)}x
              </label>
            </div>
            <div
              ref={stageRef}
              className={drag ? "crop-stage is-dragging" : "crop-stage"}
              onPointerMove={moveDrag}
              onPointerUp={endDrag}
              onPointerCancel={endDrag}
            >
              {source && (
                <img
                  src={source}
                  alt="Ảnh đang cắt"
                  draggable={false}
                  onLoad={event =>
                    setNatural({ width: event.currentTarget.naturalWidth, height: event.currentTarget.naturalHeight })
                  }
                  onPointerDown={event => startDrag("move", event)}
                  style={
                    imageBox
                      ? { left: imageBox.x, top: imageBox.y, width: imageBox.width, height: imageBox.height }
                      : undefined
                  }
                />
              )}
              {crop && (
                <div
                  className="crop-selection"
                  style={{ left: crop.x, top: crop.y, width: crop.width, height: crop.height }}
                  onPointerDown={event => startDrag("move", event)}
                >
                  {handles.map(handle => (
                    <span
                      key={handle}
                      className={`crop-handle crop-handle-${handle}`}
                      onPointerDown={event => startDrag(handle, event)}
                    />
                  ))}
                </div>
              )}
              {!natural.width && <span className="crop-stage-loading">Đang mở ảnh…</span>}
            </div>
            <div className="crop-dialog-actions">
              <button type="button" className="button button-ghost" onClick={() => setCropOpen(false)} disabled={uploadImage.isPending}>
                Huỷ
              </button>
              <button type="button" className="button button-primary" onClick={cropImage} disabled={!crop || uploadImage.isPending}>
                <Check size={14} /> Cắt &amp; tải lên
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

/**
 * Ảnh đại diện, poster, thumbnail… là những khối nặng (khung cắt ảnh, tải lên, xem trước).
 *
 * Bộ so sánh chỉ xét dữ liệu hiển thị nên khi quản trị viên gõ ở ô khác trong form,
 * các khối ảnh không dựng lại — đây là phần tốn thời gian nhất khi form dài.
 */
export default memo(
  ImagePicker,
  (prev, next) =>
    prev.value === next.value &&
    prev.aspect === next.aspect &&
    prev.label === next.label &&
    prev.hint === next.hint &&
    prev.className === next.className,
);
