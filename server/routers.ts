import { z } from "zod";
import { COOKIE_NAME, ONE_YEAR_MS } from "@shared/const";
import { addFavorite, createDeviceSession, createLocalUser, DeviceLimitError, getPlaybackPreferences, getUserByEmail, isFavorite, listDeviceSessions, listFavorites, listWatchHistory, recordWatchHistory, removeFavorite, removeFavoriteIfOlder, removeWatchHistory, removeWatchHistoryIfOlder, revokeAllDeviceSessions, revokeDeviceSession, savePlaybackPreferences, touchDeviceSession, updatePasswordHash } from "./db";
import { getSessionCookieOptions } from "./_core/cookies";
import { systemRouter } from "./_core/systemRouter";
import { adminProcedure, protectedProcedure, publicProcedure, router, sessionProtectedProcedure } from "./_core/trpc";
import { getCatalogMeta, getDailyUpdates, getHome, getMovieDetail, getMovies, getPersistentPosterSource, MAX_CINEMA_PAGE, protectImageSource, searchMovies } from "./cinema";
import { createLocalSession, hashPassword, verifyPassword } from "./localAuth";
import { randomUUID } from "node:crypto";
import type { TrpcContext } from "./_core/context";
import type { User } from "../drizzle/schema";
import { TRPCError } from "@trpc/server";
import { sendMovieRequestToTelegram } from "./_core/telegram";
import { createTvStream, deleteTvStream, listTvStreams, saveTvPoster, saveTvSubtitle, updateTvStream } from "./tvStreams";
import { createTvVideo, deleteTvVideo, listTvVideos, updateTvVideo } from "./tvVideos";

const pageInput = z.number().int().min(1).max(MAX_CINEMA_PAGE).optional();
const slugInput = z.string().trim().min(2).max(120).regex(/^[a-z0-9-]+$/i);
const movieSnapshot = z.object({
  movieSlug: slugInput,
  movieName: z.string().trim().min(1).max(255),
  originName: z.string().trim().max(255).optional(),
  posterUrl: z.string().startsWith("/api/cinema/image/").max(160).nullable().optional(),
  year: z.number().int().min(1900).max(2100).nullable().optional(),
});
const emailInput = z.string().trim().email().max(320).transform((value) => value.toLowerCase());
const passwordInput = z.string().min(8, "Mật khẩu phải có ít nhất 8 ký tự").max(128);
const playbackPreferencesInput = z.record(z.string(), z.unknown()).refine((value) => {
  try { return JSON.stringify(value).length <= 32_000; } catch { return false; }
}, "Playback preferences vượt quá dung lượng cho phép.");
const deviceInput = z.object({
  deviceId: z.string().trim().min(8).max(128).optional(),
  name: z.string().trim().min(1).max(160).optional(),
  model: z.string().trim().max(120).optional(),
  osVersion: z.string().trim().max(80).optional(),
  appVersion: z.string().trim().max(80).optional(),
}).optional();
const movieRequestCooldown = new Map<string, number>();
const loginAttempts = new Map<string, { count: number; resetAt: number }>();
const passwordChangeAttempts = new Map<string, { count: number; resetAt: number }>();
const tvPosterInput = z.string().trim().max(1000).nullable().optional().refine((value) => {
  if (!value) return true;
  if (value.startsWith("/uploads/tv-posters/") || value.startsWith("uploads/tv-posters/")) return true;
  try { return ["http:", "https:"].includes(new URL(value).protocol); } catch { return false; }
}, "Poster phải là URL http(s) hoặc file đã upload trên máy chủ.");

function setSessionCookie(ctx: { req: Parameters<typeof getSessionCookieOptions>[0]; res: { cookie: (name: string, value: string, options: Record<string, unknown>) => void } }, token: string) {
  ctx.res.cookie(COOKIE_NAME, token, { ...getSessionCookieOptions(ctx.req), maxAge: ONE_YEAR_MS });
}

function publicUser(user: NonNullable<Parameters<typeof createLocalSession>[0]>) {
  return { id: user.id, name: user.name, email: user.email, role: user.role, createdAt: user.createdAt };
}

function trustedClientTimestamp(value: string) {
  const parsed = new Date(value);
  return parsed.getTime() > Date.now() + 5 * 60_000 ? new Date() : parsed;
}

