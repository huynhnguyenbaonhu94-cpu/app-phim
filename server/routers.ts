import { z } from "zod";
import { COOKIE_NAME, ONE_YEAR_MS } from "@shared/const";
import { addFavorite, changeUserPassword, createLocalUser, getAccountPreferences, getUserByEmail, isFavorite, listAuthSessions, listFavorites, listWatchHistory, recordWatchHistory, removeFavorite, removeWatchHistory, revokeAllAuthSessions, revokeAuthSession, saveAccountPreferences } from "./db";
import { getSessionCookieOptions } from "./_core/cookies";
import { systemRouter } from "./_core/systemRouter";
import { adminProcedure, protectedProcedure, publicProcedure, router } from "./_core/trpc";
import { getCatalogMeta, getDailyUpdates, getHome, getMovieDetail, getMovies, getPersistentPosterSource, MAX_CINEMA_PAGE, protectImageSource, searchMovies } from "./cinema";
import { createLocalSession, hashPassword, verifyPassword } from "./localAuth";
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
const deviceInput = z.object({ deviceName: z.string().trim().min(1).max(120).optional(), deviceModel: z.string().trim().max(120).optional(), platform: z.enum(["ios", "web", "android"]).optional() });
const publicUser = (user: NonNullable<import("../drizzle/schema").User> | null) => user ? ({ id: user.id, name: user.name, email: user.email, role: user.role }) : null;
const movieRequestCooldown = new Map<string, number>();
const authRateBuckets = new Map<string, { count: number; resetAt: number }>();

function consumeAuthRateLimit(key: string, max: number, windowMs: number) {
  const now = Date.now();
  if (authRateBuckets.size > 5_000) {
    authRateBuckets.forEach((bucket, bucketKey) => { if (bucket.resetAt <= now) authRateBuckets.delete(bucketKey); });
  }
  const bucket = authRateBuckets.get(key);
  if (!bucket || bucket.resetAt <= now) {
    authRateBuckets.set(key, { count: 1, resetAt: now + windowMs });
    return;
  }
  if (bucket.count >= max) throw new TRPCError({ code: "TOO_MANY_REQUESTS", message: "Bạn thao tác quá nhiều lần. Hãy thử lại sau ít phút." });
  bucket.count += 1;
}

const tvPosterInput = z.string().trim().max(1000).nullable().optional().refine((value) => {
  if (!value) return true;
  if (value.startsWith("/uploads/tv-posters/") || value.startsWith("uploads/tv-posters/")) return true;
  try { return ["http:", "https:"].includes(new URL(value).protocol); } catch { return false; }
}, "Poster phải là URL http(s) hoặc file đã upload trên máy chủ.");

function setSessionCookie(ctx: { req: Parameters<typeof getSessionCookieOptions>[0]; res: { cookie: (name: string, value: string, options: Record<string, unknown>) => void } }, token: string) {
  ctx.res.cookie(COOKIE_NAME, token, { ...getSessionCookieOptions(ctx.req), maxAge: ONE_YEAR_MS });
}

