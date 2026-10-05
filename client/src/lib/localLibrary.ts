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
const CLOUD_ENABLED_KEY = "cinemora:account-sync:v1";
const AUTO_NEXT_KEY = "cinemora_autonext";
let cloudQueue: Promise<void> = Promise.resolve();
let cloudGeneration = 0;
let cloudUserId: number | null = null;
let historySyncTimer: ReturnType<typeof setTimeout> | undefined;
const pendingHistorySync = new Map<string, Record<string, unknown>>();

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

function isCloudEnabled() { return canUseStorage() && window.localStorage.getItem(CLOUD_ENABLED_KEY) === "1"; }
export function setCloudSyncEnabled(enabled: boolean, userId: number | null = null) {
  if (!canUseStorage()) return;
  const nextUserId = enabled ? userId : null;
  if (cloudUserId !== nextUserId || !enabled) {
    cloudGeneration += 1;
    cloudUserId = nextUserId;
    if (historySyncTimer) clearTimeout(historySyncTimer);
    historySyncTimer = undefined;
    pendingHistorySync.clear();
  }
  if (enabled) window.localStorage.setItem(CLOUD_ENABLED_KEY, "1");
  else window.localStorage.removeItem(CLOUD_ENABLED_KEY);
}

function tRpcPayload(root: any) { return root?.result?.data?.json ?? root?.result?.data?.data ?? null; }
async function cloudQuery(procedure: string) {
  const response = await fetch(`/api/trpc/${procedure}`, { credentials: "same-origin", headers: { Accept: "application/json" } });
  const body = await response.json();
  if (!response.ok || body?.error) throw new Error(body?.error?.json?.message || `API ${procedure} failed`);
  return tRpcPayload(body);
}
function cloudMutation(procedure: string, input: Record<string, unknown>) {
  if (!isCloudEnabled()) return;
  const requestGeneration = cloudGeneration;
  cloudQueue = cloudQueue.then(async () => {
    if (requestGeneration !== cloudGeneration || !isCloudEnabled()) return;
    const response = await fetch(`/api/trpc/${procedure}`, {
      method: "POST", credentials: "same-origin",
      headers: { Accept: "application/json", "Content-Type": "application/json" },
      body: JSON.stringify({ json: input }),
    });
    if (!response.ok) throw new Error(`API ${procedure} failed`);
  }).catch(() => undefined);
}
function scheduleHistoryMutation(key: string, input: Record<string, unknown>) {
  if (!isCloudEnabled()) return;
  pendingHistorySync.set(key, input);
  if (historySyncTimer) clearTimeout(historySyncTimer);
  historySyncTimer = setTimeout(() => {
    const pending = Array.from(pendingHistorySync.values());
    pendingHistorySync.clear();
    for (const item of pending) cloudMutation("account.recordHistory", item);
  }, 1800);
}
export function saveWebAutoNextPreference(enabled: boolean) {
  if (!canUseStorage()) return;
  window.localStorage.setItem(AUTO_NEXT_KEY, enabled ? "on" : "off");
  cloudMutation("account.savePreferences", { preferences: { webAutoNext: enabled } });
  window.dispatchEvent(new Event("cinemora-account-preferences"));
}
function moviePayload(movie: LocalMovie) {
  const input: Record<string, unknown> = { movieSlug: movie.slug, movieName: movie.name };
  if (movie.originName) input.originName = movie.originName;
  if (movie.year) input.year = movie.year;
  if (movie.poster?.startsWith("/api/cinema/image/")) input.posterUrl = movie.poster;
  return input;
}

export function listFavorites() { return read<LocalMovie>(FAVORITES_KEY); }
export function isFavorite(slug: string) { return listFavorites().some((movie) => movie.slug === slug); }
export function toggleFavorite(movie: LocalMovie) {
  const favorites = listFavorites();
  const isRemoving = favorites.some((item) => item.slug === movie.slug);
  const next = isRemoving ? favorites.filter((item) => item.slug !== movie.slug) : [movie, ...favorites];
  write(FAVORITES_KEY, next);
  cloudMutation(isRemoving ? "account.removeFavorite" : "account.addFavorite", isRemoving ? { movieSlug: movie.slug } : moviePayload(movie));
  return !isRemoving;
}
export function removeFavorite(slug: string) {
  write(FAVORITES_KEY, listFavorites().filter((movie) => movie.slug !== slug));
  cloudMutation("account.removeFavorite", { movieSlug: slug });
}

