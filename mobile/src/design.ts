import { Platform } from "react-native";

export const colors = {
  background: "#080A10",
  backgroundElevated: "#101521",
  surface: "rgba(24, 30, 43, 0.76)",
  surfaceStrong: "rgba(29, 36, 51, 0.9)",
  surfaceSoft: "rgba(47, 57, 77, 0.46)",
  glass: "rgba(255, 255, 255, 0.075)",
  glassHighlight: "rgba(255, 255, 255, 0.18)",
  border: "rgba(225, 232, 255, 0.14)",
  borderStrong: "rgba(225, 232, 255, 0.22)",
  text: "#F7F8FC",
  textSecondary: "#B7BFCE",
  textMuted: "#858FA1",
  primary: "#C5D2FF",
  primaryPressed: "#AABCF7",
  onPrimary: "#10131A",
  success: "#8EE0B3",
  warning: "#F5C979",
  error: "#FF8E8B",
  scrim: "rgba(2, 4, 9, 0.68)",
  glow: "rgba(158, 181, 255, 0.11)",
} as const;

export const spacing = { xs: 4, sm: 8, md: 12, lg: 16, xl: 20, xxl: 28, xxxl: 36 } as const;
export const radius = { sm: 10, md: 16, lg: 22, xl: 28, pill: 999 } as const;
export const typography = {
  display: { fontSize: 32, lineHeight: 38, fontWeight: "900" as const, letterSpacing: -0.8 },
  title: { fontSize: 24, lineHeight: 30, fontWeight: "900" as const, letterSpacing: -0.4 },
  section: { fontSize: 18, lineHeight: 24, fontWeight: "800" as const },
  body: { fontSize: 15, lineHeight: 22, fontWeight: "500" as const },
  label: { fontSize: 12, lineHeight: 16, fontWeight: "800" as const },
  caption: { fontSize: 11, lineHeight: 15, fontWeight: "600" as const },
} as const;
export const motion = { fast: 140, normal: 220, slow: 360 } as const;
export const blur = { tabBar: 72, glass: Platform.OS === "ios" ? 54 : 26 } as const;

export const C = {
  bg: colors.background,
  surface: colors.surface,
  surface2: colors.surfaceSoft,
  text: colors.text,
  muted: colors.textSecondary,
  accent: colors.primary,
  line: colors.border,
  danger: colors.error,
} as const;
