import { Check, ChevronDown, Search, X } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";

type SearchableOption = { value: string; label: string };

type SearchableSelectProps = {
  value: string;
  options: SearchableOption[];
  onChange: (value: string) => void;
  placeholder: string;
  searchPlaceholder?: string;
  ariaLabel: string;
  emptyLabel?: string;
  compact?: boolean;
  includePlaceholderOption?: boolean;
};

export function SearchableSelect({ value, options, onChange, placeholder, searchPlaceholder = "Tìm nhanh...", ariaLabel, emptyLabel = "Không có lựa chọn phù hợp", compact = false, includePlaceholderOption = true }: SearchableSelectProps) {
  const rootRef = useRef<HTMLDivElement | null>(null);
  const searchRef = useRef<HTMLInputElement | null>(null);
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState("");
  const selected = options.find((option) => option.value === value);
  const filtered = useMemo(() => {
    const keyword = search.trim().toLocaleLowerCase();
    return keyword ? options.filter((option) => option.label.toLocaleLowerCase().includes(keyword)) : options;
  }, [options, search]);

  useEffect(() => {
    function closeOnOutside(event: MouseEvent) {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    }
    function closeOnEscape(event: KeyboardEvent) {
      if (event.key === "Escape") setOpen(false);
    }
    document.addEventListener("mousedown", closeOnOutside);
    document.addEventListener("keydown", closeOnEscape);
    return () => { document.removeEventListener("mousedown", closeOnOutside); document.removeEventListener("keydown", closeOnEscape); };
  }, []);

  useEffect(() => {
    if (open) window.requestAnimationFrame(() => searchRef.current?.focus());
    else setSearch("");
  }, [open]);

  function choose(nextValue: string) {
    onChange(nextValue);
    setOpen(false);
    setSearch("");
  }

  return <div ref={rootRef} className={`searchable-select ${compact ? "searchable-select-compact" : ""} ${open ? "is-open" : ""}`}>
    <button type="button" className="searchable-select-trigger" aria-haspopup="listbox" aria-expanded={open} aria-label={ariaLabel} onClick={() => setOpen((current) => !current)}>
      <span className={selected ? "" : "is-placeholder"}>{selected?.label || placeholder}</span><ChevronDown size={15} className="searchable-select-chevron" />
    </button>
    {open && <div className="searchable-select-popover" role="dialog" aria-label={`${ariaLabel} options`}>
      <div className="searchable-select-search"><Search size={14} /><input ref={searchRef} value={search} onChange={(event) => setSearch(event.target.value)} placeholder={searchPlaceholder} aria-label={`Tìm trong ${ariaLabel}`} /><button type="button" aria-label="Đóng danh sách lựa chọn" onClick={() => { setSearch(""); setOpen(false); }}><X size={15} /></button></div>
      <div className="searchable-select-options" role="listbox" aria-label={ariaLabel}>
        {includePlaceholderOption && <button type="button" role="option" aria-selected={!value} className={!value ? "is-selected" : ""} onClick={() => choose("")}><span>{placeholder}</span>{!value && <Check size={14} />}</button>}
        {filtered.map((option) => <button type="button" role="option" aria-selected={option.value === value} className={option.value === value ? "is-selected" : ""} key={option.value} onClick={() => choose(option.value)}><span>{option.label}</span>{option.value === value && <Check size={14} />}</button>)}
        {!filtered.length && <div className="searchable-select-empty">{emptyLabel}</div>}
      </div>
      <div className="searchable-select-footer">{filtered.length} lựa chọn</div>
    </div>}
  </div>;
}
