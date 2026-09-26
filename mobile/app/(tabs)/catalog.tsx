import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { ActivityIndicator, FlatList, Pressable, RefreshControl, ScrollView, Text, View } from "react-native";
import { Ionicons } from "@expo/vector-icons";
import { router, useLocalSearchParams } from "expo-router";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { api, Movie } from "@/api";
import { C, GlassMenu, MovieCard, ScreenAtmosphere, styles, useAutoHideTabBar } from "@/ui";

type Kind = "latest" | "single" | "series";
type BrowseMode = "filter" | "categories" | "countries" | "years";
type Option = { name: string; slug: string };
type CatalogMeta = { categories: Option[]; countries: Option[]; years: number[] };
type ListResult = Awaited<ReturnType<typeof api.list>>;

let metaCache: CatalogMeta | null = null;
let metaPromise: Promise<CatalogMeta> | null = null;

async function getCatalogMeta() {
  if (metaCache) return metaCache;
  if (!metaPromise) {
    metaPromise = api.meta().then((meta: any) => {
      const normalize = (items: unknown) => Array.isArray(items)
        ? items.map((item: any) => ({ name: String(item?.name || "").trim(), slug: String(item?.slug || "").trim() })).filter((item: Option) => item.name && item.slug)
        : [];
      const years = Array.isArray(meta?.years)
        ? meta.years.map((year: unknown) => Number(year)).filter((year: number) => Number.isFinite(year)).sort((a: number, b: number) => b - a)
        : [];
      metaCache = { categories: normalize(meta?.categories), countries: normalize(meta?.countries), years };
      return metaCache;
    }).finally(() => { metaPromise = null; });
  }
  return metaPromise;
}

function hasNextPage(result: ListResult, page: number) {
  const pagination = result.pagination as Record<string, unknown> | undefined;
  if (!pagination) return (result.items || []).length >= 12;
  const totalPages = Number(pagination.totalPages ?? pagination.total_pages ?? pagination.pageCount ?? pagination.page_count ?? pagination.total_page);
  if (Number.isFinite(totalPages) && totalPages > 0) return page < totalPages;
  const currentPage = Number(pagination.currentPage ?? pagination.current_page ?? pagination.page);
  const perPage = Number(pagination.itemsPerPage ?? pagination.items_per_page ?? pagination.limit);
  const totalItems = Number(pagination.totalItems ?? pagination.total_items ?? pagination.total);
  return Number.isFinite(currentPage) && Number.isFinite(perPage) && perPage > 0 && Number.isFinite(totalItems)
    ? currentPage * perPage < totalItems
    : (result.items || []).length >= 12;
}

const kindOptions: Array<{ value: Kind; label: string }> = [
  { value: "latest", label: "Mới nhất" },
  { value: "single", label: "Phim lẻ" },
  { value: "series", label: "Phim bộ" },
];

const modeOptions: Array<{ value: BrowseMode; label: string; icon: keyof typeof Ionicons.glyphMap }> = [
  { value: "filter", label: "Bộ lọc", icon: "options-outline" },
  { value: "categories", label: "Thể loại", icon: "film-outline" },
  { value: "countries", label: "Quốc gia", icon: "globe-outline" },
  { value: "years", label: "Năm", icon: "calendar-outline" },
];

const ChipRow = ({ items, selected, onSelect, allLabel }: { items: Array<{ value: string; label: string }>; selected: string; onSelect: (value: string) => void; allLabel?: string }) => (
  <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={catalogStyles.chipRow}>
    {allLabel && <Pressable onPress={() => onSelect("")} style={[catalogStyles.chip, !selected && catalogStyles.chipSelected]}><Text style={[catalogStyles.chipText, !selected && catalogStyles.chipTextSelected]}>{allLabel}</Text></Pressable>}
    {items.map(item => <Pressable key={item.value} onPress={() => onSelect(item.value)} style={[catalogStyles.chip, selected === item.value && catalogStyles.chipSelected]}><Text style={[catalogStyles.chipText, selected === item.value && catalogStyles.chipTextSelected]}>{item.label}</Text></Pressable>)}
  </ScrollView>
);