function displayIpAddress(value: string | null) {
  if (!value) return null;
  if (value.includes(".")) {
    const parts = value.split(".");
    if (parts.length === 4) return `${parts[0]}.${parts[1]}.${parts[2]}.xxx`;
  }
  if (value.includes(":")) return `${value.split(":").slice(0, 3).join(":")}::…`;
  return "Địa chỉ mạng ẩn";
}

function checkLoginRateLimit(key: string) {
  const now = Date.now();
  const current = loginAttempts.get(key);
  if (current && current.resetAt > now && current.count >= 10) {
    throw new TRPCError({ code: "TOO_MANY_REQUESTS", message: "Bạn đã thử đăng nhập quá nhiều lần. Vui lòng thử lại sau 15 phút." });
  }
  if (loginAttempts.size > 5000) {
    Array.from(loginAttempts.entries()).forEach(([entry, value]) => { if (value.resetAt <= now) loginAttempts.delete(entry); });
  }
}

function recordLoginFailure(key: string) {
  const now = Date.now();
  const current = loginAttempts.get(key);
  loginAttempts.set(key, current && current.resetAt > now ? { count: current.count + 1, resetAt: current.resetAt } : { count: 1, resetAt: now + 15 * 60_000 });
}

function checkPasswordChangeRateLimit(key: string) {
  const entry = passwordChangeAttempts.get(key);
  if (entry && entry.resetAt > Date.now() && entry.count >= 5) {
    throw new TRPCError({ code: "TOO_MANY_REQUESTS", message: "Bạn đã thử đổi mật khẩu quá nhiều lần. Vui lòng thử lại sau 15 phút." });
  }
}

function recordPasswordChangeFailure(key: string) {
  const now = Date.now();
  const entry = passwordChangeAttempts.get(key);
  passwordChangeAttempts.set(key, entry && entry.resetAt > now ? { count: entry.count + 1, resetAt: entry.resetAt } : { count: 1, resetAt: now + 15 * 60_000 });
}

async function issueDeviceSession(ctx: TrpcContext, user: User, details?: z.infer<typeof deviceInput>) {
  const sessionId = randomUUID();
  const expiresAt = new Date(Date.now() + ONE_YEAR_MS);
  const userAgent = String(ctx.req.get("user-agent") || "").slice(0, 160);
  const metadata = {
    userId: user.id,
    sessionId,
    deviceId: details?.deviceId || `web-${randomUUID()}`,
    deviceName: details?.name || (userAgent ? `Trình duyệt · ${userAgent.slice(0, 120)}` : "Trình duyệt web"),
    deviceModel: details?.model || null,
    osVersion: details?.osVersion || null,
    appVersion: details?.appVersion || null,
    ipAddress: String(ctx.req.ip || "").slice(0, 45) || null,
    expiresAt,
  };
  let session: { sessionId: string; expiresAt: Date };
  try { session = await createDeviceSession(metadata); }
  catch (error) {
    if (error instanceof DeviceLimitError) throw new TRPCError({ code: "FORBIDDEN", message: error.message });
    throw error;
  }
  const token = await createLocalSession(user, session.sessionId, session.expiresAt);
  setSessionCookie(ctx, token);
  return { ...(details?.deviceId ? { token } : {}), sessionId: session.sessionId, expiresAt: session.expiresAt };
}

