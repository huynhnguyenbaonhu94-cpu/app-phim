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
  let cropWidth = width * .82;
  let cropHeight = height * .82;
  if (ratio && sourceRatio > ratio) cropWidth = cropHeight * ratio;
  if (ratio && sourceRatio < ratio) cropHeight = cropWidth / ratio;
  return { x: (width - cropWidth) / 2, y: (height - cropHeight) / 2, width: cropWidth, height: cropHeight };
}

export default function ImagePicker({ value, onChange, label = "Ảnh", aspect = "free", hint, className = "" }: ImagePickerProps) {
  const uploadImage = trpc.customMovies.uploadImage.useMutation();
  const fileInput = useRef<HTMLInputElement>(null);
  const stageRef = useRef<HTMLDivElement>(null);
  const [source, setSource] = useState(value);
  const [sourceName, setSourceName] = useState("");
  const [cropOpen, setCropOpen] = useState(false);
  const [cropAspect, setCropAspect] = useState<CropAspect>(aspect);
  const [imageSize, setImageSize] = useState({ width: 0, height: 0 });
  const [imageRect, setImageRect] = useState<DOMRect | null>(null);
  const [crop, setCrop] = useState<Rect | null>(null);
  const [zoom, setZoom] = useState(1);
  const [drag, setDrag] = useState<{ start: Point; origin: Rect } | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => setSource(value), [value]);

  const sourceIsLocal = source.startsWith("data:");
  const currentRatio = cropAspect === "free" ? null : aspectValues[cropAspect];

  function openCrop() {
    if (!source) {
      setError("Hãy chọn ảnh hoặc dán link trước.");
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
    setImageSize({ width: image.naturalWidth, height: image.naturalHeight });
    requestAnimationFrame(() => { const rect = image.getBoundingClientRect(); setImageRect(rect); setCrop(initialCrop(rect.width, rect.height, currentRatio)); });
  }

  function pointInImage(event: React.PointerEvent) {
    const stage = stageRef.current;
    if (!stage || !imageRect) return null;
    const stageRect = stage.getBoundingClientRect();
    return { x: clamp(event.clientX - stageRect.left, imageRect.left - stageRect.left, imageRect.right - stageRect.left), y: clamp(event.clientY - stageRect.top, imageRect.top - stageRect.top, imageRect.bottom - stageRect.top) };
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
    const next = { ...drag.origin, x: clamp(drag.origin.x + deltaX, offsetX, offsetX + maxWidth - drag.origin.width), y: clamp(drag.origin.y + deltaY, offsetY, offsetY + maxHeight - drag.origin.height) };
    setCrop(next);
  }

  function cropImage() {
    if (!crop || !imageRect || !imageSize.width || !stageRef.current) return;
    const image = stageRef.current.querySelector("img");
    if (!image) return;
    const stageRect = stageRef.current.getBoundingClientRect();
    const scaleX = imageSize.width / imageRect.width;
    const scaleY = imageSize.height / imageRect.height;
    const sx = Math.max(0, (crop.x - (imageRect.left - stageRect.left)) * scaleX / zoom);
    const sy = Math.max(0, (crop.y - (imageRect.top - stageRect.top)) * scaleY / zoom);
    const sw = Math.min(imageSize.width - sx, crop.width * scaleX / zoom);
    const sh = Math.min(imageSize.height - sy, crop.height * scaleY / zoom);
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
      const mimeType = /png/i.test(sourceName) || /^data:image\/png/i.test(source) ? "image/png" : "image/jpeg";
      const base64 = canvas.toDataURL(mimeType, .9);
      setCropOpen(false);
      void uploadCropped(base64, mimeType);
    } catch {
      setError("Không thể cắt ảnh từ link ngoài này. Hãy tải tệp ảnh về rồi chọn lại.");
    }
  }

  async function uploadCropped(base64: string, mimeType: string) {
    setError(null);
    try {
      const result = await uploadImage.mutateAsync({ base64, filename: sourceName || `movie-image.${mimeType === "image/png" ? "png" : "jpg"}`, mimeType });
      onChange(result.url);
      setSource(result.url);
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
      setCropOpen(true);
    } catch (fileError) {
      setError(fileError instanceof Error ? fileError.message : "Không thể đọc ảnh.");
    }
  }

  function setExternalLink(next: string) {
    setSource(next);
    setError(null);
    onChange(next);
  }

  const displayedCrop = crop && imageRect && stageRef.current ? { ...crop, width: crop.width, height: crop.height } : null;

  return <div className={`image-picker ${className}`}>
    <div className="image-picker-label"><strong>{label}</strong><span>{hint || "Tải ảnh lên hoặc dán link"}</span></div>
    <div className="image-picker-row">
      <div className="image-picker-preview">{source ? <img src={source} alt="Xem trước" onError={() => setError("Không thể tải ảnh từ link này.")} /> : <ImageIcon size={23} />}</div>
      <div className="image-picker-controls">
        <div className="image-picker-link-row"><input value={sourceIsLocal ? "" : value} onChange={event => setExternalLink(event.target.value)} placeholder="https://…/image.jpg" aria-label={`${label} URL`} /><button type="button" className="button button-ghost image-picker-upload" onClick={() => fileInput.current?.click()}><Upload size={14} /> Chọn ảnh</button><input ref={fileInput} type="file" accept="image/jpeg,image/png,image/webp" hidden onChange={event => { void handleFile(event.target.files?.[0]); event.currentTarget.value = ""; }} /></div>
        <div className="image-picker-actions">{source && <button type="button" className="button button-ghost" onClick={openCrop} disabled={uploadImage.isPending}><Crop size={14} /> Chỉnh sửa</button>}{uploadImage.isPending && <span className="image-picker-uploading"><LoaderCircle size={14} className="spin" /> Đang tải ảnh…</span>}</div>
      </div>
    </div>
    {error && <p className="image-picker-error">{error}</p>}
    {cropOpen && <div className="crop-dialog-backdrop" role="presentation" onMouseDown={event => { if (event.target === event.currentTarget && !uploadImage.isPending) setCropOpen(false); }}><div className="crop-dialog" role="dialog" aria-modal="true" aria-label={`Chỉnh sửa ${label}`}>
      <div className="crop-dialog-heading"><div><strong>Chỉnh sửa {label.toLocaleLowerCase("vi-VN")}</strong><span>Kéo vùng chọn để cắt ảnh</span></div><button type="button" className="admin-tv-refresh" onClick={() => setCropOpen(false)} disabled={uploadImage.isPending} aria-label="Đóng"><X size={16} /></button></div>
      <div className="crop-toolbar">{aspectLabels.map(item => <button key={item.key} type="button" className={cropAspect === item.key ? "is-active" : ""} onClick={() => chooseAspect(item.key)}>{item.label}</button>)}<label className="crop-zoom"><ZoomIn size={14} /><input type="range" min="1" max="2.5" step=".1" value={zoom} onChange={event => setZoom(Number(event.target.value))} /> {zoom.toFixed(1)}x</label></div>
      <div ref={stageRef} className="crop-stage" onPointerDown={beginDrag} onPointerMove={moveDrag} onPointerUp={() => setDrag(null)} onPointerCancel={() => setDrag(null)}>{source && <img src={source} alt="Ảnh đang cắt" onLoad={handleImageLoad} style={{ transform: `scale(${zoom})` }} />}{displayedCrop && <div className="crop-selection" style={{ left: displayedCrop.x, top: displayedCrop.y, width: displayedCrop.width, height: displayedCrop.height }}><span /></div>}</div>
      <div className="crop-dialog-actions"><button type="button" className="button button-ghost" onClick={() => setCropOpen(false)} disabled={uploadImage.isPending}>Huỷ</button><button type="button" className="button button-primary" onClick={cropImage} disabled={!crop || uploadImage.isPending}><Check size={14} /> Cắt &amp; tải lên</button></div>
    </div></div>}
  </div>;
}