const Directory = ({ mode, categories, countries, years, selected, onSelect }: { mode: BrowseMode; categories: Option[]; countries: Option[]; years: number[]; selected: string; onSelect: (value: string) => void }) => {
  const options = mode === "categories" ? categories.map(item => ({ value: item.slug, label: item.name })) : mode === "countries" ? countries.map(item => ({ value: item.slug, label: item.name })) : years.map(year => ({ value: String(year), label: String(year) }));
  const title = mode === "categories" ? "Danh sách thể loại" : mode === "countries" ? "Danh sách quốc gia" : "Danh sách năm phát hành";
  const subtitle = mode === "categories" ? "Chọn thể loại để xem các phim tương ứng" : mode === "countries" ? "Chọn quốc gia để khám phá phim" : "Chọn năm để xem phim phát hành trong năm đó";
  return <View style={catalogStyles.directory}><Text style={catalogStyles.directoryTitle}>{title}</Text><Text style={catalogStyles.directorySubtitle}>{subtitle}</Text><View style={catalogStyles.directoryGrid}>{options.map(option => <Pressable key={option.value} onPress={() => onSelect(option.value)} style={[catalogStyles.directoryCard, selected === option.value && catalogStyles.directoryCardSelected]}><Text style={[catalogStyles.directoryCardText, selected === option.value && catalogStyles.directoryCardTextSelected]} numberOfLines={2}>{option.label}</Text><Ionicons name="chevron-forward" size={14} color={selected === option.value ? C.accent : C.muted} /></Pressable>)}</View></View>;
};

