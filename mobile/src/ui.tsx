import { memo, useCallback, useEffect, useRef, useState } from "react";
import { BlurView } from "expo-blur";
import { Image } from "expo-image";
import { router, useNavigation } from "expo-router";
import { Ionicons } from "@expo/vector-icons";
import {
  Modal,
  Pressable,
  StyleSheet,
  Text,
  View,
  type PressableStateCallbackType,
  type NativeScrollEvent,
  type NativeSyntheticEvent,
  type StyleProp,
  type ViewStyle,
} from "react-native";
import { imageUrl, Movie } from "./api";
import { blur, C, colors, radius, spacing, typography } from "./design";
export { C } from "./design";

export const TAB_BAR_VISIBLE = {
  position: "absolute" as const,
  left: 12,
  right: 12,
  bottom: 12,
  height: 72,
  paddingTop: 9,
  paddingBottom: 9,
  borderRadius: radius.xl,
  overflow: "hidden" as const,
  elevation: 0,
  borderWidth: 1,
  borderColor: colors.borderStrong,
};

export function ScreenAtmosphere() {
  return <View pointerEvents="none" style={StyleSheet.absoluteFill}>
    <View style={glassStyles.ambientTop} />
    <View style={glassStyles.ambientBottom} />
    <View style={glassStyles.ambientHairline} />
  </View>;
}

export function GlassContainer({ children, style, intensity = blur.glass }: { children: React.ReactNode; style?: StyleProp<ViewStyle>; intensity?: number }) {
  return <View style={[glassStyles.container, style]}>
    <BlurView pointerEvents="none" intensity={intensity} tint="dark" style={StyleSheet.absoluteFill}>
      <View style={glassStyles.tint} />
    </BlurView>
    <View pointerEvents="none" style={glassStyles.specular} />
    {children}
  </View>;
}

export function GlassCard({ children, style }: { children: React.ReactNode; style?: StyleProp<ViewStyle> }) {
  return <GlassContainer style={[glassStyles.card, style]}>{children}</GlassContainer>;
}

export function GlassButton({ children, onPress, style, disabled = false }: { children: React.ReactNode; onPress?: () => void; style?: StyleProp<ViewStyle>; disabled?: boolean }) {
  return <Pressable disabled={disabled} onPress={onPress} style={({ pressed }) => [glassStyles.button, style, disabled && glassStyles.disabled, pressed && glassStyles.pressed]}>
    <View pointerEvents="none" style={glassStyles.buttonHighlight} />
    {children}
  </Pressable>;
}

export function GlassIconButton({ icon, label, onPress }: { icon: keyof typeof Ionicons.glyphMap; label: string; onPress?: () => void }) {
  return <GlassButton onPress={onPress} style={glassStyles.iconButton}><Ionicons accessibilityLabel={label} name={icon} size={20} color={colors.text} /></GlassButton>;
}

export function GlassState({ icon, title, message, action, actionLabel }: { icon: keyof typeof Ionicons.glyphMap; title: string; message?: string; action?: () => void; actionLabel?: string }) {
  return <GlassCard style={glassStyles.state}>
    <View style={glassStyles.stateIcon}><Ionicons name={icon} size={25} color={colors.primary} /></View>
    <Text style={glassStyles.stateTitle}>{title}</Text>
    {message && <Text style={glassStyles.stateMessage}>{message}</Text>}
    {action && actionLabel && <GlassButton onPress={action} style={glassStyles.stateAction}><Text style={glassStyles.buttonText}>{actionLabel}</Text></GlassButton>}
  </GlassCard>;
}

