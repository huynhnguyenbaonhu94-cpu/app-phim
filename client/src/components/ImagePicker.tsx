import { useEffect, useRef, useState } from "react";
import { Check, Crop, Image as ImageIcon, LoaderCircle, Upload, X, ZoomIn } from "lucide-react";
import { trpc } from "@/lib/trpc";

type CropAspect = "poster" | "thumbnail" | "actor" | "free";

type Point = { x: number; y: number };
type Rect = { x: number; y: number; width: number; height: number };

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

function initialCrop(width: number, height: number, ratio: number | null): Rect {
  const sourceRatio = width / height;
  let cropWidth = width * 0.82;
  let cropHeight = height * 0.82;
  if (ratio && sourceRatio > ratio) cropWidth = cropHeight * ratio;
  if (ratio && sourceRatio < ratio) cropHeight = cropWidth / ratio;
  return { x: (width - cropWidth) / 2, y: (height - cropHeight) / 2, width: cropWidth, height: cropHeight };
}

export default function ImagePicker({
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

  const [cropOpen, setCropOpen] = useState(false);
  const [cropAspect, setCropAspect] = useState<CropAspect>(aspect);
  const [imageSize, setImageSize] = useState({ width: 0, height: 0 });
  const [imageRect, setImageRect] = useState<DOMRect | null>(null);
  const [crop, setCrop] = useState<Rect | null>(null);
  const [zoom, setZoom] = useState(1);
  const [drag, setDrag] = useState<{ start: Point; origin: Rect } | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setSource(value);
    setLinkDraft(isRemoteLink(value) ? value : "");
    setPreviewFailed(false);
  }, [value]);

  useEffect(
    () => () => {
      if (importTimer.current) window.clearTimeout(importTimer.current);
    },
    [],
  );

  const sourceIsLocal = source.startsWith("data:");
  const busy = uploadImage.isPending || linkState === "loading" || linkState === "importing";
  const currentRatio = cropAspect === "free" ? null : aspectValues[cropAspect];
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
    setCropOpen(true);
  }

  function chooseAspect(next: CropAspect) {
    setCropAspect(next);
    if (imageRect) setCrop(initialCrop(imageRect.width, imageRect.height, next === "free" ? null : aspectValues[next]));
  }

  function handleImageLoad(event: React.SyntheticEvent<HTMLImageElement>) {
    const image = event.currentTarget;
    setPreviewFailed(false);
    setImageSize({ width: image.naturalWidth, height: image.naturalHeight });
    requestAnimationFrame(() => {
      const rect = image.getBoundingClientRect();
      setImageRect(rect);
      setCrop(initialCrop(rect.width, rect.height, currentRatio));
    });
  }

  function pointInImage(event: React.PointerEvent) {
    const stage = stageRef.current;
    if (!stage || !imageRect) return null;
    const stageRect = stage.getBoundingClientRect();
    return {
      x: clamp(event.clientX - stageRect.left, imageRect.left - stageRect.left, imageRect.right - stageRect.left),
      y: clamp(event.clientY - stageRect.top, imageRect.top - stageRect.top, imageRect.bottom - stageRect.top),
    };
  }

  function beginDrag(event: React.PointerEvent) {
    if (!crop || !imageRect) return;
    const point = pointInImage(event);
    if (!point) return;
    event.currentTarget.setPointerCapture(event.pointerId);
    setDrag({ start: point, origin: crop });
  }

  function moveDrag(event: React.PointerEvent) {
    if (!drag || !imageRect || !stageRef.current) return;
    const point = pointInImage(event);
    if (!point) return;
    const stageRect = stageRef.current.getBoundingClientRect();
    const offsetX = imageRect.left - stageRect.left;
    const offsetY = imageRect.top - stageRect.top;
    const maxWidth = imageRect.width;
    const maxHeight = imageRect.height;
    const deltaX = point.x - drag.start.x;
    const deltaY = point.y - drag.start.y;
    setCrop({
      ...drag.origin,
      x: clamp(drag.origin.x + deltaX, offsetX, offsetX + maxWidth - drag.origin.width),
      y: clamp(drag.origin.y + deltaY, offsetY, offsetY + maxHeight - drag.origin.height),
    });
  }

  function cropImage() {
    if (!crop || !imageRect || !imageSize.width || !stageRef.current) return;
    const image = stageRef.current.querySelector("img");
    if (!image) return;
    const stageRect = stageRef.current.getBoundingClientRect();
    const scaleX = imageSize.width / imageRect.width;
    const scaleY = imageSize.height / imageRect.height;
    const sx = Math.max(0, ((crop.x - (imageRect.left - stageRect.left)) * scaleX) / zoom);
    const sy = Math.max(0, ((crop.y - (imageRect.top - stageRect.top)) * scaleY) / zoom);
    const sw = Math.min(imageSize.width - sx, (crop.width * scaleX) / zoom);
    const sh = Math.min(imageSize.height - sy, (crop.height * scaleY) / zoom);
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(sw));
    canvas.height = Math.max(1, Math.round(sh));
    const context = canvas.getContext("2d");
    if (!context) {
      setError("Trình duyệt không hỗ trợ cắt ảnh.");
      return;
    }
    try {
      context.drawImage(image, sx, sy, sw, sh, 0, 0, canvas.width, canvas.height);
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
      setCropOpen(true);
    } catch (fileError) {
      setError(fileError instanceof Error ? fileError.message : "Không thể đọc ảnh.");
    }
  }

  const displayedCrop = crop && imageRect && stageRef.current ? { ...crop } : null;
  const showPreview = Boolean(source) && !previewFailed;

  return (
    <div className={`image-picker ${className}`}>
      <div className="image-picker-label">
        <strong>{label}</strong>
        <span>{hint || "Tải ảnh lên hoặc dán link"}</span>
      </div>
      <div className="image-picker-row">
        <div className={busy ? "image-picker-preview is-loading" : "image-picker-preview"}>
          {showPreview ? (
            <img src={source} alt="Xem trước" key={source} onLoad={handleImageLoad} onError={() => setPreviewFailed(true)} />
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
            {source && (
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
        <p className="image-picker-error">Không hiện được ảnh xem trước từ link này. Kiểm tra lại link ảnh.</p>
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
                <span>Kéo vùng chọn để cắt ảnh</span>
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
              <label className="crop-zoom">
                <ZoomIn size={14} />
                <input type="range" min="1" max="2.5" step=".1" value={zoom} onChange={event => setZoom(Number(event.target.value))} />
                {zoom.toFixed(1)}x
              </label>
            </div>
            <div
              ref={stageRef}
              className="crop-stage"
              onPointerDown={beginDrag}
              onPointerMove={moveDrag}
              onPointerUp={() => setDrag(null)}
              onPointerCancel={() => setDrag(null)}
            >
              {source && <img src={source} alt="Ảnh đang cắt" onLoad={handleImageLoad} style={{ transform: `scale(${zoom})` }} />}
              {displayedCrop && (
                <div
                  className="crop-selection"
                  style={{ left: displayedCrop.x, top: displayedCrop.y, width: displayedCrop.width, height: displayedCrop.height }}
                >
                  <span />
                </div>
              )}
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