import { useEffect, useRef } from "react";
import { Animated, Pressable, StyleSheet, Text, View } from "react-native";
import { Tabs } from "expo-router";
import { Ionicons } from "@expo/vector-icons";
import { BlurView } from "expo-blur";
import { C, tabBarHideProgress } from "@/ui";

const tabIcons: Record<string, keyof typeof Ionicons.glyphMap> = {
  index: "home-outline",
  catalog: "grid-outline",
  search: "search-outline",
  account: "person-outline",
};

function LiquidGlassTabBar({ state, descriptors, navigation }: any) {
  const translateY = tabBarHideProgress.interpolate({ inputRange: [0, 1], outputRange: [0, 104] });
  const opacity = tabBarHideProgress.interpolate({ inputRange: [0, 0.8, 1], outputRange: [1, 0.16, 0] });
  const scale = tabBarHideProgress.interpolate({ inputRange: [0, 1], outputRange: [1, 0.94] });

  return <Animated.View pointerEvents="box-none" style={[tabStyles.positioner, { opacity, transform: [{ translateY }, { scale }] }]}>
    <View style={tabStyles.bar}>
      <BlurView pointerEvents="none" intensity={86} tint="dark" style={StyleSheet.absoluteFill}>
        <View style={tabStyles.glassWash} />
      </BlurView>
      <View pointerEvents="none" style={tabStyles.topSpecular} />
      <View style={tabStyles.items}>
        {state.routes.map((route: any, index: number) => {
          const focused = state.index === index;
          const { options } = descriptors[route.key];
          const label = options.title ?? route.name;
          const icon = tabIcons[route.name] ?? "ellipse-outline";
          return <GlassTabItem
            key={route.key}
            label={label}
            icon={icon}
            focused={focused}
            onPress={() => {
              const event = navigation.emit({ type: "tabPress", target: route.key, canPreventDefault: true });
              if (!focused && !event.defaultPrevented) navigation.navigate(route.name, route.params);
            }}
            onLongPress={() => navigation.emit({ type: "tabLongPress", target: route.key })}
          />;
        })}
      </View>
    </View>
  </Animated.View>;
}

function GlassTabItem({ label, icon, focused, onPress, onLongPress }: { label: string; icon: keyof typeof Ionicons.glyphMap; focused: boolean; onPress: () => void; onLongPress: () => void }) {
  const progress = useRef(new Animated.Value(focused ? 1 : 0)).current;
  useEffect(() => {
    Animated.spring(progress, { toValue: focused ? 1 : 0, damping: 17, stiffness: 210, mass: 0.7, useNativeDriver: true }).start();
  }, [focused, progress]);

  const capsuleOpacity = progress.interpolate({ inputRange: [0, 1], outputRange: [0, 1] });
  const capsuleScale = progress.interpolate({ inputRange: [0, 1], outputRange: [0.84, 1] });
  const iconScale = progress.interpolate({ inputRange: [0, 1], outputRange: [1, 1.12] });
  const iconY = progress.interpolate({ inputRange: [0, 1], outputRange: [1, -1] });

  return <Pressable
    accessibilityRole="tab"
    accessibilityState={{ selected: focused }}
    accessibilityLabel={label}
    onPress={onPress}
    onLongPress={onLongPress}
    style={({ pressed }) => [tabStyles.item, pressed && tabStyles.pressed]}
  >
    <Animated.View pointerEvents="none" style={[tabStyles.activeCapsule, { opacity: capsuleOpacity, transform: [{ scale: capsuleScale }] }]} />
    <Animated.View style={{ alignItems: "center", justifyContent: "center", transform: [{ scale: iconScale }, { translateY: iconY }] }}>
      <Ionicons name={icon} size={21} color={focused ? C.accent : "#aeb6c8"} />
    </Animated.View>
    <Text numberOfLines={1} style={[tabStyles.label, focused && tabStyles.activeLabel]}>{label}</Text>
    <Animated.View pointerEvents="none" style={[tabStyles.activeDot, { opacity: progress }]} />
  </Pressable>;
}

export default function TabsLayout() {
  return <Tabs
    tabBar={props => <LiquidGlassTabBar {...props} />}
    screenOptions={{
      headerShown: false,
      sceneStyle: { backgroundColor: C.bg },
    }}
  >
    <Tabs.Screen name="index" options={{ title: "Trang Chủ" }} />
    <Tabs.Screen name="catalog" options={{ title: "Thư Viện" }} />
    <Tabs.Screen name="search" options={{ title: "Tìm Kiếm" }} />
    <Tabs.Screen name="account" options={{ title: "Tài Khoản" }} />
  </Tabs>;
}

const tabStyles = StyleSheet.create({
  positioner: { position: "absolute", left: 13, right: 13, bottom: 14, height: 72, zIndex: 100 },
  bar: { flex: 1, overflow: "hidden", borderRadius: 26, borderWidth: 1, borderColor: "rgba(223,231,255,0.24)", backgroundColor: "rgba(17,22,34,0.68)", shadowColor: "#91a7ff", shadowOpacity: 0.16, shadowRadius: 24, shadowOffset: { width: 0, height: 8 }, elevation: 16 },
  glassWash: { ...StyleSheet.absoluteFillObject, backgroundColor: "rgba(18,24,38,0.52)" },
  topSpecular: { position: "absolute", top: 0, left: 26, right: 26, height: 1, backgroundColor: "rgba(245,247,255,0.4)" },
  items: { flex: 1, flexDirection: "row", alignItems: "stretch", paddingHorizontal: 5, paddingVertical: 6 },
  item: { flex: 1, minWidth: 0, position: "relative", alignItems: "center", justifyContent: "center", gap: 2, borderRadius: 21, paddingHorizontal: 2 },
  pressed: { opacity: 0.78, transform: [{ scale: 0.96 }] },
  activeCapsule: { position: "absolute", top: 1, left: 2, right: 2, bottom: 1, borderRadius: 20, backgroundColor: "rgba(197,210,255,0.13)", borderWidth: 1, borderColor: "rgba(218,226,255,0.22)" },
  label: { color: "#b8c0d1", fontSize: 9, lineHeight: 12, fontWeight: "700", letterSpacing: 0.1 },
  activeLabel: { color: "#e5eaff", fontWeight: "900" },
  activeDot: { position: "absolute", bottom: 3, width: 3, height: 3, borderRadius: 2, backgroundColor: C.accent },
});