export default function Catalog() {
  const insets = useSafeAreaInsets();
  const onScroll = useAutoHideTabBar();
  const params = useLocalSearchParams<{ kind?: string; category?: string; country?: string; year?: string; mode?: string }>();
  const initialKind: Kind = params.kind === "single" || params.kind === "series" ? params.kind : "latest";
  const initialMode: BrowseMode = params.mode === "categories" || params.mode === "countries" || params.mode === "years" ? params.mode : "filter";
  const [mode, setMode] = useState<BrowseMode>(initialMode);
  const [kind, setKind] = useState<Kind>(initialKind);
  const [category, setCategory] = useState(params.category || "");
  const [country, setCountry] = useState(params.country || "");
  const [year, setYear] = useState(params.year || "");
  const [selectedDirectoryValue, setSelectedDirectoryValue] = useState(initialMode === "categories" ? params.category || "" : initialMode === "countries" ? params.country || "" : params.year || "");
  const [meta, setMeta] = useState<CatalogMeta>(metaCache || { categories: [], countries: [], years: [] });
  const [metaLoading, setMetaLoading] = useState(!metaCache);
  const [items, setItems] = useState<Movie[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState("");
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(false);
  const requestId = useRef(0);
  const loadingMoreRef = useRef(false);

  useEffect(() => {
    let active = true;
    setMetaLoading(!metaCache);
    void getCatalogMeta().then(value => { if (active) { setMeta(value); setMetaLoading(false); } }).catch(() => { if (active) setMetaLoading(false); });
    return () => { active = false; };
  }, []);

  const activeFilter = useMemo(() => ({
    ...(category ? { category } : {}),
    ...(country ? { country } : {}),
    ...(year ? { year: Number(year) } : {}),
  }), [category, country, year]);

  const fetchFirstPage = useCallback(async (refresh = false) => {
    const currentRequest = ++requestId.current;
    if (refresh) setRefreshing(true); else setLoading(true);
    setError("");
    try {
      const result = await api.list(1, kind, activeFilter);
      if (requestId.current !== currentRequest) return;
      setItems(result.items || []); setPage(1); setHasMore(hasNextPage(result, 1));
    } catch {
      if (requestId.current === currentRequest) setError("Không thể tải danh sách phim. Vui lòng thử lại.");
    } finally {
      if (requestId.current === currentRequest) { setLoading(false); setRefreshing(false); }
    }
  }, [activeFilter, kind]);

  useEffect(() => { if (mode === "filter" || selectedDirectoryValue) void fetchFirstPage(); }, [fetchFirstPage, mode, selectedDirectoryValue]);

  const changeMode = useCallback((nextMode: BrowseMode) => {
    setMode(nextMode); setSelectedDirectoryValue(""); setItems([]); setError("");
    router.setParams({ mode: nextMode, category: undefined, country: undefined, year: undefined });
  }, []);

  const selectDirectoryValue = useCallback((value: string) => {
    setSelectedDirectoryValue(value); setItems([]);
    if (mode === "categories") { setCategory(value); setCountry(""); setYear(""); router.setParams({ mode, category: value || undefined, country: undefined, year: undefined }); }
    if (mode === "countries") { setCountry(value); setCategory(""); setYear(""); router.setParams({ mode, country: value || undefined, category: undefined, year: undefined }); }
    if (mode === "years") { setYear(value); setCategory(""); setCountry(""); router.setParams({ mode, year: value || undefined, category: undefined, country: undefined }); }
  }, [mode]);

  const selectFilterCategory = useCallback((value: string) => { setCategory(value); }, []);
  const selectFilterCountry = useCallback((value: string) => { setCountry(value); }, []);
  const selectFilterYear = useCallback((value: string) => { setYear(value); }, []);
  const clearFilters = useCallback(() => { setCategory(""); setCountry(""); setYear(""); setSelectedDirectoryValue(""); router.setParams({ mode: "filter", category: undefined, country: undefined, year: undefined }); }, []);

  const loadMore = useCallback(async () => {
    if (!hasMore || loadingMoreRef.current) return;
    loadingMoreRef.current = true; setLoadingMore(true); setError("");
    const nextPage = page + 1; const currentRequest = requestId.current;
    try {
      const result = await api.list(nextPage, kind, activeFilter);
      if (requestId.current !== currentRequest) return;
      setItems(current => [...current, ...(result.items || []).filter(movie => !current.some(existing => existing.slug === movie.slug))]);
      setPage(nextPage); setHasMore((result.items || []).length > 0 && hasNextPage(result, nextPage));
    } catch { setError("Không tải được phim tiếp theo. Hãy thử lại."); }
    finally { loadingMoreRef.current = false; setLoadingMore(false); }
  }, [activeFilter, hasMore, kind, page]);

  const selectedLabel = mode === "categories" ? meta.categories.find(item => item.slug === selectedDirectoryValue)?.name : mode === "countries" ? meta.countries.find(item => item.slug === selectedDirectoryValue)?.name : selectedDirectoryValue;
  const listHeader = <View style={{ paddingTop: insets.top + 7 }}>
    <View style={catalogStyles.header}><View><Text style={catalogStyles.brand}>THƯ VIỆN</Text><Text style={catalogStyles.subtitle}>Khám phá phim theo nhu cầu</Text></View><View style={catalogStyles.headerActions}><Pressable accessibilityLabel="Tìm phim" onPress={() => router.push("/search")} style={catalogStyles.searchButton}><Ionicons name="search" size={19} color={C.text} /></Pressable><GlassMenu /></View></View>
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={catalogStyles.modeRow}>{modeOptions.map(option => <Pressable key={option.value} onPress={() => changeMode(option.value)} style={[catalogStyles.modeChip, mode === option.value && catalogStyles.modeChipSelected]}><Ionicons name={option.icon} size={13} color={mode === option.value ? "#11150a" : C.muted} /><Text style={[catalogStyles.modeText, mode === option.value && catalogStyles.modeTextSelected]}>{option.label}</Text></Pressable>)}</ScrollView>
    {mode === "filter" ? <View><View style={catalogStyles.sectionHeader}><View><Text style={catalogStyles.sectionTitle}>Danh sách phim</Text><Text style={catalogStyles.sectionSubtitle}>Lọc theo loại, thể loại, quốc gia hoặc năm</Text></View><Pressable onPress={clearFilters}><Text style={catalogStyles.clearText}>Xóa lọc</Text></Pressable></View><Text style={catalogStyles.filterLabel}>Loại danh sách</Text><ChipRow items={kindOptions.map(item => ({ value: item.value, label: item.label }))} selected={kind} onSelect={value => setKind(value as Kind)} /><Text style={catalogStyles.filterLabel}>Thể loại</Text><ChipRow items={meta.categories.map(item => ({ value: item.slug, label: item.name }))} selected={category} onSelect={selectFilterCategory} allLabel="Tất cả" /><Text style={catalogStyles.filterLabel}>Quốc gia</Text><ChipRow items={meta.countries.map(item => ({ value: item.slug, label: item.name }))} selected={country} onSelect={selectFilterCountry} allLabel="Tất cả" /><Text style={catalogStyles.filterLabel}>Năm phát hành</Text><ChipRow items={meta.years.map(item => ({ value: String(item), label: String(item) }))} selected={year} onSelect={selectFilterYear} allLabel="Tất cả" /></View> : <Directory mode={mode} categories={meta.categories} countries={meta.countries} years={meta.years} selected={selectedDirectoryValue} onSelect={selectDirectoryValue} />}
    {metaLoading && <Text style={catalogStyles.metaLoading}>Đang cập nhật danh mục…</Text>}
    {(mode === "filter" || selectedDirectoryValue) && <View style={catalogStyles.listHeader}><Text style={catalogStyles.listTitle}>{selectedLabel ? `Phim theo ${mode === "categories" ? "thể loại" : mode === "countries" ? "quốc gia" : "năm"}: ${selectedLabel}` : kindOptions.find(item => item.value === kind)?.label}</Text><Text style={catalogStyles.listCaption}>{items.length ? `${items.length} phim đang hiển thị` : "Danh sách phim từ Cinemora"}</Text></View>}
  </View>;

  return <View style={[styles.screen, { overflow: "hidden" }]}><ScreenAtmosphere /><FlatList style={{ flex: 1, backgroundColor: "transparent" }} contentContainerStyle={catalogStyles.content} data={items} keyExtractor={item => String(item.id || item.slug)} renderItem={({ item }) => <View style={catalogStyles.item}><MovieCard movie={item} wide /></View>} numColumns={2} columnWrapperStyle={catalogStyles.row} ListHeaderComponent={listHeader} ListEmptyComponent={(mode !== "filter" && !selectedDirectoryValue) ? <Text style={catalogStyles.stateText}>Chọn một danh mục để xem phim.</Text> : loading ? <View style={catalogStyles.state}><ActivityIndicator color={C.accent} /><Text style={catalogStyles.stateText}>Đang tải phim…</Text></View> : error ? <View style={catalogStyles.state}><Ionicons name="cloud-offline-outline" size={28} color={C.muted} /><Text style={catalogStyles.stateText}>{error}</Text><Pressable onPress={() => void fetchFirstPage()} style={catalogStyles.retry}><Text style={catalogStyles.retryText}>Thử lại</Text></Pressable></View> : <Text style={catalogStyles.stateText}>Chưa có phim trong danh mục này.</Text>} ListFooterComponent={loadingMore ? <View style={catalogStyles.footerLoading}><ActivityIndicator color={C.accent} /><Text style={catalogStyles.stateText}>Đang tải thêm…</Text></View> : error && items.length > 0 ? <Text style={catalogStyles.loadError}>{error}</Text> : hasMore ? <Pressable onPress={() => void loadMore()} style={catalogStyles.moreButton}><Text style={catalogStyles.moreText}>Tải thêm phim</Text><Ionicons name="arrow-down" size={15} color={C.accent} /></Pressable> : items.length > 0 ? <Text style={catalogStyles.endNote}>Bạn đã đến cuối danh sách.</Text> : null} onEndReached={() => { if (hasMore && !loadingMoreRef.current) void loadMore(); }} onEndReachedThreshold={0.45} refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => void fetchFirstPage(true)} tintColor={C.accent} colors={[C.accent]} progressBackgroundColor={C.surface2} />} initialNumToRender={8} maxToRenderPerBatch={8} updateCellsBatchingPeriod={40} windowSize={5} removeClippedSubviews showsVerticalScrollIndicator={false} /></View>;
}

