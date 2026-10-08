import { z } from "zod";
import { COOKIE_NAME, ONE_YEAR_MS } from "@shared/const";
import { addFavorite, addMovieComment, clearWatchHistory, createLocalUser, deleteMovieComment, findMovieComment, getUserByEmail, getUserById, isFavorite, listFavorites, listMovieComments, listWatchHistory, recordWatchHistory, removeFavorite, removeWatchHistory, updateLocalAccountByAdmin, updateLocalPassword } from "./db";
import { getSessionCookieOptions } from "./_core/cookies";
import { systemRouter } from "./_core/systemRouter";
import { adminProcedure, protectedProcedure, publicProcedure, router } from "./_core/trpc";
import { getCatalogMeta, getDailyUpdates, getHome, getMovieDetail, getMovies, getPersistentPosterSource, MAX_CINEMA_PAGE, protectImageSource, searchMovies } from "./cinema";
import { createLocalSession, hashPassword, verifyPassword } from "./localAuth";
import { listAccountDevices, listAllAccountSummaries, revokeAllSessions, revokeDevice, revokeSession } from "./accountSessions";
import { TRPCError } from "@trpc/server";
import { sendMovieRequestToTelegram } from "./_core/telegram";
import { createTvStream, deleteTvStream, listTvStreams, saveTvPoster, saveTvSubtitle, updateTvStream } from "./tvStreams";
import { createTvVideo, deleteTvVideo, listTvVideos, updateTvVideo } from "./tvVideos";
import { approveQrLogin, completeQrLogin, createQrLoginChallenge, qrLoginStatus } from "./qrLogin";
import { enforceRateLimit, SECURITY_LIMITS } from "./securityRateLimit";

