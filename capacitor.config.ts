import type { CapacitorConfig } from "@capacitor/cli";

const config: CapacitorConfig = {
  appId: "app.serval438.taurus3258",
  appName: "Cinemora",
  webDir: "dist/public",
  backgroundColor: "#08090c",
  ios: {
    contentInset: "automatic",
    preferredContentMode: "mobile",
    backgroundColor: "#08090c",
    allowsLinkPreview: true,
  },
};

export default config;