import { memo, useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  ActivityIndicator,
  FlatList,
  Pressable,
  RefreshControl,
  Text,
  View,
  StyleSheet,
} from "react-native";
import { Image } from "expo-image";
import { Ionicons } from "@expo/vector-icons";
import { router } from "expo-router";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { api, imageUrl, Movie } from "@/api";
import { C, GlassMenu, MovieCard, ScreenAtmosphere, styles, useAutoHideTabBar } from "@/ui";

type HomeResult = Awaited<ReturnType<typeof api.home>>;

function hasNextPage(result: HomeResult, page: number) {
  const pagination = result.pagination as Record<string, unknown> | undefined;
  if (!pagination) return (result.items || []).length >= 12;
  const totalPages = Number(pagination.totalPages ?? pagination.total_pages ?? pagination.pageCount ?? pagination.page_count ?? pagination.total_page);
  if (Number.isFinite(totalPages) && totalPages > 0) return page < totalPages;
  const currentPage = Number(pagination.currentPage ?? pagination.current_page ?? pagination.page);
  const hasNext = pagination.hasNextPage ?? pagination.has_next_page ?? pagination.has_next;
  if (typeof hasNext === "boolean") return hasNext;
  const totalItems = Number(pagination.totalItems ?? pagination.total_items ?? pagination.total);
  const perPage = Number(pagination.itemsPerPage ?? pagination.items_per_page ?? pagination.limit);
  if (Number.isFinite(currentPage) && Number.isFinite(totalItems) && Number.isFinite(perPage) && perPage > 0) return currentPage * perPage < totalItems;
  return (result.items || []).length >= 12;
}