const pageInput = z.number().int().min(1).max(MAX_CINEMA_PAGE).optional();
const slugInput = z.string().trim().min(2).max(120).regex(/^[a-z0-9-]+$/i);
// Id bình luận đến từ app dưới dạng chuỗi, nhưng vẫn nhận cả số cho tiện thử nghiệm.
const commentIdInput = z.union([z.string(), z.number()]);
function toCommentId(value: string | number | null | undefined): number | null {
  if (value === null || value === undefined) return null;
  const parsed = typeof value === "number" ? value : Number.parseInt(String(value), 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}
const movieSnapshot = z.object({
  movieSlug: slugInput,
  movieName: z.string().trim().min(1).max(255),
  originName: z.string().trim().max(255).optional(),
  posterUrl: z.string().startsWith("/api/cinema/image/").max(160).nullable().optional(),
  year: z.number().int().min(1900).max(2100).nullable().optional(),
});
const emailInput = z.string().trim().email().max(320).transform((value) => value.toLowerCase());
const passwordInput = z.string().min(8, "Mật khẩu phải có ít nhất 8 ký tự").max(128);
const changePasswordInput = z.object({
  currentPassword: z.string().min(1).max(128),
  newPassword: passwordInput,
}).refine(({ currentPassword, newPassword }) => currentPassword !== newPassword, {
  message: "Mật khẩu mới phải khác mật khẩu hiện tại.",
  path: ["newPassword"],
});
const movieRequestCooldown = new Map<string, number>();
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
    me: publicProcedure.query(opts => opts.ctx.user),
    register: publicProcedure.input(z.object({ name: z.string().trim().min(2).max(80), email: emailInput, password: passwordInput, deviceId: z.string().trim().max(160).optional(), deviceName: z.string().trim().max(160).optional() })).mutation(async ({ ctx, input }) => {
      enforceRateLimit(ctx.req, "auth.register", SECURITY_LIMITS.registerPerIp.limit, SECURITY_LIMITS.registerPerIp.windowMs);
      if (await getUserByEmail(input.email)) throw new TRPCError({ code: "CONFLICT", message: "Email này đã được đăng ký" });
      const user = await createLocalUser({ name: input.name, email: input.email, passwordHash: await hashPassword(input.password) });
      if (!user) throw new TRPCError({ code: "INTERNAL_SERVER_ERROR", message: "Không thể tạo tài khoản" });
      setSessionCookie(ctx, await createLocalSession(user, ctx.req, input));
      return { user };
    }),
    login: publicProcedure.input(z.object({ email: emailInput, password: z.string().min(1).max(128), deviceId: z.string().trim().max(160).optional(), deviceName: z.string().trim().max(160).optional() })).mutation(async ({ ctx, input }) => {
      enforceRateLimit(ctx.req, "auth.login.ip", SECURITY_LIMITS.loginPerIp.limit, SECURITY_LIMITS.loginPerIp.windowMs);
      enforceRateLimit(ctx.req, "auth.login.email", SECURITY_LIMITS.loginPerEmail.limit, SECURITY_LIMITS.loginPerEmail.windowMs, input.email);
      const user = await getUserByEmail(input.email);
      if (!user || !(await verifyPassword(input.password, user.passwordHash))) throw new TRPCError({ code: "UNAUTHORIZED", message: "Email hoặc mật khẩu không đúng" });
      setSessionCookie(ctx, await createLocalSession(user, ctx.req, input));
      return { user };
    }),
    logout: publicProcedure.mutation(async ({ ctx }) => {
      const token = ctx.req.headers.cookie?.match(new RegExp(`(?:^|;\\s*)${COOKIE_NAME}=([^;]+)`))?.[1];
      await revokeSession(token);
      const cookieOptions = getSessionCookieOptions(ctx.req);
      ctx.res.clearCookie(COOKIE_NAME, { ...cookieOptions, maxAge: -1 });
      return { success: true } as const;
    }),
    qrCreate: publicProcedure.input(z.object({ deviceId: z.string().trim().max(160).optional(), deviceName: z.string().trim().max(160).optional() })).mutation(({ ctx, input }) => {
      enforceRateLimit(ctx.req, "auth.qrCreate", SECURITY_LIMITS.qrCreatePerIp.limit, SECURITY_LIMITS.qrCreatePerIp.windowMs);
      return createQrLoginChallenge(ctx.req, input);
    }),
    qrStatus: publicProcedure.input(z.object({ nonce: z.string().trim().min(32).max(220) })).query(({ input }) => qrLoginStatus(input.nonce)),
    qrApprove: protectedProcedure.input(z.object({ nonce: z.string().trim().min(32).max(220), approved: z.boolean() })).mutation(({ ctx, input }) => approveQrLogin(input.nonce, ctx.user.id, input.approved)),
    qrComplete: publicProcedure.input(z.object({ nonce: z.string().trim().min(32).max(220), deviceId: z.string().trim().max(160).optional(), deviceName: z.string().trim().max(160).optional() })).mutation(async ({ ctx, input }) => {
      enforceRateLimit(ctx.req, "auth.qrComplete", SECURITY_LIMITS.qrCompletePerIp.limit, SECURITY_LIMITS.qrCompletePerIp.windowMs);
      const result = await completeQrLogin(ctx.req, input.nonce, input);
      setSessionCookie(ctx, result.token);
      return { user: result.user };
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

    // Bình luận của phim: khách đọc được, chỉ thành viên đã đăng nhập mới gửi được.
    comments: publicProcedure
      .input(z.object({ slug: slugInput }))
      .query(async ({ ctx, input }) => ({ items: await listMovieComments(input.slug, ctx.user?.id ?? null) })),

    addComment: protectedProcedure
      .input(z.object({
        slug: slugInput,
        content: z.string().trim().min(1, "Nội dung bình luận không được để trống.").max(2000, "Bình luận quá dài, tối đa 2000 ký tự."),
        parentId: commentIdInput.nullish(),
      }))
      .mutation(async ({ ctx, input }) => {
        enforceRateLimit(ctx.req, "cinema.comment", SECURITY_LIMITS.commentPerUser.limit, SECURITY_LIMITS.commentPerUser.windowMs, String(ctx.user.id));
        const parentId = toCommentId(input.parentId);
        if (parentId) {
          const parent = await findMovieComment(parentId);
          if (!parent || parent.movieSlug !== input.slug) {
            throw new TRPCError({ code: "BAD_REQUEST", message: "Bình luận gốc không còn tồn tại." });
          }
        }
        const comment = await addMovieComment({
          movieSlug: input.slug,
          parentId,
          userId: ctx.user.id,
          userName: ctx.user.name?.trim() || ctx.user.email?.split("@")[0] || "Người xem",
          userRole: ctx.user.role,
          content: input.content,
        }, ctx.user.id);
        return { comment };
      }),

    deleteComment: protectedProcedure
      .input(z.object({ slug: slugInput, id: commentIdInput }))
      .mutation(async ({ ctx, input }) => {
        const id = toCommentId(input.id);
        if (!id) throw new TRPCError({ code: "BAD_REQUEST", message: "Bình luận không hợp lệ." });
        const existing = await findMovieComment(id);
        if (!existing || existing.movieSlug !== input.slug) {
          throw new TRPCError({ code: "NOT_FOUND", message: "Bình luận không còn tồn tại." });
        }
        // Chủ bình luận, hoặc quản trị viên.
        if (existing.userId !== ctx.user.id && ctx.user.role !== "admin") {
          throw new TRPCError({ code: "FORBIDDEN", message: "Bạn chỉ xoá được bình luận của mình." });
        }
        await deleteMovieComment(id);
        return { success: true };
      }),
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
    devices: protectedProcedure.query(({ ctx }) => listAccountDevices(ctx.user.id)),
    changePassword: protectedProcedure.input(changePasswordInput).mutation(async ({ ctx, input }) => {
      enforceRateLimit(ctx.req, "account.changePassword", SECURITY_LIMITS.loginPerEmail.limit, SECURITY_LIMITS.loginPerEmail.windowMs, String(ctx.user.id));
      const user = await getUserById(ctx.user.id);
      if (!user || !(await verifyPassword(input.currentPassword, user.passwordHash))) {
        throw new TRPCError({ code: "UNAUTHORIZED", message: "Mật khẩu hiện tại không đúng." });
      }
      await updateLocalPassword(ctx.user.id, await hashPassword(input.newPassword));
      await revokeAllSessions(ctx.user.id);
      const token = await createLocalSession(user, ctx.req, {
        deviceId: ctx.req.get("x-cinemora-device-id") || undefined,
        deviceName: ctx.req.get("x-cinemora-device-name") || undefined,
      });
      setSessionCookie(ctx, token);
      return { success: true } as const;
    }),
    logoutDevice: protectedProcedure.input(z.object({ id: z.number().int().positive() })).mutation(({ ctx, input }) => revokeDevice(ctx.user.id, input.id)),
    logoutAll: protectedProcedure.mutation(async ({ ctx }) => {
      await revokeAllSessions(ctx.user.id);
      const cookieOptions = getSessionCookieOptions(ctx.req);
      ctx.res.clearCookie(COOKIE_NAME, { ...cookieOptions, maxAge: -1 });
      return { success: true } as const;
    }),
    favorites: protectedProcedure.query(async ({ ctx }) => (await listFavorites(ctx.user.id)).map((item) => ({ ...item, posterUrl: protectImageSource(item.posterUrl) }))),
    isFavorite: protectedProcedure.input(z.object({ movieSlug: slugInput })).query(({ ctx, input }) => isFavorite(ctx.user.id, input.movieSlug)),
    addFavorite: protectedProcedure.input(movieSnapshot).mutation(async ({ ctx, input }) => {
      enforceRateLimit(ctx.req, "account.write", SECURITY_LIMITS.accountWritePerUser.limit, SECURITY_LIMITS.accountWritePerUser.windowMs, String(ctx.user.id));
      return addFavorite({ userId: ctx.user.id, ...input, posterUrl: await getPersistentPosterSource(input.movieSlug, input.posterUrl) });
    }),
    removeFavorite: protectedProcedure.input(z.object({ movieSlug: slugInput })).mutation(({ ctx, input }) => {
      enforceRateLimit(ctx.req, "account.write", SECURITY_LIMITS.accountWritePerUser.limit, SECURITY_LIMITS.accountWritePerUser.windowMs, String(ctx.user.id));
      return removeFavorite(ctx.user.id, input.movieSlug);
    }),
    history: protectedProcedure.query(async ({ ctx }) => (await listWatchHistory(ctx.user.id)).map((item) => ({ ...item, posterUrl: protectImageSource(item.posterUrl) }))),
    recordHistory: protectedProcedure.input(movieSnapshot.extend({
      episodeSlug: z.string().trim().max(140).optional(),
      episodeName: z.string().trim().max(255).optional(),
      watchedSeconds: z.number().int().min(0).max(86_400).optional(),
      durationSeconds: z.number().int().min(0).max(86_400).optional(),
    })).mutation(async ({ ctx, input }) => {
      enforceRateLimit(ctx.req, "account.write", SECURITY_LIMITS.accountWritePerUser.limit, SECURITY_LIMITS.accountWritePerUser.windowMs, String(ctx.user.id));
      return recordWatchHistory({ userId: ctx.user.id, ...input, posterUrl: await getPersistentPosterSource(input.movieSlug, input.posterUrl) });
    }),
    removeHistory: protectedProcedure.input(z.object({ movieSlug: slugInput, episodeSlug: z.string().trim().max(140).optional() })).mutation(({ ctx, input }) => {
      enforceRateLimit(ctx.req, "account.write", SECURITY_LIMITS.accountWritePerUser.limit, SECURITY_LIMITS.accountWritePerUser.windowMs, String(ctx.user.id));
      return removeWatchHistory(ctx.user.id, input.movieSlug, input.episodeSlug);
    }),
    clearHistory: protectedProcedure.mutation(({ ctx }) => {
      enforceRateLimit(ctx.req, "account.write", SECURITY_LIMITS.accountWritePerUser.limit, SECURITY_LIMITS.accountWritePerUser.windowMs, String(ctx.user.id));
      return clearWatchHistory(ctx.user.id);
    }),
  }),
  adminAccounts: router({
    list: adminProcedure.query(() => listAllAccountSummaries()),
    devices: adminProcedure.input(z.object({ userId: z.number().int().positive() })).query(({ input }) => listAccountDevices(input.userId)),
    logoutAll: adminProcedure.input(z.object({ userId: z.number().int().positive() })).mutation(({ input }) => revokeAllSessions(input.userId)),
    update: adminProcedure.input(z.object({
      id: z.number().int().positive(),
      name: z.string().trim().min(2).max(120).optional(),
      email: z.string().trim().email().max(255).optional(),
      password: z.string().min(8, "Mật khẩu phải có ít nhất 8 ký tự").max(200).optional(),
      role: z.enum(["user", "admin"]).optional(),
    })).mutation(async ({ input }) => {
      const { password, ...rest } = input;
      const updated = await updateLocalAccountByAdmin({ ...rest, ...(password ? { passwordHash: await hashPassword(password) } : {}) });
      if (password) await revokeAllSessions(input.id);
      return updated;
    }),
  }),
});

export type AppRouter = typeof appRouter;
