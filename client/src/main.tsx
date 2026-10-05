import { trpc } from "@/lib/trpc";
import { Capacitor } from "@capacitor/core";
import { UNAUTHED_ERR_MSG } from '@shared/const';
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { httpBatchLink, TRPCClientError } from "@trpc/client";
import { createRoot } from "react-dom/client";
import superjson from "superjson";
import App from "./App";
import "./index.css";
import { toast } from "sonner";
const apiBaseUrl = (import.meta.env.VITE_API_BASE_URL || "").trim().replace(/\/+$/, "");
const trpcUrl = apiBaseUrl ? `${apiBaseUrl}/api/trpc` : "/api/trpc";
const browserDeviceId = (() => { const key = "cinemora:device-id"; const current = localStorage.getItem(key); if (current) return current; const value = globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random()}`; localStorage.setItem(key, value); return value; })();
if (Capacitor.isNativePlatform()) {
  document.documentElement.classList.add("cinemora-native");
}

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      gcTime: 10 * 60_000,       // giữ cache 10 phút sau khi component unmount
      staleTime: 60_000,          // coi data là fresh trong 1 phút
      refetchOnWindowFocus: false, // không tự fetch lại khi switch tab
      refetchOnReconnect: false,
      retry: 1,
    },
  },
});

const redirectToLoginIfUnauthorized = (error: unknown) => {
  if (!(error instanceof TRPCClientError)) return;
  if (typeof window === "undefined") return;

  const isUnauthorized = error.message === UNAUTHED_ERR_MSG || error.message.includes("bị đăng xuất");

  if (!isUnauthorized) return;

  if (error.message.includes("bị đăng xuất")) toast.error(error.message);

  // Local email/password auth uses the httpOnly session cookie; public pages
  // must never redirect visitors to a third-party login portal.
};

queryClient.getQueryCache().subscribe(event => {
  if (event.type === "updated" && event.action.type === "error") {
    const error = event.query.state.error;
    redirectToLoginIfUnauthorized(error);
    console.error("[API Query Error]", error);
  }
});

queryClient.getMutationCache().subscribe(event => {
  if (event.type === "updated" && event.action.type === "error") {
    const error = event.mutation.state.error;
    redirectToLoginIfUnauthorized(error);
    console.error("[API Mutation Error]", error);
  }
});

const trpcClient = trpc.createClient({
  links: [
    httpBatchLink({
      url: trpcUrl,
      transformer: superjson,
      headers() { return { "x-device-id": `web:${browserDeviceId}`, "x-device-name": "Trình duyệt web", "x-device-model": navigator.userAgent.slice(0, 120) }; },
      fetch(input, init) {
        return globalThis.fetch(input, {
          ...(init ?? {}),
          credentials: "include",
        });
      },
    }),
  ],
});

createRoot(document.getElementById("root")!).render(
  <trpc.Provider client={trpcClient} queryClient={queryClient}>
    <QueryClientProvider client={queryClient}>
      <App />
    </QueryClientProvider>
  </trpc.Provider>
);
