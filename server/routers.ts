import { z } from "zod";
import { COOKIE_NAME, ONE_YEAR_MS } from "@shared/const";
import { addFavorite, createLocalUser, getUserByEmail, isFavorite, listFavorites, listWatchHistory, recordWatchHistory, removeFavorite } from "./db";
import { getSessionCookieOptions } from "./_core/cookies";
import { systemRouter } from "./_core/systemRouter";
import { protectedProcedure, publicProcedure, router } from "./_core/trpc";
import { getCatalogMeta, getDailyUpdates, getHome, getMovieDetail, getMovies, getPersistentPosterSource, MAX_CINEMA_PAGE, protectImageSource, searchMovies } from "./cinema";
import { createLocalSession, hashPassword, verifyPassword } from "./localAuth";
import { TRPCError } from "@trpc/server";
import { sendMovieRequestToTelegram } from "./_core/telegram";

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
const movieRequestCooldown = new Map<string, number>();

function setSessionCookie(ctx: { req: Parameters<typeof getSessionCookieOptions>[0]; res: { cookie: (name: string, value: string, options: Record<string, unknown>) => void } }, token: string) {
  ctx.res.cookie(COOKIE_NAME, token, { ...getSessionCookieOptions(ctx.req), maxAge: ONE_YEAR_MS });
}

export const appRouter = router({
  system: systemRouter,
  auth: router({
    me: publicProcedure.query(opts => opts.ctx.user),
    register: publicProcedure.input(z.object({ name: z.string().trim().min(2).max(80), email: emailInput, password: passwordInput })).mutation(async ({ ctx, input }) => {
      if (await getUserByEmail(input.email)) throw new TRPCError({ code: "CONFLICT", message: "Email này đã được đăng ký" });
      const user = await createLocalUser({ name: input.name, email: input.email, passwordHash: await hashPassword(input.password) });
      if (!user) throw new TRPCError({ code: "INTERNAL_SERVER_ERROR", message: "Không thể tạo tài khoản" });
      setSessionCookie(ctx, await createLocalSession(user));
      return { user };
    }),
    login: publicProcedure.input(z.object({ email: emailInput, password: z.string().min(1).max(128) })).mutation(async ({ ctx, input }) => {
      const user = await getUserByEmail(input.email);
      if (!user || !(await verifyPassword(input.password, user.passwordHash))) throw new TRPCError({ code: "UNAUTHORIZED", message: "Email hoặc mật khẩu không đúng" });
      setSessionCookie(ctx, await createLocalSession(user));
      return { user };
    }),
    logout: publicProcedure.mutation(({ ctx }) => {
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
  account: router({
    favorites: protectedProcedure.query(async ({ ctx }) => (await listFavorites(ctx.user.id)).map((item) => ({ ...item, posterUrl: protectImageSource(item.posterUrl) }))),
    isFavorite: protectedProcedure.input(z.object({ movieSlug: slugInput })).query(({ ctx, input }) => isFavorite(ctx.user.id, input.movieSlug)),
    addFavorite: protectedProcedure.input(movieSnapshot).mutation(async ({ ctx, input }) => addFavorite({ userId: ctx.user.id, ...input, posterUrl: await getPersistentPosterSource(input.movieSlug, input.posterUrl) })),
    removeFavorite: protectedProcedure.input(z.object({ movieSlug: slugInput })).mutation(({ ctx, input }) => removeFavorite(ctx.user.id, input.movieSlug)),
    history: protectedProcedure.query(async ({ ctx }) => (await listWatchHistory(ctx.user.id)).map((item) => ({ ...item, posterUrl: protectImageSource(item.posterUrl) }))),
    recordHistory: protectedProcedure.input(movieSnapshot.extend({
      episodeSlug: z.string().trim().max(140).optional(),
      episodeName: z.string().trim().max(255).optional(),
      watchedSeconds: z.number().int().min(0).max(86_400).optional(),
      durationSeconds: z.number().int().min(0).max(86_400).optional(),
    })).mutation(async ({ ctx, input }) => recordWatchHistory({ userId: ctx.user.id, ...input, posterUrl: await getPersistentPosterSource(input.movieSlug, input.posterUrl) })),
  }),
});

export type AppRouter = typeof appRouter;