export function useAutoHideTabBar() {
  const navigation = useNavigation();
  const lastOffset = useRef(0);
  const hidden = useRef(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const animateBar = useCallback((toHidden: boolean) => {
    if (timer.current) clearTimeout(timer.current);
    const start = toHidden ? 0 : 1;
    const end = toHidden ? 1 : 0;
    let step = 0;
    const tick = () => {
      const p = Math.min(1, ++step / 10);
      const eased = 1 - Math.pow(1 - p, 3);
      const value = start + (end - start) * eased;
      navigation.setOptions({ tabBarStyle: { ...TAB_BAR_VISIBLE, height: 72 - value * 50, paddingTop: 9 - value * 9, paddingBottom: 9 - value * 9, borderRadius: radius.xl - value * 12, opacity: 1 - value * 0.82, transform: [{ translateY: value * 36 }] } });
      if (p < 1) timer.current = setTimeout(tick, 16); else timer.current = null;
    };
    tick();
  }, [navigation]);
  useEffect(() => {
    lastOffset.current = 0;
    hidden.current = false;
    navigation.setOptions({ tabBarStyle: TAB_BAR_VISIBLE });
    return () => { if (timer.current) clearTimeout(timer.current); };
  }, [navigation]);
  return useCallback((event: NativeSyntheticEvent<NativeScrollEvent>) => {
    const offset = Math.max(0, event.nativeEvent.contentOffset.y);
    const delta = offset - lastOffset.current;
    if (delta > 12 && offset > 42 && !hidden.current) { hidden.current = true; animateBar(true); }
    else if (delta < -12 && hidden.current) { hidden.current = false; animateBar(false); }
    lastOffset.current = offset;
  }, [animateBar]);
}

export function GlassMenu() {
  const [open, setOpen] = useState(false);
  const items = [["Trang chủ", "home-outline", "/"], ["Thư viện", "grid-outline", "/catalog"], ["Tìm kiếm", "search-outline", "/search"], ["Tài khoản", "person-outline", "/account"]] as const;
  return <>
    <GlassIconButton icon="menu-outline" label="Mở menu" onPress={() => setOpen(true)} />
    <Modal visible={open} transparent animationType="fade" onRequestClose={() => setOpen(false)} statusBarTranslucent>
      <Pressable style={menuStyles.backdrop} onPress={() => setOpen(false)}>
        <View style={menuStyles.bottomScrim} />
        <Pressable style={menuStyles.sheet} onPress={event => event.stopPropagation()}>
          <BlurView pointerEvents="none" intensity={44} tint="dark" style={StyleSheet.absoluteFill} />
          <View style={menuStyles.grabber} />
          <Text style={menuStyles.kicker}>CINEMORA · KHÔNG GIAN GIẢI TRÍ</Text>
          <Text style={menuStyles.title}>Khám phá</Text>
          {items.map(([label, icon, path]) => <Pressable key={label} onPress={() => { setOpen(false); router.push(path); }} style={({ pressed }) => [menuStyles.item, pressed && menuStyles.itemPressed]}>
            <View style={menuStyles.itemIcon}><Ionicons name={icon} size={19} color={colors.primary} /></View>
            <Text style={menuStyles.itemText}>{label}</Text>
            <Ionicons name="chevron-forward" size={17} color={colors.textMuted} />
          </Pressable>)}
        </Pressable>
      </Pressable>
    </Modal>
  </>;
}

export const Poster = memo(function Poster({ movie, large = false }: { movie: Movie; large?: boolean }) {
  const src = imageUrl(movie.poster || movie.thumb || movie.thumb_url || movie.poster_url);
  return src
    ? <Image source={{ uri: src }} cachePolicy="memory-disk" contentFit="cover" transition={160} recyclingKey={src} style={[styles.poster, large && styles.posterLarge]} />
    : <View style={[styles.poster, large && styles.posterLarge, styles.posterFallback]}><Text style={styles.logoMark}>C</Text></View>;
});

export const MovieCard = memo(function MovieCard({ movie, onPress, wide = false }: { movie: Movie; onPress?: () => void; wide?: boolean }) {
  const handlePress = useCallback(() => onPress ? onPress() : router.push(`/movie/${movie.slug}`), [movie.slug, onPress]);
  return <Pressable accessibilityRole="button" accessibilityLabel={`Mở phim ${movie.name}`} onPress={handlePress} style={({ pressed }: PressableStateCallbackType) => [styles.card, wide && styles.cardWide, pressed && styles.cardPressed]}>
    <View style={styles.posterWrap}>
      <Poster movie={movie} />
      {!!movie.quality && <View style={styles.quality}><Text style={styles.qualityText}>{movie.quality}</Text></View>}
      <View pointerEvents="none" style={styles.posterGloss} />
    </View>
    <Text style={styles.cardTitle} numberOfLines={2}>{movie.name}</Text>
    <Text style={styles.cardMeta} numberOfLines={1}>{[movie.originName, movie.year].filter(Boolean).join(" · ") || "Cinemora"}</Text>
  </Pressable>;
});

export function SectionTitle({ eyebrow, title, action, onAction }: { eyebrow?: string; title: string; action?: string; onAction?: () => void }) {
  return <View style={styles.sectionHead}>
    <View>{!!eyebrow && <Text style={styles.eyebrow}>{eyebrow}</Text>}<Text style={styles.sectionTitle}>{title}</Text></View>
    {!!action && <Pressable accessibilityRole="button" onPress={onAction}><Text style={styles.action}>{action} ›</Text></Pressable>}
  </View>;
}

const glassStyles = StyleSheet.create({
  container: { overflow: "hidden", borderRadius: radius.lg, borderWidth: 1, borderColor: colors.border, backgroundColor: colors.glass },
  tint: { ...StyleSheet.absoluteFillObject, backgroundColor: "rgba(20, 25, 36, 0.22)" },
  specular: { position: "absolute", top: 0, left: 14, right: 14, height: 1, backgroundColor: "rgba(255,255,255,0.34)" },
  card: { padding: spacing.lg, shadowColor: "#000", shadowOpacity: 0.24, shadowRadius: 18, shadowOffset: { width: 0, height: 8 }, elevation: 5 },
  button: { minHeight: 48, overflow: "hidden", borderRadius: radius.pill, paddingHorizontal: spacing.xl, justifyContent: "center", alignItems: "center", backgroundColor: colors.primary },
  buttonHighlight: { position: "absolute", left: 14, right: 14, top: 1, height: 1, backgroundColor: "rgba(255,255,255,0.42)" },
  iconButton: { width: 44, height: 44, minHeight: 44, paddingHorizontal: 0, borderRadius: radius.md, backgroundColor: "rgba(255,255,255,0.09)", borderColor: colors.borderStrong },
  buttonText: { color: colors.onPrimary, ...typography.label },
  pressed: { transform: [{ scale: 0.97 }], opacity: 0.86 },
  disabled: { opacity: 0.45 },
  state: { alignItems: "center", justifyContent: "center", padding: spacing.xxl, gap: spacing.sm, minHeight: 190 },
  stateIcon: { width: 54, height: 54, borderRadius: 20, alignItems: "center", justifyContent: "center", backgroundColor: "rgba(197,210,255,0.1)", borderWidth: 1, borderColor: colors.border },
  stateTitle: { color: colors.text, ...typography.section, textAlign: "center" },
  stateMessage: { color: colors.textSecondary, ...typography.body, textAlign: "center" },
  stateAction: { marginTop: spacing.sm },
  ambientTop: { position: "absolute", top: -180, right: -110, width: 340, height: 340, borderRadius: 170, backgroundColor: "rgba(111,140,239,0.09)" },
  ambientBottom: { position: "absolute", top: 380, left: -230, width: 390, height: 390, borderRadius: 195, backgroundColor: "rgba(91,123,218,0.045)" },
  ambientHairline: { position: "absolute", top: 0, left: 0, right: 0, height: 1, backgroundColor: "rgba(255,255,255,0.045)" },
});

const menuStyles = StyleSheet.create({
  backdrop: { flex: 1, justifyContent: "flex-end", backgroundColor: "rgba(2,4,9,0.38)" },
  bottomScrim: { ...StyleSheet.absoluteFillObject, backgroundColor: colors.scrim },
  sheet: { overflow: "hidden", padding: spacing.xl, paddingBottom: 38, borderTopLeftRadius: 32, borderTopRightRadius: 32, backgroundColor: "rgba(20,25,37,0.92)", borderTopWidth: 1, borderColor: colors.borderStrong },
  grabber: { width: 38, height: 4, borderRadius: 3, backgroundColor: colors.glassHighlight, alignSelf: "center", marginBottom: spacing.xl },
  kicker: { color: colors.textMuted, ...typography.caption, letterSpacing: 1.7 },
  title: { color: colors.text, ...typography.display, marginTop: 4, marginBottom: spacing.lg },
  item: { minHeight: 61, flexDirection: "row", alignItems: "center", gap: spacing.md, paddingHorizontal: spacing.sm, borderTopWidth: StyleSheet.hairlineWidth, borderColor: "rgba(255,255,255,0.08)" },
  itemPressed: { backgroundColor: "rgba(255,255,255,0.07)" },
  itemIcon: { width: 42, height: 42, borderRadius: radius.md, alignItems: "center", justifyContent: "center", backgroundColor: "rgba(197,210,255,0.12)", borderWidth: 1, borderColor: "rgba(197,210,255,0.14)" },
  itemText: { flex: 1, color: colors.text, ...typography.body, fontWeight: "700" },
});

const styles = StyleSheet.create({
  poster: { width: "100%", aspectRatio: 0.68, borderRadius: radius.md, backgroundColor: colors.surfaceSoft },
  posterLarge: { width: 132, height: 198, aspectRatio: undefined },
  posterFallback: { alignItems: "center", justifyContent: "center" },
  logoMark: { color: colors.primary, fontSize: 30, fontWeight: "900" },
  card: { width: "31.7%", marginBottom: spacing.md },
  cardWide: { width: "100%" },
  cardPressed: { opacity: 0.9, transform: [{ scale: 0.985 }] },
  posterWrap: { position: "relative", overflow: "hidden", borderRadius: radius.md, backgroundColor: colors.surfaceSoft, borderWidth: 1, borderColor: colors.border, shadowColor: "#000", shadowOpacity: 0.28, shadowRadius: 12, shadowOffset: { width: 0, height: 7 }, elevation: 4 },
  posterGloss: { position: "absolute", top: 0, left: 1, right: 1, height: 30, borderTopLeftRadius: radius.md, borderTopRightRadius: radius.md, backgroundColor: "rgba(255,255,255,0.045)" },
  quality: { position: "absolute", top: 7, left: 7, paddingHorizontal: 8, paddingVertical: 5, borderRadius: 9, backgroundColor: "rgba(8,10,16,0.78)", borderWidth: 1, borderColor: "rgba(255,255,255,0.14)" },
  qualityText: { color: colors.primary, ...typography.caption, fontWeight: "900" },
  cardTitle: { color: colors.text, ...typography.label, marginTop: spacing.sm, lineHeight: 19 },
  cardMeta: { color: colors.textMuted, ...typography.caption, marginTop: 3 },
  sectionHead: { flexDirection: "row", alignItems: "flex-end", justifyContent: "space-between", marginTop: spacing.xxxl, marginBottom: spacing.md },
  eyebrow: { color: colors.primary, ...typography.caption, letterSpacing: 1.5 },
  sectionTitle: { color: colors.text, ...typography.title, marginTop: 5 },
  action: { color: colors.primary, ...typography.label },
  safe: { flex: 1, backgroundColor: colors.background },
  screen: { flex: 1, backgroundColor: colors.background },
  content: { paddingHorizontal: spacing.xl, paddingTop: spacing.md, paddingBottom: 116 },
  header: { paddingHorizontal: spacing.xl, paddingTop: spacing.md, paddingBottom: spacing.md, flexDirection: "row", alignItems: "center", justifyContent: "space-between" },
  brand: { color: colors.primary, fontSize: 24, fontWeight: "900", letterSpacing: 2 },
  headerButton: { color: colors.textSecondary, fontSize: 14 },
  input: { backgroundColor: colors.surface, borderColor: colors.border, borderWidth: 1, borderRadius: radius.lg, color: colors.text, padding: 15, fontSize: 16, minHeight: 52 },
  pill: { backgroundColor: colors.primary, borderRadius: radius.pill, paddingVertical: 13, paddingHorizontal: 21, minHeight: 46 },
  pillText: { color: colors.onPrimary, fontWeight: "800" },
  muted: { color: colors.textSecondary, ...typography.body },
  divider: { height: 1, backgroundColor: colors.border, marginVertical: spacing.lg },
  error: { color: colors.error, textAlign: "center", padding: spacing.xxl },
});
export { styles };