function dedupeMovies(movies: Movie[]) {
  const seen = new Set<string>();
  return movies.filter(movie => {
    const key = String(movie.id || movie.slug || movie.name);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

const FeatureCard = memo(function FeatureCard({ movie }: { movie: Movie }) {
  const uri = imageUrl(movie.backdrop || movie.poster || movie.thumb || movie.thumb_url || movie.poster_url);
  return <Pressable accessibilityRole="button" accessibilityLabel={`Xem ${movie.name}`} onPress={() => router.push(`/movie/${movie.slug}`)} style={({ pressed }) => [homeStyles.feature, pressed && homeStyles.pressed]}>
    {uri ? <Image source={{ uri }} contentFit="cover" cachePolicy="memory-disk" transition={180} recyclingKey={uri} style={homeStyles.featureBackdrop} /> : <View style={homeStyles.featureBackdrop} />}
    <View style={homeStyles.featureWash} />
    <View style={homeStyles.featureContent}>
      <View style={homeStyles.featureLabel}><Ionicons name="sparkles" size={12} color={C.accent} /><Text style={homeStyles.featureLabelText}>ĐỀ XUẤT HÔM NAY</Text></View>
      <Text style={homeStyles.featureTitle} numberOfLines={2}>{movie.name}</Text>
      <Text style={homeStyles.featureOrigin} numberOfLines={1}>{movie.originName || "Một lựa chọn dành riêng cho bạn"}</Text>
      <View style={homeStyles.featureMeta}>{!!movie.year && <Text style={homeStyles.metaText}>{movie.year}</Text>}{!!movie.categories?.[0]?.name && <><View style={homeStyles.metaDot} /><Text style={homeStyles.metaText}>{movie.categories[0].name}</Text></>}</View>
      <View style={homeStyles.watchButton}><Ionicons name="play" size={14} color="#11150a" /><Text style={homeStyles.watchButtonText}>Xem ngay</Text><Ionicons name="arrow-forward" size={14} color="#11150a" /></View>
    </View>
    {!!movie.quality && <View style={homeStyles.featureQuality}><Text style={homeStyles.featureQualityText}>{movie.quality}</Text></View>}
  </Pressable>;
});

function Header({ topInset }: { topInset: number }) {
  return <View style={{ paddingTop: topInset + 7 }}>
    <View style={homeStyles.header}>
      <View style={homeStyles.brandRow}>
        <Text style={homeStyles.brand}>CINEMORA</Text>
        <View style={homeStyles.brandDivider} />
        <Text style={homeStyles.brandCaption}>PHIM HAY MỖI NGÀY</Text>
      </View>
      <View style={homeStyles.headerActions}><Pressable accessibilityLabel="Tìm phim" onPress={() => router.push("/search")} style={homeStyles.searchButton}><Ionicons name="search" size={19} color={C.text} /></Pressable><GlassMenu /></View>
    </View>
    <View style={homeStyles.quickLinks}>
      <Pressable onPress={() => router.push("/catalog")} style={[homeStyles.quickChip, homeStyles.quickChipActive]}><Ionicons name="sparkles" size={13} color="#11150a" /><Text style={homeStyles.quickChipActiveText}>Dành cho bạn</Text></Pressable>
      <Pressable onPress={() => router.push({ pathname: "/catalog", params: { kind: "latest" } })} style={homeStyles.quickChip}><Text style={homeStyles.quickChipText}>Mới nhất</Text></Pressable>
      <Pressable onPress={() => router.push({ pathname: "/catalog", params: { kind: "single" } })} style={homeStyles.quickChip}><Text style={homeStyles.quickChipText}>Phim lẻ</Text></Pressable>
      <Pressable onPress={() => router.push({ pathname: "/catalog", params: { kind: "series" } })} style={homeStyles.quickChip}><Text style={homeStyles.quickChipText}>Phim bộ</Text></Pressable>
    </View>
  </View>;
}

export default function Home() {
  const insets = useSafeAreaInsets();
  const onScroll = useAutoHideTabBar();
  const [items, setItems] = useState<Movie[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState("");
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(false);
  const loadingMoreRef = useRef(false);

  const loadFirstPage = useCallback(async (refresh = false) => {
    if (refresh) setRefreshing(true);
    else setLoading(true);
    setError("");
    try {
      const result = await api.home(1);
      setItems(dedupeMovies(result.items || []));
      setPage(1);
      setHasMore(hasNextPage(result, 1));
    } catch {
      setError("Không thể tải phim lúc này. Hãy thử lại sau ít phút.");
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => { void loadFirstPage(); }, [loadFirstPage]);

  const loadMore = useCallback(async () => {
    if (loadingMoreRef.current || !hasMore) return;
    loadingMoreRef.current = true;
    setLoadingMore(true);
    setError("");
    const nextPage = page + 1;
    try {
      const result = await api.home(nextPage);
      const nextItems = result.items || [];
      setItems(current => dedupeMovies([...current, ...nextItems]));
      setPage(nextPage);
      setHasMore(nextItems.length > 0 && hasNextPage(result, nextPage));
    } catch {
      setError("Không tải được trang phim kế tiếp. Kéo xuống để thử lại.");
    } finally {
      loadingMoreRef.current = false;
      setLoadingMore(false);
    }
  }, [hasMore, page]);

  const featured = items[0];
  const movies = useMemo(() => featured ? items.slice(1) : items, [featured, items]);
  const renderItem = useCallback(({ item }: { item: Movie }) => <View style={homeStyles.gridItem}><MovieCard movie={item} wide /></View>, []);
  const header = useMemo(() => <>
    <Header topInset={insets.top} />
    {featured && <FeatureCard movie={featured} />}
    <View style={homeStyles.sectionHead}>
      <View><Text style={homeStyles.sectionKicker}>MỚI CẬP NHẬT</Text><Text style={homeStyles.sectionTitle}>Phim mới nhất</Text></View>
      <Pressable onPress={() => router.push("/catalog")} style={homeStyles.sectionAction}><Text style={homeStyles.sectionCount}>Xem tất cả</Text><Ionicons name="chevron-forward" size={12} color={C.accent} /></Pressable>
    </View>
  </>, [featured, hasMore, insets.top, items.length]);

  if (loading && items.length === 0) return <View style={[styles.screen, homeStyles.center, { overflow: "hidden" }]}><ScreenAtmosphere /><ActivityIndicator color={C.accent} size="large" /><Text style={homeStyles.loadingText}>Đang tải phim hay…</Text></View>;

  return <View style={[styles.screen, { overflow: "hidden" }]}><ScreenAtmosphere /><FlatList
    style={{ flex: 1, backgroundColor: "transparent" }}
    contentContainerStyle={homeStyles.listContent}
    data={movies}
    keyExtractor={movie => String(movie.id || movie.slug)}
    numColumns={2}
    renderItem={renderItem}
    columnWrapperStyle={homeStyles.row}
    ListHeaderComponent={header}
    ListEmptyComponent={error ? <View style={homeStyles.empty}><Ionicons name="cloud-offline-outline" size={28} color={C.muted} /><Text style={styles.error}>{error}</Text><Pressable onPress={() => void loadFirstPage()} style={homeStyles.retry}><Text style={homeStyles.retryText}>Thử lại</Text></Pressable></View> : <Text style={homeStyles.emptyHint}>Phim nổi bật hôm nay đã sẵn sàng để bạn thưởng thức.</Text>}
    ListFooterComponent={loadingMore ? <View style={homeStyles.footerLoading}><ActivityIndicator color={C.accent} /><Text style={homeStyles.loadingText}>Đang tải thêm phim…</Text></View> : error && items.length > 0 ? <Text style={homeStyles.loadError}>{error}</Text> : hasMore ? <Pressable onPress={() => void loadMore()} style={homeStyles.moreButton}><Text style={homeStyles.moreText}>Tải thêm phim</Text><Ionicons name="arrow-down" size={15} color={C.accent} /></Pressable> : <Text style={homeStyles.endNote}>Bạn đã xem hết danh sách hiện có.</Text>}
    onEndReached={() => { if (hasMore && !loadingMoreRef.current) void loadMore(); }}
    onEndReachedThreshold={0.45}
    onScroll={onScroll}
    scrollEventThrottle={16}
    refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => void loadFirstPage(true)} tintColor={C.accent} colors={[C.accent]} progressBackgroundColor={C.surface2} />}
    initialNumToRender={6}
    maxToRenderPerBatch={6}
    updateCellsBatchingPeriod={35}
    windowSize={5}
    removeClippedSubviews
    showsVerticalScrollIndicator={false}
  /></View>;
}

const homeStyles = {
  listContent: { paddingHorizontal: 18, paddingBottom: 112 } as const,
  header: { minHeight: 48, flexDirection: "row" as const, alignItems: "center" as const, justifyContent: "space-between" as const, marginBottom: 16 },
  brandRow: { flexDirection: "row" as const, alignItems: "center" as const, gap: 7, flexShrink: 1 },
  brand: { color: C.text, fontSize: 22, fontWeight: "900" as const, letterSpacing: 2.1 },
  brandDivider: { height: 18, width: 1, backgroundColor: C.line, marginHorizontal: 3 },
  brandCaption: { color: C.muted, fontSize: 9, fontWeight: "700" as const, letterSpacing: 0.6, flexShrink: 1 },
  headerActions: { flexDirection: "row" as const, alignItems: "center" as const, gap: 8 },
  searchButton: { width: 44, height: 40, borderRadius: 14, backgroundColor: C.surface, borderWidth: 1, borderColor: C.line, alignItems: "center" as const, justifyContent: "center" as const, marginLeft: 10 },
  quickLinks: { flexDirection: "row" as const, flexWrap: "wrap" as const, gap: 8, marginBottom: 25 },
  quickChip: { minHeight: 40, flexDirection: "row" as const, alignItems: "center" as const, paddingHorizontal: 14, borderRadius: 20, backgroundColor: C.surface2, borderWidth: 1, borderColor: "rgba(255,255,255,0.07)" },
  quickChipActive: { backgroundColor: C.accent, borderColor: C.accent, gap: 5 },
  quickChipText: { color: C.muted, fontSize: 10, fontWeight: "700" as const },
  quickChipActiveText: { color: "#11150a", fontSize: 10, fontWeight: "900" as const },
  sectionHead: { flexDirection: "row" as const, alignItems: "flex-end" as const, justifyContent: "space-between" as const, marginBottom: 13 },
  sectionKicker: { color: C.accent, fontSize: 9, fontWeight: "900" as const, letterSpacing: 2.1 },
  sectionTitle: { color: C.text, fontSize: 23, fontWeight: "900" as const, marginTop: 3, letterSpacing: -0.6 },
  sectionAction: { flexDirection: "row" as const, alignItems: "center" as const, gap: 3, paddingBottom: 3 },
  sectionCount: { color: C.accent, fontSize: 10, fontWeight: "800" as const },
  feature: { height: 288, marginBottom: 34, borderRadius: 30, overflow: "hidden" as const, backgroundColor: C.surface, borderWidth: 1, borderColor: "rgba(225,232,255,0.28)", shadowColor: "#8299ef", shadowOpacity: 0.15, shadowRadius: 24, shadowOffset: { width: 0, height: 10 }, elevation: 7 },
  featureBackdrop: { ...StyleSheet.absoluteFillObject, width: "100%" as const, height: "100%" as const },
  featureWash: { ...StyleSheet.absoluteFillObject, backgroundColor: "rgba(7,9,13,0.48)" },
  featureContent: { flex: 1, justifyContent: "flex-end" as const, alignItems: "flex-start" as const, padding: 22 },
  posterFallback: { alignItems: "center" as const, justifyContent: "center" as const },
  featureQuality: { position: "absolute" as const, left: 6, top: 6, borderRadius: 6, backgroundColor: "rgba(12,15,23,0.78)", borderWidth: 1, borderColor: "rgba(255,255,255,0.18)", paddingHorizontal: 6, paddingVertical: 4 },
  featureQualityText: { color: C.accent, fontSize: 8, fontWeight: "900" as const },
  featureInfo: { flex: 1, justifyContent: "center" as const, alignItems: "flex-start" as const, paddingVertical: 4 },
  featureLabel: { flexDirection: "row" as const, alignItems: "center" as const, gap: 5, marginBottom: 8 },
  featureLabelText: { color: C.accent, fontSize: 8, fontWeight: "900" as const, letterSpacing: 1.5 },
  featureTitle: { color: C.text, fontSize: 18, lineHeight: 22, fontWeight: "900" as const, letterSpacing: -0.2 },
  featureOrigin: { color: C.muted, fontSize: 11, marginTop: 6 },
  featureMeta: { flexDirection: "row" as const, alignItems: "center" as const, gap: 7, marginTop: 7 },
  metaText: { color: C.muted, fontSize: 9, fontWeight: "700" as const, maxWidth: 100 },
  metaDot: { width: 3, height: 3, borderRadius: 2, backgroundColor: C.accent },
  watchButton: { minHeight: 44, flexDirection: "row" as const, alignItems: "center" as const, gap: 6, backgroundColor: C.accent, borderRadius: 22, paddingHorizontal: 17, marginTop: 14 },
  watchButtonText: { color: "#11150a", fontSize: 11, fontWeight: "900" as const },
  listHeading: { marginBottom: 12 },
  listHeadingText: { color: C.text, fontSize: 17, fontWeight: "900" as const, letterSpacing: -0.2 },
  listHeadingSub: { color: C.muted, fontSize: 10, marginTop: 4 },
  row: { gap: 14, marginBottom: 23 },
  gridItem: { width: "47.5%" as const },
  pressed: { opacity: 0.86, transform: [{ scale: 0.99 }] },
  center: { alignItems: "center" as const, justifyContent: "center" as const, gap: 12 },
  loadingText: { color: C.muted, fontSize: 11, textAlign: "center" as const },
  footerLoading: { paddingVertical: 18, alignItems: "center" as const, gap: 8 },
  moreButton: { minHeight: 46, marginTop: 10, borderRadius: 14, borderWidth: 1, borderColor: C.line, backgroundColor: C.surface, flexDirection: "row" as const, alignItems: "center" as const, justifyContent: "center" as const, gap: 8 },
  moreText: { color: C.text, fontSize: 12, fontWeight: "800" as const },
  empty: { alignItems: "center" as const, paddingVertical: 45 },
  emptyHint: { color: C.muted, fontSize: 12, textAlign: "center" as const, paddingVertical: 20 },
  retry: { paddingHorizontal: 15, paddingVertical: 9, backgroundColor: C.accent, borderRadius: 13, marginTop: 4 },
  retryText: { color: "#11150a", fontSize: 11, fontWeight: "900" as const },
  loadError: { color: C.danger, fontSize: 11, textAlign: "center" as const, marginVertical: 12 },
  endNote: { color: C.muted, fontSize: 10, textAlign: "center" as const, marginTop: 18 },
};
