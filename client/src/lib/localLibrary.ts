export type LocalMovie = {
  id: string;
  slug: string;
  name: string;
  originName: string;
  poster: string | null;
  year: number | null;
  quality: string;
  episodeCurrent: string;
  rating: number | null;
  categories: Array<{ name: string; slug: string }>;
};

export type LocalHistory = LocalMovie & {
  episodeSlug: string;
  episodeName: string;
  watchedSeconds: number;
  durationSeconds: number;
  lastWatchedAt: string;
};

const FAVORITES_KEY = "cinemora:favorites:v1";
const HISTORY_KEY = "cinemora:history:v1";
const CHANGE_EVENT = "cinemora-library-change";

function canUseStorage() { return typeof window !== "undefined" && typeof window.localStorage !== "undefined"; }
function read<T>(key: string): T[] {
  if (!canUseStorage()) return [];
  try {
    const value = JSON.parse(window.localStorage.getItem(key) || "[]");
    return Array.isArray(value) ? value as T[] : [];
  } catch { return []; }
}
function write<T>(key: string, value: T[]) {
  if (!canUseStorage()) return;
  window.localStorage.setItem(key, JSON.stringify(value));
  window.dispatchEvent(new CustomEvent(CHANGE_EVENT));
}

export function listFavorites() { return read<LocalMovie>(FAVORITES_KEY); }
export function isFavorite(slug: string) { return listFavorites().some((movie) => movie.slug === slug); }
export function toggleFavorite(movie: LocalMovie) {
  const favorites = listFavorites();
  const next = favorites.some((item) => item.slug === movie.slug) ? favorites.filter((item) => item.slug !== movie.slug) : [movie, ...favorites];
  write(FAVORITES_KEY, next);
  return next.some((item) => item.slug === movie.slug);
}
export function removeFavorite(slug: string) { write(FAVORITES_KEY, listFavorites().filter((movie) => movie.slug !== slug)); }

export function listHistory() { return read<LocalHistory>(HISTORY_KEY); }
export function saveHistory(item: Omit<LocalHistory, "lastWatchedAt">) {
  const history = listHistory().filter((entry) => !(entry.slug === item.slug && entry.episodeSlug === item.episodeSlug));
  write(HISTORY_KEY, [{ ...item, lastWatchedAt: new Date().toISOString() }, ...history].slice(0, 100));
}
export function subscribeLibrary(callback: () => void) {
  if (!canUseStorage()) return () => undefined;
  const onStorage = () => callback();
  const onLocalChange = () => callback();
  window.addEventListener("storage", onStorage);
  window.addEventListener(CHANGE_EVENT, onLocalChange);
  return () => { window.removeEventListener("storage", onStorage); window.removeEventListener(CHANGE_EVENT, onLocalChange); };
}
export function removeHistory(slug: string, episodeSlug?: string) {
  const history = listHistory().filter((entry) =>
    episodeSlug ? !(entry.slug === slug && entry.episodeSlug === episodeSlug) : entry.slug !== slug
  );
  write(HISTORY_KEY, history);
}
export function updateHistoryPoster(slug: string, episodeSlug: string, poster: string) {
  const history = listHistory().map((entry) =>
    entry.slug === slug && entry.episodeSlug === episodeSlug ? { ...entry, poster } : entry
  );
  write(HISTORY_KEY, history);
}
export function clearHistory() { write(HISTORY_KEY, []); }
