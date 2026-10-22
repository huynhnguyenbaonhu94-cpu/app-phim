import { useEffect, useRef, useState } from "react";
import { Check, ChevronDown } from "lucide-react";

export type SelectOption = { value: string; label: string };

/**
 * Danh sách chọn tự dựng thay cho `<select>` của trình duyệt.
 *
 * `<select>` mở ra một bảng do hệ điều hành vẽ nên không thể chỉnh theo giao diện
 * của trang — đó là lý do danh sách chọn trước đây trông lệch hẳn so với phần còn
 * lại. Component này vẽ đúng tông màu tối của Cinemora, có bàn phím và đóng khi
 * bấm ra ngoài.
 */
export function SelectField({
  value,
  options,
  onChange,
  disabled,
  ariaLabel,
  placeholder = "Chưa chọn",
}: {
  value: string;
  options: SelectOption[];
  onChange: (value: string) => void;
  disabled?: boolean;
  ariaLabel?: string;
  placeholder?: string;
}) {
  const [open, setOpen] = useState(false);
  const [activeIndex, setActiveIndex] = useState(0);
  const rootRef = useRef<HTMLDivElement>(null);

  const currentIndex = options.findIndex((option) => option.value === value);
  const current = currentIndex >= 0 ? options[currentIndex] : undefined;

  // Bấm ra ngoài hoặc nhấn Esc thì đóng danh sách.
  useEffect(() => {
    if (!open) return;
    setActiveIndex(currentIndex >= 0 ? currentIndex : 0);
    const onPointerDown = (event: MouseEvent | TouchEvent) => {
      if (rootRef.current && !rootRef.current.contains(event.target as Node)) setOpen(false);
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false);
    };
    document.addEventListener("mousedown", onPointerDown);
    document.addEventListener("touchstart", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("mousedown", onPointerDown);
      document.removeEventListener("touchstart", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [open, currentIndex]);

  function choose(index: number) {
    const option = options[index];
    if (!option) return;
    onChange(option.value);
    setOpen(false);
  }

  return (
    <div className={`sel-field${open ? " is-open" : ""}${disabled ? " is-disabled" : ""}`} ref={rootRef}>
      <button
        type="button"
        className="sel-trigger"
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-label={ariaLabel}
        disabled={disabled}
        onClick={() => setOpen((previous) => !previous)}
        onKeyDown={(event) => {
          if (event.key === "ArrowDown" || event.key === "ArrowUp") {
            event.preventDefault();
            setOpen(true);
          }
        }}
      >
        <span className={`sel-value${current ? "" : " is-placeholder"}`}>{current?.label ?? placeholder}</span>
        <ChevronDown size={14} className="sel-caret" />
      </button>

      {open && (
        <div
          className="sel-menu"
          role="listbox"
          tabIndex={-1}
          onKeyDown={(event) => {
            if (event.key === "ArrowDown") {
              event.preventDefault();
              setActiveIndex((index) => Math.min(index + 1, options.length - 1));
            } else if (event.key === "ArrowUp") {
              event.preventDefault();
              setActiveIndex((index) => Math.max(index - 1, 0));
            } else if (event.key === "Enter") {
              event.preventDefault();
              choose(activeIndex);
            }
          }}
        >
          {options.map((option, index) => (
            <button
              type="button"
              key={option.value}
              role="option"
              aria-selected={option.value === value}
              className={`sel-option${option.value === value ? " is-active" : ""}${index === activeIndex ? " is-cursor" : ""}`}
              onMouseEnter={() => setActiveIndex(index)}
              onClick={() => choose(index)}
            >
              <span>{option.label}</span>
              {option.value === value && <Check size={14} />}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}