export function listHistory() { return read<LocalHistory>(HISTORY_KEY); }
export function saveHistory(item: Omit<LocalHistory, "lastWatchedAt">) {
  const entry: LocalHistory = { ...item, lastWatchedAt: new Date().toISOString() };
  const history = listHistory().filter((old) => !(old.slug === item.slug && old.episodeSlug === item.episodeSlug));
  write(HISTORY_KEY, [entry, ...history].slice(0, 100));
  const input = moviePayload(entry);
  input.episodeSlug = entry.episodeSlug;
  input.episodeName = entry.episodeName;
  input.watchedSeconds = Math.max(0, Math.floor(entry.watchedSeconds));
  input.durationSeconds = Math.max(0, Math.floor(entry.durationSeconds));
  scheduleHistoryMutation(`${entry.slug}\u0000${entry.episodeSlug}`, input);
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
  const history = listHistory().filter((entry) => episodeSlug ? !(entry.slug === slug && entry.episodeSlug === episodeSlug) : entry.slug !== slug);
  write(HISTORY_KEY, history);
  if (episodeSlug) pendingHistorySync.delete(`${slug}\u0000${episodeSlug}`);
  const input: Record<string, unknown> = { movieSlug: slug };
  if (episodeSlug) input.episodeSlug = episodeSlug;
  cloudMutation("account.deleteHistory", input);
}
export function updateHistoryPoster(slug: string, episodeSlug: string, poster: string) {
  const history = listHistory().map((entry) => entry.slug === slug && entry.episodeSlug === episodeSlug ? { ...entry, poster } : entry);
  write(HISTORY_KEY, history);
}
export function clearHistory() {
  write(HISTORY_KEY, []);
  pendingHistorySync.clear();
  cloudMutation("account.clearHistory", {});
}
export function clearLocalLibrary() {
  if (!canUseStorage()) return;
  write(FAVORITES_KEY, []);
  write(HISTORY_KEY, []);
  window.localStorage.removeItem(AUTO_NEXT_KEY);
  window.dispatchEvent(new Event("cinemora-account-preferences"));
}

export async function syncLocalLibraryToAccount() {
  if (!canUseStorage()) return;
  if (!isCloudEnabled()) return;
  const [remoteFavorites, remoteHistory, remotePreferences] = await Promise.all([
    cloudQuery("account.favorites"), cloudQuery("account.history"), cloudQuery("account.preferences"),
  ]);
  if (typeof remotePreferences?.webAutoNext === "boolean") {
    window.localStorage.setItem(AUTO_NEXT_KEY, remotePreferences.webAutoNext ? "on" : "off");
  } else {
    const localAutoNext = window.localStorage.getItem(AUTO_NEXT_KEY);
    if (localAutoNext === "on" || localAutoNext === "off") cloudMutation("account.savePreferences", { preferences: { webAutoNext: localAutoNext === "on" } });
  }
  window.dispatchEvent(new Event("cinemora-account-preferences"));
  const favoriteMap = new Map<string, LocalMovie>();
  for (const item of Array.isArray(remoteFavorites) ? remoteFavorites : []) {
    favoriteMap.set(item.movieSlug, {
      id: item.movieSlug, slug: item.movieSlug, name: item.movieName, originName: item.originName || "",
      poster: item.posterUrl || null, year: item.year || null, quality: "", episodeCurrent: "", rating: null, categories: [],
    });
  }
  for (const item of listFavorites()) if (!favoriteMap.has(item.slug)) favoriteMap.set(item.slug, item);
  const historyMap = new Map<string, LocalHistory>();
  for (const item of Array.isArray(remoteHistory) ? remoteHistory : []) {
    const entry: LocalHistory = {
      id: item.movieSlug, slug: item.movieSlug, name: item.movieName, originName: item.originName || "",
      poster: item.posterUrl || null, year: item.year || null, quality: "", episodeCurrent: "", rating: null, categories: [],
      episodeSlug: item.episodeSlug || "movie", episodeName: item.episodeName || "Phim",
      watchedSeconds: Number(item.watchedSeconds || 0), durationSeconds: Number(item.durationSeconds || 0),
      lastWatchedAt: item.lastWatchedAt || new Date(0).toISOString(),
    };
    const key = `${entry.slug}\u0000${entry.episodeSlug}`;
    historyMap.set(key, entry);
  }
  for (const item of listHistory()) {
    const key = `${item.slug}\u0000${item.episodeSlug}`;
    if (!historyMap.has(key)) historyMap.set(key, item);
  }
  const favorites = Array.from(favoriteMap.values()).slice(0, 100);
  const history = Array.from(historyMap.values()).sort((a, b) => Date.parse(b.lastWatchedAt) - Date.parse(a.lastWatchedAt)).slice(0, 100);
  write(FAVORITES_KEY, favorites);
  write(HISTORY_KEY, history);
  for (const movie of favorites) cloudMutation("account.addFavorite", moviePayload(movie));
  for (const entry of history) {
    const input = moviePayload(entry);
    Object.assign(input, { episodeSlug: entry.episodeSlug, episodeName: entry.episodeName, watchedSeconds: entry.watchedSeconds, durationSeconds: entry.durationSeconds });
    cloudMutation("account.recordHistory", input);
  }
}
