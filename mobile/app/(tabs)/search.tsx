import { useCallback, useState } from "react";
import { ActivityIndicator, Keyboard, Pressable, RefreshControl, ScrollView, Text, TextInput, View } from "react-native";
import { Ionicons } from "@expo/vector-icons";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { router } from "expo-router";
import { api, Movie } from "@/api";
import { C, GlassContainer, GlassMenu, MovieCard, ScreenAtmosphere, styles, useAutoHideTabBar } from "@/ui";

export default function Search() {
  const insets = useSafeAreaInsets();
  const onScroll = useAutoHideTabBar();
  const [keyword, setKeyword] = useState("");
  const [submittedKeyword, setSubmittedKeyword] = useState("");
  const [items, setItems] = useState<Movie[]>([]);
  const [loading, setLoading] = useState(false);
  const [searched, setSearched] = useState(false);

  const submit = useCallback(async () => {
    const value = keyword.trim();
    if (value.length < 2) return;
    Keyboard.dismiss();
    setSubmittedKeyword(value);
    setSearched(true);
    setLoading(true);
    try {
      setItems((await api.search(value)).items || []);
    } catch {
      setItems([]);
    } finally {
      setLoading(false);
    }
  }, [keyword]);

  const clear = useCallback(() => {
    setKeyword("");
    setSubmittedKeyword("");
    setItems([]);
    setSearched(false);
  }, []);

  return <View style={[styles.screen, { overflow: "hidden" }]}><ScreenAtmosphere /><ScrollView
    style={{ flex: 1, backgroundColor: "transparent" }}
    contentContainerStyle={[searchStyles.content, { paddingTop: insets.top + 10 }]}
    keyboardShouldPersistTaps="handled"
    showsVerticalScrollIndicator={false}
    onScroll={onScroll}
    scrollEventThrottle={16}
    refreshControl={<RefreshControl refreshing={false} onRefresh={() => searched && void submit()} tintColor={C.accent} colors={[C.accent]} progressBackgroundColor={C.surface2} />}
  >
    <View style={searchStyles.header}>
      <View><Text style={searchStyles.kicker}>CINEMORA</Text><Text style={searchStyles.title}>TÌM KIẾM</Text><Text style={searchStyles.subtitle}>Tìm phim theo tên tiếng Việt hoặc tên gốc</Text></View>
      <View style={searchStyles.headerActions}><Ionicons name="search" size={24} color={C.accent} /><GlassMenu /></View>
    </View>

    <GlassContainer style={searchStyles.searchBox}>
      <Ionicons name="search-outline" size={19} color={C.muted} />
      <TextInput value={keyword} onChangeText={setKeyword} onSubmitEditing={() => void submit()} returnKeyType="search" placeholder="Tên phim, tên gốc..." placeholderTextColor={C.muted} style={searchStyles.input} autoCapitalize="none" autoCorrect={false} />
      {!!keyword && <Pressable onPress={clear} accessibilityLabel="Xóa từ khóa" style={searchStyles.clearButton}><Ionicons name="close-circle" size={18} color={C.muted} /></Pressable>}
    </GlassContainer>
    <Pressable onPress={() => void submit()} disabled={loading || keyword.trim().length < 2} style={({ pressed }) => [searchStyles.submitButton, (loading || keyword.trim().length < 2) && searchStyles.submitDisabled, pressed && searchStyles.pressed]}>
      {loading ? <ActivityIndicator color="#11150a" size="small" /> : <Ionicons name="search" size={18} color="#11150a" />}
      <Text style={searchStyles.submitText}>Tìm phim</Text>
    </Pressable>

    <View style={searchStyles.resultHeader}><View><Text style={searchStyles.resultKicker}>KẾT QUẢ TÌM KIẾM</Text><Text style={searchStyles.resultTitle}>{submittedKeyword ? `“${submittedKeyword}”` : "Bạn đang tìm gì?"}</Text></View>{searched && !loading && <Text style={searchStyles.resultCount}>{items.length} phim</Text>}</View>

    {loading ? <View style={searchStyles.state}><ActivityIndicator color={C.accent} size="large" /><Text style={searchStyles.stateText}>Đang tìm phim…</Text></View>
      : !searched ? <GlassContainer style={searchStyles.emptyCard}><Ionicons name="film-outline" size={28} color={C.accent} /><Text style={searchStyles.emptyTitle}>Bắt đầu khám phá</Text><Text style={searchStyles.emptyText}>Nhập ít nhất 2 ký tự để tìm kiếm phim yêu thích.</Text></GlassContainer>
      : items.length === 0 ? <GlassContainer style={searchStyles.emptyCard}><Ionicons name="search-outline" size={28} color={C.muted} /><Text style={searchStyles.emptyTitle}>Không tìm thấy phim</Text><Text style={searchStyles.emptyText}>Thử từ khóa khác hoặc kiểm tra lại chính tả.</Text></GlassContainer>
      : <View style={searchStyles.grid}>{items.map(movie => <View key={String(movie.id || movie.slug)} style={searchStyles.gridItem}><MovieCard movie={movie} wide onPress={() => router.push(`/movie/${movie.slug}`)} /></View>)}</View>}
  </ScrollView></View>;
}

