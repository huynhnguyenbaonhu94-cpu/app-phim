import { trpc } from "@/lib/trpc";
import { TRPCClientError } from "@trpc/client";
import { useCallback, useEffect, useMemo, useRef } from "react";
import { clearLocalLibrary, setCloudSyncEnabled, syncLocalLibraryToAccount } from "@/lib/localLibrary";

let sessionExpiredEventSent = false;
let syncedLibraryUserId: number | null = null;
let syncingLibraryUserId: number | null = null;

type UseAuthOptions = {
  redirectOnUnauthenticated?: boolean;
  redirectPath?: string;
};

export function useAuth(options?: UseAuthOptions) {
  const { redirectOnUnauthenticated = false, redirectPath } = options ?? {};
  const utils = trpc.useUtils();
  const meQuery = trpc.auth.me.useQuery(undefined, { retry: false, refetchOnWindowFocus: true, refetchInterval: 30_000 });
  const logoutMutation = trpc.auth.logout.useMutation({ onSuccess: () => { utils.auth.me.setData(undefined, null); } });
  const hadUser = useRef(false);
  const manualLogout = useRef(false);

  useEffect(() => {
    const userId = meQuery.data?.id ?? null;
    setCloudSyncEnabled(userId !== null, userId);
    if (userId !== null && syncedLibraryUserId !== userId && syncingLibraryUserId !== userId) {
      syncingLibraryUserId = userId;
      void syncLocalLibraryToAccount().then(() => { syncedLibraryUserId = userId; }).catch(() => undefined).finally(() => {
        if (syncingLibraryUserId === userId) syncingLibraryUserId = null;
      });
    } else if (meQuery.data === null) {
      syncedLibraryUserId = null;
      syncingLibraryUserId = null;
    }
  }, [meQuery.data]);
  useEffect(() => {
    const onIntentionalLogout = () => { manualLogout.current = true; };
    window.addEventListener("cinemora-intentional-logout", onIntentionalLogout);
    if (meQuery.data) { hadUser.current = true; manualLogout.current = false; sessionExpiredEventSent = false; }
    else if (hadUser.current && !manualLogout.current && !meQuery.isLoading && !sessionExpiredEventSent) {
      hadUser.current = false;
      sessionExpiredEventSent = true;
      setCloudSyncEnabled(false);
      clearLocalLibrary();
      window.dispatchEvent(new CustomEvent("cinemora-session-expired"));
    }
    return () => window.removeEventListener("cinemora-intentional-logout", onIntentionalLogout);
  }, [meQuery.data, meQuery.isLoading]);

  const logout = useCallback(async () => {
    manualLogout.current = true;
    window.dispatchEvent(new CustomEvent("cinemora-intentional-logout"));
    try {
      await logoutMutation.mutateAsync();
    } catch (error: unknown) {
      if (!(error instanceof TRPCClientError) || error.data?.code !== "UNAUTHORIZED") throw error;
    } finally {
      setCloudSyncEnabled(false);
      clearLocalLibrary();
      utils.auth.me.setData(undefined, null);
      await utils.auth.me.invalidate();
    }
  }, [logoutMutation, utils]);

  const state = useMemo(() => ({
    user: meQuery.data ?? null,
    loading: meQuery.isLoading || logoutMutation.isPending,
    error: meQuery.error ?? logoutMutation.error ?? null,
    isAuthenticated: Boolean(meQuery.data),
  }), [meQuery.data, meQuery.error, meQuery.isLoading, logoutMutation.error, logoutMutation.isPending]);

  // Kept for compatibility with protected layouts; local auth UI handles login.
  void redirectOnUnauthenticated;
  void redirectPath;

  return { ...state, refresh: () => meQuery.refetch(), logout };
}
