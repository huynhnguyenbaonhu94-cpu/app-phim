import Constants from "expo-constants";

export type Episode = {
  name?: string;
  slug?: string;
  filename?: string;
  link?: string;
  link_m3u8?: string;
  link_embed?: string;
  embedUrl?: string | null;
  streamUrl?: string | null;
  [key: string]: unknown;
};

export type MovieServer = {
  name?: string;
  isAi?: boolean;
  episodes?: Episode[];
  [key: string]: unknown;
};

export type Movie = {
  id?: string | number; slug: string; name: string; originName?: string; poster?: string; backdrop?: string; thumb?: string;
  thumb_url?: string; poster_url?: string; description?: string; content?: string; year?: number;
  quality?: string; episodeCurrent?: string; episodeTotal?: number; rating?: number; views?: number;
  categories?: { name: string; slug?: string }[]; countries?: { name: string; slug?: string }[]; country?: { name: string; slug?: string }[];
  actors?: string[]; directors?: string[]; createdAt?: string | null; updatedAt?: string | null; tmdbId?: string | null; imdbId?: string | null;
  episodes?: Episode[]; servers?: MovieServer[]; [key: string]: unknown;
};
const base = String(Constants.expoConfig?.extra?.apiBaseUrl || "https://cungcapicloud.id.vn").replace(/\/$/, "");
const imageBase = base;
export const absoluteUrl = (value?: string | null) => {
  if (!value) return undefined;
  if (/^https?:\/\//i.test(value)) return value;
  return `${base}${value.startsWith("/") ? value : `/${value}`}`;
};
export const imageUrl = (value?: string | null) => absoluteUrl(value);
export const unwrap = (payload: any) => payload?.result?.data?.json ?? payload?.result?.data ?? payload;
export async function trpcQuery<T>(path: string, input?: unknown): Promise<T> {
  const query = input === undefined ? "" : `?input=${encodeURIComponent(JSON.stringify({ json: input }))}`;
  const response = await fetch(`${base}/api/trpc/${path}${query}`, { headers: { Accept: "application/json" } });
  if (!response.ok) throw new Error(`API ${response.status}`);
  return unwrap(await response.json()) as T;
}
export const api = {
  home: (page = 1) => trpcQuery<{ items: Movie[]; pagination?: any }>("cinema.home", { page }),
  list: (page = 1, kind: "latest" | "single" | "series" = "latest", filters: Record<string, unknown> = {}) => trpcQuery<{ items: Movie[]; pagination?: any }>("cinema.list", { page, kind, ...filters }),
  search: (keyword: string) => trpcQuery<{ items: Movie[] }>("cinema.search", { keyword, page: 1 }),
  detail: (slug: string) => trpcQuery<Movie>("cinema.detail", { slug }),
  meta: () => trpcQuery<any>("cinema.meta"),
};