const searchStyles = {
  content: { paddingHorizontal: 20, paddingBottom: 118 } as const,
  headerActions: { flexDirection: "row" as const, alignItems: "center" as const, gap: 8 },
  header: { minHeight: 75, flexDirection: "row" as const, alignItems: "center" as const, justifyContent: "space-between" as const, marginBottom: 18 },
  kicker: { color: C.muted, fontSize: 9, fontWeight: "900" as const, letterSpacing: 2.4 },
  title: { color: C.text, fontSize: 31, lineHeight: 34, fontWeight: "900" as const, letterSpacing: 1.1 },
  subtitle: { color: C.muted, fontSize: 10, marginTop: 5 },
  searchBox: { minHeight: 62, flexDirection: "row" as const, alignItems: "center" as const, gap: 10, paddingHorizontal: 16, borderRadius: 20, backgroundColor: "rgba(255,255,255,0.055)", borderWidth: 1, borderColor: "rgba(225,232,255,0.16)" },
  input: { flex: 1, color: C.text, fontSize: 16, fontWeight: "600" as const, paddingVertical: 0 },
  clearButton: { padding: 3 },
  submitButton: { minHeight: 48, alignSelf: "flex-start" as const, flexDirection: "row" as const, alignItems: "center" as const, gap: 8, marginTop: 14, paddingHorizontal: 22, borderRadius: 25, backgroundColor: C.accent },
  submitDisabled: { opacity: 0.55 },
  submitText: { color: "#11150a", fontSize: 14, fontWeight: "900" as const },
  pressed: { opacity: 0.82, transform: [{ scale: 0.98 }] },
  resultHeader: { flexDirection: "row" as const, alignItems: "flex-end" as const, justifyContent: "space-between" as const, marginTop: 42, marginBottom: 17 },
  resultKicker: { color: C.accent, fontSize: 10, fontWeight: "900" as const, letterSpacing: 2.1 },
  resultTitle: { color: C.text, fontSize: 25, lineHeight: 30, fontWeight: "900" as const, marginTop: 5 },
  resultCount: { color: C.muted, fontSize: 10, paddingBottom: 3 },
  grid: { flexDirection: "row" as const, flexWrap: "wrap" as const, justifyContent: "space-between" as const, rowGap: 20 },
  gridItem: { width: "47.5%" as const },
  state: { minHeight: 180, alignItems: "center" as const, justifyContent: "center" as const, gap: 10 },
  stateText: { color: C.muted, fontSize: 11 },
  emptyCard: { minHeight: 210, alignItems: "center" as const, justifyContent: "center" as const, paddingHorizontal: 28, borderRadius: 22, borderWidth: 1, borderColor: "rgba(225,232,255,0.15)", backgroundColor: "rgba(255,255,255,0.045)", gap: 8 },
  emptyTitle: { color: C.text, fontSize: 15, fontWeight: "900" as const },
  emptyText: { color: C.muted, fontSize: 11, lineHeight: 17, textAlign: "center" as const },
};