const catalogStyles = {
  content: { paddingHorizontal: 18, paddingBottom: 112 } as const,
  header: { minHeight: 55, flexDirection: "row" as const, alignItems: "center" as const, justifyContent: "space-between" as const, marginBottom: 15 },
  brand: { color: C.text, fontSize: 22, fontWeight: "900" as const, letterSpacing: 1.4 }, subtitle: { color: C.muted, fontSize: 10, marginTop: 4 },
  headerActions: { flexDirection: "row" as const, alignItems: "center" as const, gap: 8 }, searchButton: { width: 44, height: 40, borderRadius: 14, backgroundColor: C.surface, borderWidth: 1, borderColor: C.line, alignItems: "center" as const, justifyContent: "center" as const },
  modeRow: { gap: 8, paddingBottom: 20 }, modeChip: { minHeight: 36, paddingHorizontal: 12, borderRadius: 13, backgroundColor: C.surface2, borderWidth: 1, borderColor: C.line, flexDirection: "row" as const, alignItems: "center" as const, gap: 5 }, modeChipSelected: { backgroundColor: C.accent, borderColor: C.accent }, modeText: { color: C.muted, fontSize: 10, fontWeight: "800" as const }, modeTextSelected: { color: "#11150a", fontWeight: "900" as const },
  sectionHeader: { flexDirection: "row" as const, alignItems: "flex-end" as const, justifyContent: "space-between" as const, marginBottom: 14 }, sectionTitle: { color: C.text, fontSize: 21, fontWeight: "900" as const }, sectionSubtitle: { color: C.muted, fontSize: 10, marginTop: 4 }, clearText: { color: C.accent, fontSize: 10, fontWeight: "800" as const, paddingBottom: 3 },
  filterLabel: { color: C.muted, fontSize: 10, fontWeight: "800" as const, marginBottom: 7, marginTop: 4 }, chipRow: { gap: 7, paddingBottom: 12 }, chip: { minHeight: 32, paddingHorizontal: 11, borderRadius: 10, backgroundColor: C.surface2, borderWidth: 1, borderColor: C.line, alignItems: "center" as const, justifyContent: "center" as const }, chipSelected: { backgroundColor: "rgba(210,243,107,0.14)", borderColor: C.accent }, chipText: { color: C.muted, fontSize: 10, fontWeight: "700" as const }, chipTextSelected: { color: C.accent, fontWeight: "900" as const },
  directory: { paddingBottom: 8 }, directoryTitle: { color: C.text, fontSize: 21, fontWeight: "900" as const }, directorySubtitle: { color: C.muted, fontSize: 10, marginTop: 4, marginBottom: 15 }, directoryGrid: { flexDirection: "row" as const, flexWrap: "wrap" as const, gap: 9 }, directoryCard: { width: "47.5%" as const, minHeight: 56, paddingHorizontal: 12, paddingVertical: 10, borderRadius: 12, borderWidth: 1, borderColor: C.line, backgroundColor: C.surface, flexDirection: "row" as const, alignItems: "center" as const, justifyContent: "space-between" as const, gap: 6 }, directoryCardSelected: { borderColor: C.accent, backgroundColor: "rgba(210,243,107,0.1)" }, directoryCardText: { flex: 1, color: C.muted, fontSize: 11, fontWeight: "800" as const }, directoryCardTextSelected: { color: C.accent },
  metaLoading: { color: C.muted, fontSize: 9, marginBottom: 8 }, listHeader: { marginTop: 7, marginBottom: 13 }, listTitle: { color: C.text, fontSize: 20, fontWeight: "900" as const }, listCaption: { color: C.muted, fontSize: 10, marginTop: 4 }, item: { width: "47%" as const }, row: { gap: 12, marginBottom: 13 }, state: { alignItems: "center" as const, justifyContent: "center" as const, paddingVertical: 42, gap: 10 }, stateText: { color: C.muted, fontSize: 11, textAlign: "center" as const, paddingVertical: 20 }, retry: { paddingHorizontal: 14, paddingVertical: 9, borderRadius: 13, backgroundColor: C.accent, marginTop: 4 }, retryText: { color: "#11150a", fontSize: 11, fontWeight: "900" as const }, footerLoading: { paddingVertical: 18, alignItems: "center" as const, gap: 8 }, moreButton: { minHeight: 46, marginTop: 8, borderRadius: 14, backgroundColor: C.surface, borderWidth: 1, borderColor: C.line, flexDirection: "row" as const, alignItems: "center" as const, justifyContent: "center" as const, gap: 8 }, moreText: { color: C.text, fontSize: 12, fontWeight: "800" as const }, loadError: { color: C.danger, textAlign: "center" as const, fontSize: 11, marginVertical: 12 }, endNote: { color: C.muted, textAlign: "center" as const, fontSize: 10, marginTop: 19 },
};