export const appRouter = router({
  system: systemRouter,
  auth: router({
    me: publicProcedure.query(opts => opts.ctx.user ? publicUser(opts.ctx.user) : null),
    register: publicProcedure.input(z.object({ name: z.string().trim().min(2).max(80), email: emailInput, password: passwordInput, device: deviceInput })).mutation(async ({ ctx, input }) => {
      if (await getUserByEmail(input.email)) throw new TRPCError({ code: "CONFLICT", message: "Email này đã được đăng ký" });
      const user = await createLocalUser({ name: input.name, email: input.email, passwordHash: await hashPassword(input.password) });
      if (!user) throw new TRPCError({ code: "INTERNAL_SERVER_ERROR", message: "Không thể tạo tài khoản" });
      const session = await issueDeviceSession(ctx, user, input.device);
      return { user: publicUser(user), ...session };
    }),
    login: publicProcedure.input(z.object({ email: emailInput, password: z.string().min(1).max(128), device: deviceInput })).mutation(async ({ ctx, input }) => {
      const rateKey = `${ctx.req.ip || "unknown"}:${input.email}`;
      checkLoginRateLimit(rateKey);
      const user = await getUserByEmail(input.email);
      if (!user || !(await verifyPassword(input.password, user.passwordHash))) {
        recordLoginFailure(rateKey);
        throw new TRPCError({ code: "UNAUTHORIZED", message: "Email hoặc mật khẩu không đúng" });
      }
      loginAttempts.delete(rateKey);
      const session = await issueDeviceSession(ctx, user, input.device);
      return { user: publicUser(user), ...session };
    }),
    logout: publicProcedure.input(z.object({}).optional()).mutation(async ({ ctx }) => {
      if (ctx.user && ctx.sessionId) await revokeDeviceSession(ctx.user.id, ctx.sessionId, "logout");
      const cookieOptions = getSessionCookieOptions(ctx.req);
      ctx.res.clearCookie(COOKIE_NAME, { ...cookieOptions, maxAge: -1 });
      return { success: true } as const;
    }),
  }),
  cinema: router({
    home: publicProcedure.input(z.object({ page: pageInput }).optional()).query(({ input }) => getHome(input?.page)),
    list: publicProcedure.input(z.object({
      kind: z.enum(["latest", "single", "series", "shows", "animation", "vietsub", "thuyetminh", "longtieng", "ongoing", "completed", "subteam", "theatrical"]),
      page: pageInput,
      category: z.string().trim().max(80).optional(),
      country: z.string().trim().max(80).optional(),
      year: z.number().int().min(1900).max(2100).optional(),
      refresh: z.boolean().optional(),
    })).query(({ input }) => getMovies(input)),
    search: publicProcedure.input(z.object({ keyword: z.string().trim().min(2).max(80), page: pageInput })).query(({ input }) => searchMovies(input)),
    detail: publicProcedure.input(z.object({ slug: slugInput })).query(({ input }) => getMovieDetail(input.slug)),
    dailyUpdates: publicProcedure.input(z.object({ page: pageInput }).optional()).query(({ input }) => getDailyUpdates(input?.page)),
    meta: publicProcedure.query(() => getCatalogMeta()),
    submitRequest: publicProcedure.input(z.object({
      title: z.string().trim().min(2, "Vui lòng nhập tên phim.").max(255),
      // Keep this optional field permissive: users may paste an IMDb/TMDB URL,
      // title ID, or a link copied from the app without a scheme.
      link: z.string().trim().max(500).optional(),
      priority: z.enum(["Thấp", "Bình thường", "Cao", "Khẩn cấp"]),
      notes: z.string().trim().max(4000).optional(),
      imageBase64: z.string().max(11_200_000).optional(),
      imageMimeType: z.enum(["image/jpeg", "image/png", "image/webp"]).optional(),
    })).mutation(async ({ ctx, input }) => {
      const key = ctx.req.ip || ctx.req.get("user-agent") || "unknown";
      const now = Date.now();
      const previous = movieRequestCooldown.get(key) ?? 0;
      if (now - previous < 30_000) {
        throw new TRPCError({ code: "TOO_MANY_REQUESTS", message: "Vui lòng chờ 30 giây trước khi gửi yêu cầu tiếp theo." });
      }
      movieRequestCooldown.set(key, now);
      try {
        await sendMovieRequestToTelegram(input);
        return { success: true } as const;
      } catch (error) {
        movieRequestCooldown.delete(key);
        throw error;
      }
    }),
  }),
  tv: router({
    list: publicProcedure.query(() => listTvStreams(false)),
    adminList: adminProcedure.query(() => listTvStreams(true)),
    videos: publicProcedure.input(z.object({ refresh: z.number().optional() }).optional()).query(() => listTvVideos(false)),
    adminVideos: adminProcedure.query(() => listTvVideos(true)),
    uploadPoster: adminProcedure.input(z.object({
      base64: z.string().min(1).max(11_200_000),
      mimeType: z.enum(["image/jpeg", "image/png", "image/webp"]),
    })).mutation(({ input }) => saveTvPoster(input)),
    uploadSubtitle: adminProcedure.input(z.object({
      base64: z.string().min(1).max(28_000_000),
      mimeType: z.enum(["text/vtt", "application/octet-stream"]),
    })).mutation(({ input }) => saveTvSubtitle(input)),
    create: adminProcedure.input(z.object({
      name: z.string().trim().min(1).max(120),
      streamUrl: z.string().trim().url().max(2000),
      audioUrl: z.string().trim().url().max(2000).nullable().optional(),
      logoUrl: z.string().trim().url().max(1000).nullable().optional(),
      posterUrl: tvPosterInput,
      description: z.string().trim().max(500).nullable().optional(),
      sortOrder: z.number().int().min(0).max(100000).optional(),
      isActive: z.boolean().optional(),
    })).mutation(({ input }) => createTvStream(input)),
    update: adminProcedure.input(z.object({
      id: z.number().int().positive(),
      name: z.string().trim().min(1).max(120),
      streamUrl: z.string().trim().url().max(2000),
      audioUrl: z.string().trim().url().max(2000).nullable().optional(),
      logoUrl: z.string().trim().url().max(1000).nullable().optional(),
      posterUrl: tvPosterInput,
      description: z.string().trim().max(500).nullable().optional(),
      sortOrder: z.number().int().min(0).max(100000).optional(),
      isActive: z.boolean().optional(),
    })).mutation(({ input: { id, ...input } }) => updateTvStream(id, input)),
    remove: adminProcedure.input(z.object({ id: z.number().int().positive() })).mutation(({ input }) => deleteTvStream(input.id)),
    createVideo: adminProcedure.input(z.object({
      name: z.string().trim().min(1).max(180), logoUrl: z.string().trim().url().max(2000).nullable().optional(), description: z.string().trim().max(1000).nullable().optional(), sortOrder: z.number().int().min(0).max(100000).optional(), isActive: z.boolean().optional(), allowPip: z.boolean().optional(), isFeatured: z.boolean().optional(), featuredEffect: z.enum(["glow", "pulse", "ribbon", "spark"]).optional(),
      episodes: z.array(z.object({ episodeNumber: z.number().int().min(1), name: z.string().trim().max(180).optional(), subtitleUrl: z.string().trim().max(2000).nullable().optional(), bilingualSubtitleUrl: z.string().trim().max(2000).nullable().optional(), subtitles: z.array(z.object({ language: z.string().trim().min(1).max(40), subtitleUrl: z.string().trim().max(2000) })).max(20).optional(), qualities: z.array(z.object({ label: z.string().trim().max(40), streamUrl: z.string().trim().url().max(2000), subtitleUrl: z.string().trim().max(2000).nullable().optional(), bilingualSubtitleUrl: z.string().trim().max(2000).nullable().optional(), subtitleTracks: z.array(z.object({ language: z.string().trim().min(1).max(40), subtitleUrl: z.string().trim().max(2000) })).max(20).optional() })).min(1) })).min(1),
    })).mutation(({ input }) => createTvVideo(input)),
    updateVideo: adminProcedure.input(z.object({
      id: z.number().int().positive(), name: z.string().trim().min(1).max(180), logoUrl: z.string().trim().url().max(2000).nullable().optional(), description: z.string().trim().max(1000).nullable().optional(), sortOrder: z.number().int().min(0).max(100000).optional(), isActive: z.boolean().optional(), allowPip: z.boolean().optional(), isFeatured: z.boolean().optional(), featuredEffect: z.enum(["glow", "pulse", "ribbon", "spark"]).optional(),
      episodes: z.array(z.object({ episodeNumber: z.number().int().min(1), name: z.string().trim().max(180).optional(), subtitleUrl: z.string().trim().max(2000).nullable().optional(), bilingualSubtitleUrl: z.string().trim().max(2000).nullable().optional(), subtitles: z.array(z.object({ language: z.string().trim().min(1).max(40), subtitleUrl: z.string().trim().max(2000) })).max(20).optional(), qualities: z.array(z.object({ label: z.string().trim().max(40), streamUrl: z.string().trim().url().max(2000), subtitleUrl: z.string().trim().max(2000).nullable().optional(), bilingualSubtitleUrl: z.string().trim().max(2000).nullable().optional(), subtitleTracks: z.array(z.object({ language: z.string().trim().min(1).max(40), subtitleUrl: z.string().trim().max(2000) })).max(20).optional() })).min(1) })).min(1),
    })).mutation(({ input: { id, ...payload } }) => updateTvVideo(id, payload)),
    removeVideo: adminProcedure.input(z.object({ id: z.number().int().positive() })).mutation(({ input }) => deleteTvVideo(input.id)),
  }),
  account: router({
    current: sessionProtectedProcedure.query(({ ctx }) => publicUser(ctx.user)),
    devices: sessionProtectedProcedure.query(async ({ ctx }) => {
      const rows = await listDeviceSessions(ctx.user.id);
      const onlineCutoff = Date.now() - 2 * 60_000;
      return rows.map((session) => ({
        sessionId: session.sessionId, deviceId: session.deviceId, name: session.deviceName,
        model: session.deviceModel, osVersion: session.osVersion, appVersion: session.appVersion,
        ipAddress: displayIpAddress(session.ipAddress), createdAt: session.createdAt, lastSeenAt: session.lastSeenAt,
        isCurrent: session.sessionId === ctx.sessionId,
        isOnline: session.lastSeenAt.getTime() >= onlineCutoff,
      }));
    }),
    heartbeat: sessionProtectedProcedure.input(z.object({}).optional()).mutation(async ({ ctx }) => {
      if (!ctx.sessionId || !(await touchDeviceSession(ctx.sessionId, ctx.user.id))) {
        throw new TRPCError({ code: "UNAUTHORIZED", message: "Phiên đăng nhập đã bị kết thúc. Vui lòng đăng nhập lại." });
      }
      return { success: true, serverTime: new Date().toISOString() };
    }),
    kickDevice: sessionProtectedProcedure.input(z.object({ sessionId: z.string().uuid() })).mutation(async ({ ctx, input }) => {
      if (input.sessionId === ctx.sessionId) throw new TRPCError({ code: "BAD_REQUEST", message: "Không thể kết thúc thiết bị hiện tại bằng thao tác này." });
      const success = await revokeDeviceSession(ctx.user.id, input.sessionId);
      if (!success) throw new TRPCError({ code: "NOT_FOUND", message: "Phiên thiết bị không còn hoạt động." });
      return { success: true };
    }),
    logoutAll: sessionProtectedProcedure.input(z.object({}).optional()).mutation(async ({ ctx }) => ({ success: true, revokedCount: await revokeAllDeviceSessions(ctx.user.id, "logout_all") })),
    changePassword: sessionProtectedProcedure.input(z.object({ currentPassword: z.string().min(1).max(128), newPassword: z.string().min(10, "Mật khẩu mới phải có ít nhất 10 ký tự").max(128) })).mutation(async ({ ctx, input }) => {
      const rateKey = `${ctx.req.ip || "unknown"}:${ctx.user.id}`;
      checkPasswordChangeRateLimit(rateKey);
      if (!(await verifyPassword(input.currentPassword, ctx.user.passwordHash))) {
        recordPasswordChangeFailure(rateKey);
        throw new TRPCError({ code: "UNAUTHORIZED", message: "Mật khẩu hiện tại không đúng." });
      }
      passwordChangeAttempts.delete(rateKey);
      if (input.currentPassword === input.newPassword) throw new TRPCError({ code: "BAD_REQUEST", message: "Mật khẩu mới phải khác mật khẩu hiện tại." });
      await updatePasswordHash(ctx.user.id, await hashPassword(input.newPassword));
      return { success: true };
    }),
    favorites: protectedProcedure.query(async ({ ctx }) => (await listFavorites(ctx.user.id)).map((item) => ({ ...item, posterUrl: protectImageSource(item.posterUrl) }))),
    isFavorite: protectedProcedure.input(z.object({ movieSlug: slugInput })).query(({ ctx, input }) => isFavorite(ctx.user.id, input.movieSlug)),
    addFavorite: protectedProcedure.input(movieSnapshot).mutation(async ({ ctx, input }) => addFavorite({ userId: ctx.user.id, ...input, posterUrl: await getPersistentPosterSource(input.movieSlug, input.posterUrl) })),
    removeFavorite: protectedProcedure.input(z.object({ movieSlug: slugInput })).mutation(({ ctx, input }) => removeFavorite(ctx.user.id, input.movieSlug)),
    history: protectedProcedure.query(async ({ ctx }) => (await listWatchHistory(ctx.user.id)).map((item) => ({ ...item, posterUrl: protectImageSource(item.posterUrl) }))),
    recordHistory: protectedProcedure.input(movieSnapshot.extend({
      episodeSlug: z.string().trim().max(140).optional(),
      episodeName: z.string().trim().max(255).optional(),
      serverName: z.string().trim().max(160).nullable().optional(),
      watchedSeconds: z.number().int().min(0).max(86_400).optional(),
      durationSeconds: z.number().int().min(0).max(86_400).optional(),
      isCompleted: z.boolean().optional(),
      lastWatchedAt: z.string().datetime().optional(),
    })).mutation(async ({ ctx, input }) => recordWatchHistory({ userId: ctx.user.id, ...input, lastWatchedAt: input.lastWatchedAt ? trustedClientTimestamp(input.lastWatchedAt) : undefined, posterUrl: await getPersistentPosterSource(input.movieSlug, input.posterUrl) })),
    savePreferences: sessionProtectedProcedure.input(z.object({ preferences: playbackPreferencesInput, updatedAt: z.string().datetime() })).mutation(async ({ ctx, input }) => {
      const current = await getPlaybackPreferences(ctx.user.id);
      const incomingAt = trustedClientTimestamp(input.updatedAt);
      if (!current || incomingAt >= current.updatedAt) await savePlaybackPreferences(ctx.user.id, input.preferences, incomingAt);
      return await getPlaybackPreferences(ctx.user.id);
    }),
    sync: sessionProtectedProcedure.input(z.object({
      favorites: z.array(movieSnapshot.extend({ addedAt: z.string().datetime().optional() })).max(100),
      history: z.array(movieSnapshot.extend({
        episodeSlug: z.string().trim().max(140).optional(), episodeName: z.string().trim().max(255).optional(),
        serverName: z.string().trim().max(160).nullable().optional(),
        watchedSeconds: z.number().min(0).max(86_400), durationSeconds: z.number().min(0).max(86_400),
        isCompleted: z.boolean().optional(), lastWatchedAt: z.string().datetime(),
      })).max(100),
      removedFavorites: z.array(z.object({ movieSlug: slugInput, deletedAt: z.string().datetime() })).max(100).optional(),
      removedHistory: z.array(z.object({ key: z.string().trim().max(280), deletedAt: z.string().datetime() })).max(100).optional(),
      preferences: playbackPreferencesInput.optional(),
      preferencesUpdatedAt: z.string().datetime().optional(),
    })).mutation(async ({ ctx, input }) => {
      // Merge into the existing unique-key tables; never replace server state with a local snapshot.
      for (const favorite of input.favorites) {
        const { addedAt, ...snapshot } = favorite;
        await addFavorite({ userId: ctx.user.id, ...snapshot, addedAt: addedAt ? trustedClientTimestamp(addedAt) : undefined, posterUrl: await getPersistentPosterSource(favorite.movieSlug, favorite.posterUrl) });
      }
      for (const history of input.history) {
        await recordWatchHistory({ userId: ctx.user.id, ...history, lastWatchedAt: trustedClientTimestamp(history.lastWatchedAt), posterUrl: await getPersistentPosterSource(history.movieSlug, history.posterUrl) });
      }
      for (const deletion of input.removedFavorites || []) await removeFavoriteIfOlder(ctx.user.id, deletion.movieSlug, trustedClientTimestamp(deletion.deletedAt));
      for (const deletion of input.removedHistory || []) {
        const key = deletion.key;
        const separator = key.lastIndexOf("::");
        if (separator <= 0) continue;
        const movieSlug = key.slice(0, separator);
        const episodeSlug = key.slice(separator + 2) || "movie";
        if (/^[a-z0-9-]{2,140}$/i.test(movieSlug) && /^[a-z0-9-]{1,140}$/i.test(episodeSlug)) {
          await removeWatchHistoryIfOlder(ctx.user.id, movieSlug, episodeSlug, trustedClientTimestamp(deletion.deletedAt));
        }
      }
      if (input.preferences && input.preferencesUpdatedAt) {
        const current = await getPlaybackPreferences(ctx.user.id);
        const incomingAt = trustedClientTimestamp(input.preferencesUpdatedAt);
        if (!current || incomingAt >= current.updatedAt) await savePlaybackPreferences(ctx.user.id, input.preferences, incomingAt);
      }
      const [favorites, history, preferences] = await Promise.all([
        listFavorites(ctx.user.id), listWatchHistory(ctx.user.id), getPlaybackPreferences(ctx.user.id),
      ]);
      return {
        favorites: favorites.map((item) => ({ ...item, posterUrl: protectImageSource(item.posterUrl) })),
        history: history.map((item) => ({ ...item, posterUrl: protectImageSource(item.posterUrl) })),
        preferences,
      };
    }),
  }),
});

export type AppRouter = typeof appRouter;
