import { useEffect, useRef, useState } from "react";
import { Stack } from "expo-router";
import { StatusBar } from "expo-status-bar";
import * as ScreenOrientation from "expo-screen-orientation";
import { Animated, Easing, StyleSheet, Text, View } from "react-native";
import { Image } from "expo-image";
import { C } from "@/ui";

function LaunchLoader({ visible }: { visible: boolean }) {
  const opacity = useRef(new Animated.Value(1)).current;
  const scale = useRef(new Animated.Value(1)).current;
  const pulse = useRef(new Animated.Value(0.92)).current;
  const [mounted, setMounted] = useState(true);

  useEffect(() => {
    const pulseLoop = Animated.loop(Animated.sequence([
      Animated.parallel([
        Animated.timing(pulse, { toValue: 1.04, duration: 720, easing: Easing.out(Easing.quad), useNativeDriver: true }),
        Animated.timing(opacity, { toValue: 0.78, duration: 720, easing: Easing.inOut(Easing.quad), useNativeDriver: true }),
      ]),
      Animated.parallel([
        Animated.timing(pulse, { toValue: 0.92, duration: 720, easing: Easing.inOut(Easing.quad), useNativeDriver: true }),
        Animated.timing(opacity, { toValue: 1, duration: 720, easing: Easing.inOut(Easing.quad), useNativeDriver: true }),
      ]),
    ]));
    pulseLoop.start();
    const timer = setTimeout(() => {
      pulseLoop.stop();
      Animated.parallel([
        Animated.timing(opacity, { toValue: 0, duration: 360, useNativeDriver: true }),
        Animated.timing(scale, { toValue: 1.08, duration: 360, easing: Easing.out(Easing.cubic), useNativeDriver: true }),
      ]).start(({ finished }) => { if (finished) setMounted(false); });
    }, 1050);
    return () => { clearTimeout(timer); pulseLoop.stop(); };
  }, [opacity, pulse, scale]);

  if (!mounted || !visible) return null;
  return <Animated.View pointerEvents="none" style={[launchStyles.root, { opacity, transform: [{ scale }] }]}>
    <View style={launchStyles.glow} />
    <Animated.View style={{ transform: [{ scale: pulse }] }}>
      <Image source={require("../assets/icon-cinemora.png")} contentFit="contain" style={launchStyles.logo} />
    </Animated.View>
    <Text style={launchStyles.brand}>CINEMORA</Text>
    <Text style={launchStyles.tagline}>PHIM HAY MỖI NGÀY</Text>
    <View style={launchStyles.loadingTrack}><Animated.View style={[launchStyles.loadingBar, { opacity: pulse }]} /></View>
  </Animated.View>;
}

export default function Layout() {
  const [showLaunchLoader, setShowLaunchLoader] = useState(true);
  useEffect(() => {
    void ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.PORTRAIT_UP).catch(() => undefined);
    const timer = setTimeout(() => setShowLaunchLoader(false), 1500);
    return () => clearTimeout(timer);
  }, []);

  return <>
    <StatusBar style="light" />
    <Stack screenOptions={{
      headerStyle: { backgroundColor: C.bg },
      headerTintColor: C.text,
      headerTitleStyle: { fontWeight: "800" },
      contentStyle: { backgroundColor: C.bg },
    }}>
      <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
      <Stack.Screen name="movie/[slug]" options={{ title: "Chi tiết phim" }} />
    </Stack>
    <LaunchLoader visible={showLaunchLoader} />
  </>;
}

const launchStyles = StyleSheet.create({
  root: { ...StyleSheet.absoluteFillObject, zIndex: 1000, alignItems: "center", justifyContent: "center", backgroundColor: "#080A10" },
  glow: { position: "absolute", width: 260, height: 260, borderRadius: 130, backgroundColor: "rgba(210,243,107,0.07)" },
  logo: { width: 94, height: 94, borderRadius: 26 },
  brand: { color: "#F3F5FA", fontSize: 24, fontWeight: "900", letterSpacing: 3.2, marginTop: 18 },
  tagline: { color: "#8D96A9", fontSize: 9, fontWeight: "800", letterSpacing: 1.8, marginTop: 7 },
  loadingTrack: { width: 88, height: 3, overflow: "hidden", borderRadius: 2, backgroundColor: "rgba(255,255,255,0.12)", marginTop: 28 },
  loadingBar: { width: "52%", height: "100%", borderRadius: 2, backgroundColor: C.accent },
});
