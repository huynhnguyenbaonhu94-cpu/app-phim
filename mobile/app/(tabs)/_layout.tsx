import { Tabs } from "expo-router";
import { Ionicons } from "@expo/vector-icons";
import { BlurView } from "expo-blur";
import { StyleSheet, View } from "react-native";
import { C, TAB_BAR_VISIBLE } from "@/ui";

export default function TabsLayout() {
  const icon = (name: any) => ({ color, size }: { color: string; size: number }) => <Ionicons name={name} color={color} size={size} />;
  const glassBackground = () => <BlurView intensity={68} tint="dark" style={StyleSheet.absoluteFill}><View style={tabStyles.glassTint} /></BlurView>;
  return <Tabs screenOptions={{
    headerShown: false,
    tabBarStyle: TAB_BAR_VISIBLE,
    tabBarBackground: glassBackground,
    tabBarActiveTintColor: C.accent,
    tabBarInactiveTintColor: C.muted,
    tabBarLabelStyle: { fontSize: 10, fontWeight: "800" },
    tabBarItemStyle: { borderRadius: 18, marginHorizontal: 3, marginVertical: 5 },
  }}>
    <Tabs.Screen name="index" options={{ title: "Trang chủ", tabBarIcon: icon("home-outline") }} />
    <Tabs.Screen name="catalog" options={{ title: "Thư viện", tabBarIcon: icon("grid-outline") }} />
    <Tabs.Screen name="search" options={{ title: "Tìm kiếm", tabBarIcon: icon("search-outline") }} />
    <Tabs.Screen name="account" options={{ title: "Tài khoản", tabBarIcon: icon("person-outline") }} />
  </Tabs>;
}

const tabStyles = StyleSheet.create({
  glassTint: { ...StyleSheet.absoluteFillObject, backgroundColor: "rgba(16,21,30,0.58)", borderRadius: 25 },
});