export const appRouter = router({
  system: systemRouter,
  auth: router({
    me: publicProcedure.query(opts => publicUser(opts.ctx.user)),
    current: publicProcedure.query(opts => ({ user: publicUser(opts.ctx.user) })),
    register: publicProcedure.input(z.object({ name: z.string().trim().min(2).max(80), email: emailInput, password: passwordInput }).extend(deviceInput.shape)).mutation(async ({ ctx, input }) => {
      consumeAuthRateLimit(`register:${ctx.req.ip || "unknown"}`, 5, 60 * 60 * 1000);
      if (await getUserByEmail(input.email)) throw new TRPCError({ code: "CONFLICT", message: "Email này đã được đăng ký" });
      const user = await createLocalUser({ name: input.name, email: input.email, passwordHash: await hashPassword(input.password) });
      if (!user) throw new TRPCError({ code: "INTERNAL_SERVER_ERROR", message: "Không thể tạo tài khoản" });
      const session = await createLocalSession(user, ctx.req, input);
      setSessionCookie(ctx, session.token);
      return { user: publicUser(user), ...(input.platform && input.platform !== "web" ? { token: session.token } : {}) };
    }),
    login: publicProcedure.input(z.object({ email: emailInput, password: z.string().min(1).max(128) }).extend(deviceInput.shape)).mutation(async ({ ctx, input }) => {
      consumeAuthRateLimit(`login:${ctx.req.ip || "unknown"}:${input.email}`, 10, 15 * 60 * 1000);
      const user = await getUserByEmail(input.email);
      if (!user || !(await verifyPassword(input.password, user.passwordHash))) throw new TRPCError({ code: "UNAUTHORIZED", message: "Email hoặc mật khẩu không đúng" });
      let session: Awaited<ReturnType<typeof createLocalSession>>;
      try { session = await createLocalSession(user, ctx.req, input); }
      catch (error) {
        if (error instanceof Error && error.message.includes("5 thiết bị")) throw new TRPCError({ code: "FORBIDDEN", message: error.message });
        throw error;
      }
      setSessionCookie(ctx, session.token);
      return { user: publicUser(user), ...(input.platform && input.platform !== "web" ? { token: session.token } : {}) };
    }),
    logout: publicProcedure.mutation(async ({ ctx }) => {
      if (ctx.user && ctx.sessionId) await revokeAuthSession(ctx.user.id, ctx.sessionId, "logout");
      const cookieOptions = getSessionCookieOptions(ctx.req);
      ctx.res.clearCookie(COOKIE_NAME, { ...cookieOptions, maxAge: -1 });
      return { success: true } as const;
    }),
    changePassword: protectedProcedure.input(z.object({ currentPassword: z.string().min(1).max(128), newPassword: passwordInput, confirmPassword: z.string().min(1).max(128), logoutAll: z.boolean() })).mutation(async ({ ctx, input }) => {
      if (input.newPassword !== input.confirmPassword) throw new TRPCError({ code: "BAD_REQUEST", message: "Hai mật khẩu mới không khớp." });
      if (!(await verifyPassword(input.currentPassword, ctx.user.passwordHash))) throw new TRPCError({ code: "UNAUTHORIZED", message: "Mật khẩu cũ không đúng." });
      if (input.currentPassword === input.newPassword) throw new TRPCError({ code: "BAD_REQUEST", message: "Mật khẩu mới phải khác mật khẩu cũ." });
      await changeUserPassword(ctx.user.id, await hashPassword(input.newPassword));
      if (input.logoutAll) {
        await revokeAllAuthSessions(ctx.user.id, "password_changed");
        const cookieOptions = getSessionCookieOptions(ctx.req);
        ctx.res.clearCookie(COOKIE_NAME, { ...cookieOptions, maxAge: -1 });
      }
      return { success: true, loggedOut: input.logoutAll } as const;
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
    favorites: protectedProcedure.query(async ({ ctx }) => (await listFavorites(ctx.user.id)).map((item) => ({ ...item, posterUrl: protectImageSource(item.posterUrl) }))),
    isFavorite: protectedProcedure.input(z.object({ movieSlug: slugInput })).query(({ ctx, input }) => isFavorite(ctx.user.id, input.movieSlug)),
    addFavorite: protectedProcedure.input(movieSnapshot).mutation(async ({ ctx, input }) => { await addFavorite({ userId: ctx.user.id, ...input, posterUrl: await getPersistentPosterSource(input.movieSlug, input.posterUrl) }); return { success: true } as const; }),
    removeFavorite: protectedProcedure.input(z.object({ movieSlug: slugInput })).mutation(async ({ ctx, input }) => { await removeFavorite(ctx.user.id, input.movieSlug); return { success: true } as const; }),
    history: protectedProcedure.query(async ({ ctx }) => (await listWatchHistory(ctx.user.id)).map((item) => ({ ...item, posterUrl: protectImageSource(item.posterUrl) }))),
    recordHistory: protectedProcedure.input(movieSnapshot.extend({
      episodeSlug: z.string().trim().max(140).optional(),
      episodeName: z.string().trim().max(255).optional(),
      watchedSeconds: z.number().int().min(0).max(86_400).optional(),
      durationSeconds: z.number().int().min(0).max(86_400).optional(),
    })).mutation(async ({ ctx, input }) => { await recordWatchHistory({ userId: ctx.user.id, ...input, posterUrl: await getPersistentPosterSource(input.movieSlug, input.posterUrl) }); return { success: true } as const; }),
    deleteHistory: protectedProcedure.input(z.object({ movieSlug: slugInput, episodeSlug: z.string().trim().max(140).optional() })).mutation(({ ctx, input }) => removeWatchHistory(ctx.user.id, input.movieSlug, input.episodeSlug)),
    clearHistory: protectedProcedure.input(z.object({})).mutation(({ ctx }) => removeWatchHistory(ctx.user.id)),
    devices: protectedProcedure.query(async ({ ctx }) => {
      const sessions = await listAuthSessions(ctx.user.id);
      const onlineCutoff = Date.now() - 90_000;
      return sessions.map((session) => ({
        id: session.id, deviceName: session.deviceName, deviceModel: session.deviceModel,
        platform: session.platform, ipAddress: session.ipAddress,
        createdAt: session.createdAt.toISOString(), lastSeenAt: session.lastSeenAt.toISOString(),
        online: session.lastSeenAt.getTime() >= onlineCutoff,
        current: session.id === ctx.sessionId,
      }));
    }),
    kickDevice: protectedProcedure.input(z.object({ sessionId: z.string().min(1).max(36) })).mutation(async ({ ctx, input }) => ({ success: await revokeAuthSession(ctx.user.id, input.sessionId, "kicked") })),
    logoutCurrent: protectedProcedure.input(z.object({})).mutation(async ({ ctx }) => {
      if (ctx.sessionId) await revokeAuthSession(ctx.user.id, ctx.sessionId, "logout");
      const cookieOptions = getSessionCookieOptions(ctx.req);
      ctx.res.clearCookie(COOKIE_NAME, { ...cookieOptions, maxAge: -1 });
      return { success: true } as const;
    }),
    logoutAllDevices: protectedProcedure.input(z.object({})).mutation(async ({ ctx }) => {
      await revokeAllAuthSessions(ctx.user.id, "logout_all");
      const cookieOptions = getSessionCookieOptions(ctx.req);
      ctx.res.clearCookie(COOKIE_NAME, { ...cookieOptions, maxAge: -1 });
      return { success: true } as const;
    }),
    preferences: protectedProcedure.query(({ ctx }) => getAccountPreferences(ctx.user.id)),
    savePreferences: protectedProcedure.input(z.object({ preferences: z.record(z.string(), z.unknown()) })).mutation(async ({ ctx, input }) => {
      const merged = { ...(await getAccountPreferences(ctx.user.id)), ...input.preferences };
      if (JSON.stringify(merged).length > 16_000) throw new TRPCError({ code: "BAD_REQUEST", message: "Dữ liệu cài đặt quá lớn." });
      return saveAccountPreferences(ctx.user.id, merged);
    }),
  }),
});

export type AppRouter = typeof appRouter;
