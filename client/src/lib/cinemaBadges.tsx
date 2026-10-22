/**
 * Nhãn hiển thị (badge) và kiểu tên người dùng — dùng chung cho trang quản trị.
 *
 * Dữ liệu do máy chủ trả về ở dạng chuỗi JSON (`users.badges`, `users.nameStyle`).
 * Mọi nơi hiển thị đều đi qua tệp này để nhãn trên web giống hệt nhãn trong app.
 */

export type BadgeStyle = "solid" | "gradient" | "outline" | "glow" | "shine" | "pulse" | "neon" | "gold" | "hologram";
export type BadgeFont = "sans" | "serif" | "mono" | "script";
export type BadgeSize = "sm" | "md" | "lg";
export type BadgeAnimation = "none" | "pulse" | "shine" | "float" | "bounce" | "tilt" | "blink";
export type NameEffect =
  | "none"
  | "glow"
  | "gradient"
  | "shine"
  | "rainbow"
  | "outline"
  | "neon"
  | "gold"
  | "ice"
  | "fire"
  | "shadow"
  | "underline"
  | "breathe";

export type CinemaBadge = {
  id: string;
  type: "text" | "image";
  text: string;
  imageUrl: string;
  color: string;
  background: string;
  style: BadgeStyle;
  font: BadgeFont;
  size: BadgeSize;
  animation: BadgeAnimation;
};

export type CinemaNameStyle = { color: string; effect: NameEffect };

const STYLES: BadgeStyle[] = ["solid", "gradient", "outline", "glow", "shine", "pulse", "neon", "gold", "hologram"];
const FONTS: BadgeFont[] = ["sans", "serif", "mono", "script"];
const SIZES: BadgeSize[] = ["sm", "md", "lg"];
const ANIMATIONS: BadgeAnimation[] = ["none", "pulse", "shine", "float", "bounce", "tilt", "blink"];
const EFFECTS: NameEffect[] = ["none", "glow", "gradient", "shine", "rainbow", "outline", "neon", "gold", "ice", "fire", "shadow", "underline", "breathe"];

export function emptyBadge(index: number): CinemaBadge {
  return {
    id: `b${index + 1}`,
    type: "text",
    text: "",
    imageUrl: "",
    color: "#d2f36b",
    background: "",
    style: "solid",
    font: "sans",
    size: "md",
    animation: "none",
  };
}

/** Đọc danh sách nhãn từ chuỗi JSON, chấp nhận cả dữ liệu hỏng mà không làm vỡ trang. */
export function parseBadges(raw: unknown): CinemaBadge[] {
  if (typeof raw !== "string" || raw.trim().length === 0) return [];
  try {
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.slice(0, 6).map((item, index) => ({
      id: String(item?.id ?? `b${index + 1}`),
      type: item?.type === "image" ? "image" : "text",
      text: String(item?.text ?? ""),
      imageUrl: String(item?.imageUrl ?? ""),
      color: String(item?.color ?? ""),
      background: String(item?.background ?? ""),
      style: (STYLES.includes(item?.style) ? item.style : "solid") as BadgeStyle,
      font: (FONTS.includes(item?.font) ? item.font : "sans") as BadgeFont,
      size: (SIZES.includes(item?.size) ? item.size : "md") as BadgeSize,
      animation: (ANIMATIONS.includes(item?.animation) ? item.animation : "none") as BadgeAnimation,
    }));
  } catch {
    return [];
  }
}

export function parseNameStyle(raw: unknown): CinemaNameStyle {
  if (typeof raw !== "string" || raw.trim().length === 0) return { color: "", effect: "none" };
  try {
    const parsed = JSON.parse(raw);
    return {
      color: String(parsed?.color ?? ""),
      effect: (EFFECTS.includes(parsed?.effect) ? parsed.effect : "none") as NameEffect,
    };
  } catch {
    return { color: "", effect: "none" };
  }
}

/** Danh sách nhãn của một tài khoản, có đường dự phòng cho tài khoản cũ chỉ có 1 nhãn chữ. */
export function accountBadges(badgesJson: unknown, legacyBadge: unknown): CinemaBadge[] {
  const badges = parseBadges(badgesJson);
  if (badges.length > 0) return badges;
  const legacy = typeof legacyBadge === "string" ? legacyBadge.trim() : "";
  return legacy.length > 0 ? [{ ...emptyBadge(0), id: "legacy", text: legacy }] : [];
}

export function BadgeChip({ badge }: { badge: CinemaBadge }) {
  if (badge.type === "image") {
    return badge.imageUrl
      ? <img className="cin-badge cin-badge--image" src={badge.imageUrl} alt={badge.text || "Nhãn"} loading="lazy" />
      : null;
  }
  if (!badge.text.trim()) return null;
  const classes = [
    "cin-badge",
    `cin-badge--${badge.style}`,
    `cin-badge--${badge.size}`,
    `cin-badge--font-${badge.font}`,
    badge.animation !== "none" ? `cin-badge--anim-${badge.animation}` : "",
  ].filter(Boolean).join(" ");
  return (
    <span className={classes} style={{ color: badge.color || undefined, "--cin-badge-bg": badge.background || undefined } as React.CSSProperties}>
      {badge.text}
    </span>
  );
}

export function BadgeChipList({ badges }: { badges: CinemaBadge[] }) {
  if (badges.length === 0) return null;
  return <>{badges.map((badge) => <BadgeChip key={badge.id} badge={badge} />)}</>;
}

export function NameText({ name, style }: { name: string; style: CinemaNameStyle }) {
  if (style.effect === "none" && !style.color) return <>{name}</>;
  return (
    <span
      className={`cin-name cin-name--${style.effect}`}
      // `--cin-name-color` để hiệu ứng viền chữ vẽ được đường viền đúng màu:
      // trước đây viền dùng `currentColor` mà chữ lại đặt trong suốt nên tên biến mất.
      style={{ color: style.color || undefined, "--cin-name-color": style.color || "#ffffff" } as React.CSSProperties}
    >
      {name}
    </span>
  );
}