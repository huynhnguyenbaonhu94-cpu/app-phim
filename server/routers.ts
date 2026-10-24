import { z } from "zod";
import { COOKIE_NAME, ONE_YEAR_MS } from "@shared/const";
import { setUserBadges, setUserNameStyle, addFavorite, addMovieComment, clearWatchHistory, createLocalUser, deleteMovieComment, findMovieComment, getUserByEmail, getUserById, isFavorite, listFavorites, listMovieComments, listWatchHistory, pinMovieComment, recordWatchHistory, removeFavorite, removeWatchHistory, setUserAvatar, setUserBadge, updateLocalAccountByAdmin, updateLocalPassword } from "./db";
import { getSessionCookieOptions } from "./_core/cookies";
import { systemRouter } from "./_core/systemRouter";
import { adminProcedure, protectedProcedure, publicProcedure, router } from "./_core/trpc";
import { getCatalogMeta, getDailyUpdates, getFilterCounts, getHome, getMovieDetail, getMovies, getPersistentPosterSource, MAX_CINEMA_PAGE, protectImageSource, searchMovies } from "./cinema";
import { createLocalSession, hashPassword, verifyPassword } from "./localAuth";
import { listAccountDevices, listAllAccountSummaries, revokeAllSessions, revokeDevice, revokeSession } from "./accountSessions";
import { TRPCError } from "@trpc/server";
import { sendMovieRequestToTelegram } from "./_core/telegram";
import {
  addMovieEpisode,
  addMovieEpisodes,
  addMovieSource,
  listMovieSources,
  removeMovieEpisode,
  removeMovieSource,
  renameMovieSource,
  reorderMovieEpisodes,
  saveMovieSubtitle,
  updateMovieEpisode,
} from "./movieSources";
import {
  createCustomMovie,
  customMovieSources,
  getCustomMovieById,
  listCustomMovies,
  removeCustomMovie,
  importMovieImageFromUrl,
  saveMovieImage,
  updateCustomMovie,
} from "./customMovies";
import { actorSearchStatus, searchActors } from "./actorSearch";
import { fetchMovieCredits } from "./movieCredits";
import { createTvStream, deleteTvStream, listTvStreams, saveTvPoster, saveTvSubtitle, updateTvStream } from "./tvStreams";
import { createTvVideo, deleteTvVideo, listTvVideos, updateTvVideo } from "./tvVideos";
import { approveQrLogin, completeQrLogin, createQrLoginChallenge, qrLoginStatus } from "./qrLogin";
import { enforceRateLimit, SECURITY_LIMITS } from "./securityRateLimit";
import { commentRevision, publishAllComments, publishComments, waitForComments } from "./commentFeed";
import { createMovieRequest, listAllMovieRequests, listMovieRequestsForUser, updateMovieRequest, MOVIE_REQUEST_STATUSES, type MovieRequestStatus } from "./movieRequests";

const pageInput = z.number().int().min(1).max(MAX_CINEMA_PAGE).optional();
const slugInput = z.string().trim().min(2).max(120).regex(/^[a-z0-9-]+$/i);
// Id bình luận đến từ app dưới dạng chuỗi, nhưng vẫn nhận cả số cho tiện thử nghiệm.
const commentIdInput = z.union([z.string(), z.number()]);

/** Nhãn hiển thị: chữ có màu/hiệu ứng, hoặc ảnh/GIF nhỏ. */
const badgeInput = z.object({
  id: z.string().trim().max(40).optional().default(""),
  type: z.enum(["text", "image"]).optional().default("text"),
  text: z.string().trim().max(24).optional().default(""),
  imageUrl: z.string().trim().max(600).optional().default(""),
  color: z.string().trim().max(24).optional().default(""),
  background: z.string().trim().max(60).optional().default(""),
  style: z.enum(["solid", "gradient", "outline", "glow", "shine", "pulse", "neon", "gold", "hologram"]).optional().default("solid"),
  font: z.enum(["sans", "serif", "mono", "script"]).optional().default("sans"),
  size: z.enum(["sm", "md", "lg"]).optional().default("md"),
  animation: z.enum(["none", "pulse", "shine", "float", "bounce", "tilt", "blink"]).optional().default("none"),
});

/** Kiểu chữ tên người dùng: màu và hiệu ứng làm nổi bật. */
const nameStyleInput = z.object({
  color: z.string().trim().max(24).optional().default(""),
  effect: z.enum(["none", "glow", "gradient", "shine", "rainbow", "outline", "neon", "gold", "ice", "fire", "shadow", "underline", "breathe"]).optional().default("none"),
});

/** Chuẩn hoá danh sách nhãn trước khi lưu: bỏ nhãn rỗng, giới hạn số lượng. */
function normalizeBadges(badges: Array<z.infer<typeof badgeInput>>) {
  return badges
    .map((badge, index) => ({
      id: badge.id && badge.id.length > 0 ? badge.id : `b${index + 1}`,
      type: badge.type,
      text: badge.text.trim(),
      imageUrl: badge.imageUrl.trim(),
      color: badge.color.trim(),
      background: badge.background.trim(),
      style: badge.style,
      font: badge.font,
      size: badge.size,
      animation: badge.animation,
    }))
    .filter((badge) => (badge.type === "image" ? badge.imageUrl.length > 0 : badge.text.length > 0))
    .slice(0, 6);
}
/** Rút gọn người đang xem thành thông tin cần cho danh sách bình luận. */
function viewerOf(user: { id: number; role?: string | null } | null | undefined) {
  if (!user) return null;
  return { id: user.id, isAdmin: user.role === "admin" };
}

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

const movieTagInput = z.object({
  name: z.string().trim().min(1).max(120),
  slug: z.string().trim().max(120).optional(),
});

const movieEpisodeQualityInput = z.object({
  label: z.string().trim().max(40).optional(),
  streamUrl: z.string().trim().url().max(2000),
  subtitleUrl: z.string().trim().max(2000).nullable().optional(),
  subtitleVtt: z.string().max(4_000_000).nullable().optional(),
  subtitleTracks: z.array(z.object({
    language: z.string().trim().min(1).max(40),
    subtitleUrl: z.string().trim().max(2000).nullable().optional(),
    subtitleVtt: z.string().max(4_000_000).nullable().optional(),
  })).max(20).optional(),
});

const movieEpisodeQualities = z.array(movieEpisodeQualityInput).max(20).optional();

/**
 * Trường của phim thêm thủ công.
 *
 * Dùng chung cho tạo mới và sửa nên trang quản trị chỉ cần một biểu mẫu.
 */
const customMovieForm = z.object({
  name: z.string().trim().min(1).max(200),
  slug: z.string().trim().max(200).nullable().optional(),
  originName: z.string().trim().max(200).nullable().optional(),
  alternativeNames: z.array(z.string().trim().max(200)).max(30).optional(),
  episodeCurrent: z.string().trim().max(80).nullable().optional(),
  episodeTotal: z.number().int().min(0).max(20_000).nullable().optional(),
  createdDate: z.string().trim().max(40).nullable().optional(),
  updatedDate: z.string().trim().max(40).nullable().optional(),
  tmdbId: z.string().trim().max(40).nullable().optional(),
  imdbId: z.string().trim().max(40).nullable().optional(),
  categories: z.array(movieTagInput).max(30).optional(),
  countries: z.array(movieTagInput).max(30).optional(),
  rating: z.string().trim().max(20).nullable().optional(),
  viewsMode: z.enum(["real", "mixed"]).optional(),
  viewsBase: z.number().int().min(0).max(1_000_000_000).optional(),
  posterUrl: z.string().trim().max(2000).nullable().optional(),
  thumbUrl: z.string().trim().max(2000).nullable().optional(),
  description: z.string().max(20_000).nullable().optional(),
  quality: z.string().trim().max(40).nullable().optional(),
  year: z.number().int().min(1900).max(2100).nullable().optional(),
  lang: z.string().trim().max(60).nullable().optional(),
  time: z.string().trim().max(40).nullable().optional(),
  status: z.string().trim().max(60).nullable().optional(),
  movieType: z.enum(["series", "single"]).optional(),
  actors: z.array(z.object({
    name: z.string().trim().min(1).max(160),
    role: z.string().trim().max(160).nullable().optional(),
    image: z.string().trim().max(2000).nullable().optional(),
  })).max(60).optional(),
  directors: z.array(z.string().trim().max(120)).max(20).optional(),
  isPublished: z.boolean().optional(),
});

export const appRouter = router({
  system: systemRouter,
  auth: router({
    me: publicProcedure.query(opts => opts.ctx.user),
    register: publicProcedure.input(z.object({ name: z.string().trim().min(2).max(80), email: emailInput, password: passwordInput, deviceId: z.string().trim().max(160).optional(), deviceName: z.string().trim().max(160).optional() })).mutation(async ({ ctx, input }) => {
      // Web đã bỏ phần đăng ký; đặt ALLOW_REGISTRATION=false trong biến môi trường để
      // khoá hoàn toàn việc tạo tài khoản mới (kể cả qua API của ứng dụng).
      if ((process.env.ALLOW_REGISTRATION || "true").trim().toLowerCase() === "false") {
        throw new TRPCError({ code: "FORBIDDEN", message: "Hệ thống đang tắt đăng ký. Vui lòng liên hệ quản trị viên." });
      }
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
      // Lọc nhiều lựa chọn: gửi kèm mảng để gộp kết quả của nhiều tổ hợp.
      kinds: z.array(z.string().trim().max(40)).max(6).optional(),
      categories: z.array(z.string().trim().max(80)).max(6).optional(),
      countries: z.array(z.string().trim().max(80)).max(6).optional(),
      years: z.array(z.number().int().min(1900).max(2100)).max(6).optional(),
    })).query(({ input }) => getMovies(input)),
    search: publicProcedure.input(z.object({ keyword: z.string().trim().min(2).max(80), page: pageInput })).query(({ input }) => searchMovies(input)),
    detail: publicProcedure.input(z.object({ slug: slugInput })).query(({ input }) => getMovieDetail(input.slug)),
    dailyUpdates: publicProcedure.input(z.object({ page: pageInput }).optional()).query(({ input }) => getDailyUpdates(input?.page)),
    meta: publicProcedure.query(() => getCatalogMeta()),
    // Đếm số phim cho từng lựa chọn lọc (thể loại / quốc gia / năm) theo bộ lọc đang bật.
    filterCounts: publicProcedure
      .input(
        z.object({
          kind: z.string().trim().max(40).optional(),
          kinds: z.array(z.string().trim().max(40)).max(6).optional(),
          category: z.string().trim().max(80).optional(),
          country: z.string().trim().max(80).optional(),
          year: z.number().int().min(1900).max(2100).optional(),
          categories: z.array(z.string().trim().max(80)).max(6).optional(),
          countries: z.array(z.string().trim().max(80)).max(6).optional(),
          years: z.array(z.number().int().min(1900).max(2100)).max(6).optional(),
          dimension: z.enum(["categories", "countries", "years"]),
          options: z.array(z.string().trim().min(1).max(80)).max(40),
        })
      )
      .query(({ input }) => getFilterCounts(input as Parameters<typeof getFilterCounts>[0])),

    // Bình luận của phim: khách đọc được, chỉ thành viên đã đăng nhập mới gửi được.
    comments: publicProcedure
      .input(z.object({ slug: slugInput }))
      .query(async ({ ctx, input }) => ({
        items: await listMovieComments(input.slug, viewerOf(ctx.user)),
        revision: commentRevision(input.slug),
      })),

    // Giữ kết nối tối đa 25 giây và trả về ngay khi phim có bình luận mới, nhờ vậy
    // app và website thấy bình luận của người khác gần như tức thì.
    watchComments: publicProcedure
      .input(z.object({ slug: slugInput, since: z.number().int().min(0).default(0) }))
      .query(async ({ ctx, input }) => {
        const waited = await waitForComments(input.slug, input.since, 25_000);
        if (!waited.changed) return { revision: waited.revision, items: null, changed: false };
        return {
          revision: waited.revision,
          items: await listMovieComments(input.slug, viewerOf(ctx.user)),
          changed: true,
        };
      }),

    // Ghim bình luận lên đầu danh sách (chỉ quản trị viên).
    pinComment: adminProcedure
      .input(z.object({ slug: slugInput, id: commentIdInput, pinned: z.boolean() }))
      .mutation(async ({ input }) => {
        const id = toCommentId(input.id);
        if (!id) throw new TRPCError({ code: "BAD_REQUEST", message: "Bình luận không hợp lệ." });
        const existing = await findMovieComment(id);
        if (!existing || existing.movieSlug !== input.slug) {
          throw new TRPCError({ code: "NOT_FOUND", message: "Bình luận không còn tồn tại." });
        }
        await pinMovieComment({ id, pinned: input.pinned });
        publishComments(input.slug);
        return { success: true } as const;
      }),

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
        }, viewerOf(ctx.user));
        publishComments(input.slug);
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
        publishComments(input.slug);
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
        let posterUrl: string | null = null;
        if (input.imageBase64) {
          posterUrl = (await saveMovieImage({
            base64: input.imageBase64,
            mimeType: input.imageMimeType,
            filename: "movie-request-poster",
          })).url;
        }
        const requesterName = ctx.user?.name?.trim() || (ctx.user?.email ? ctx.user.email.split("@")[0] : null);
        const request = await createMovieRequest({
          userId: ctx.user?.id ?? null,
          requesterName,
          requesterEmail: ctx.user?.email ?? null,
          title: input.title,
          link: input.link,
          priority: input.priority,
          notes: input.notes,
          posterUrl,
        });
        let telegramSent = false;
        try {
          await sendMovieRequestToTelegram(input);
          telegramSent = true;
        } catch (error) {
          // Yêu cầu đã lưu thành công trong trang quản trị; Telegram chỉ là kênh báo phụ.
          console.warn("[MovieRequest] Telegram notification failed:", error instanceof Error ? error.message : error);
        }
        return { success: true, requestId: request.id, telegramSent } as const;
      } catch (error) {
        movieRequestCooldown.delete(key);
        throw error;
      }
    }),
    myRequests: protectedProcedure.query(({ ctx }) => listMovieRequestsForUser(ctx.user.id)),
  }),
  movieRequests: router({
    list: adminProcedure.query(() => listAllMovieRequests()),
    update: adminProcedure.input(z.object({
      id: z.number().int().positive(),
      status: z.enum(MOVIE_REQUEST_STATUSES),
      adminMessage: z.string().trim().max(4000).optional(),
    }).superRefine((input, ctx) => {
      if (input.status === "other" && !input.adminMessage?.trim()) {
        ctx.addIssue({ code: "custom", path: ["adminMessage"], message: "Vui lòng nhập nội dung gửi đến người dùng khi chọn Khác." });
      }
    })).mutation(({ input }) => updateMovieRequest(input.id, {
      status: input.status as MovieRequestStatus,
      adminMessage: input.adminMessage,
    })),
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
    // Ảnh đại diện: app gửi lên dạng data URL base64 đã thu nhỏ sẵn.
    setAvatar: protectedProcedure
      .input(z.object({
        dataUrl: z.string().min(32).max(400_000).regex(/^data:image\/(png|jpe?g|webp);base64,[A-Za-z0-9+/=]+$/, "Ảnh không hợp lệ."),
      }))
      .mutation(async ({ ctx, input }) => {
        enforceRateLimit(ctx.req, "account.setAvatar", 12, 60_000, String(ctx.user.id));
        await setUserAvatar(ctx.user.id, input.dataUrl);
        return { success: true } as const;
      }),
    clearAvatar: protectedProcedure.mutation(async ({ ctx }) => {
      await setUserAvatar(ctx.user.id, null);
      return { success: true } as const;
    }),
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
  // Phim admin thêm thủ công bằng link (chỉ admin).
  customMovies: router({
    list: adminProcedure.query(() => listCustomMovies()),
    get: adminProcedure
      .input(z.object({ id: z.number().int().positive() }))
      .query(async ({ input }) => {
        const row = await getCustomMovieById(input.id);
        if (!row) throw new TRPCError({ code: "NOT_FOUND", message: "Không tìm thấy phim này." });
        return { ...row, sources: await customMovieSources(row.slug) };
      }),
    create: adminProcedure.input(customMovieForm).mutation(({ input }) => createCustomMovie(input)),
    update: adminProcedure
      .input(customMovieForm.extend({ id: z.number().int().positive() }))
      .mutation(({ input }) => {
        const { id, ...rest } = input;
        return updateCustomMovie(id, rest);
      }),
    remove: adminProcedure
      .input(z.object({ id: z.number().int().positive() }))
      .mutation(({ input }) => removeCustomMovie(input.id)),
    // Ảnh poster / thumbnail / diễn viên: nhận base64 đã cắt sẵn từ trình sửa ảnh.
    uploadImage: adminProcedure
      .input(z.object({
        base64: z.string().min(1).max(12_000_000),
        filename: z.string().max(180).optional(),
        mimeType: z.string().max(60).optional(),
      }))
      .mutation(({ input }) => saveMovieImage(input)),
    // Dán link ảnh: tải về máy chủ để xem trước và cắt ảnh luôn hoạt động.
    importImage: adminProcedure
      .input(z.object({ url: z.string().min(4).max(2000) }))
      .mutation(({ input }) => importMovieImageFromUrl({ url: input.url })),
    // Tìm diễn viên từ TMDB (hoặc Wikidata) để thêm nhanh kèm ảnh.
    searchActors: adminProcedure
      .input(z.object({
        query: z.string().trim().min(2).max(80),
        limit: z.number().int().min(1).max(20).optional(),
      }))
      .mutation(({ input }) => searchActors(input)),
    // Lấy diễn viên + đạo diễn theo TMDB ID hoặc IMDB ID của phim.
    fetchCredits: adminProcedure
      .input(z.object({
        tmdbId: z.string().trim().max(40).nullable().optional(),
        imdbId: z.string().trim().max(40).nullable().optional(),
        limit: z.number().int().min(1).max(60).optional(),
        movieType: z.enum(["series", "single"]).nullable().optional(),
        title: z.string().trim().max(200).nullable().optional(),
      }))
      .mutation(({ input }) => fetchMovieCredits(input)),
    // Kiểm tra khoá TMDB và kết nối ra ngoài của máy chủ (admin).
    actorSearchStatus: adminProcedure.mutation(() => actorSearchStatus()),
    // Khoá TMDB cho trang quản trị (chỉ admin): dùng khi máy chủ hosting không gọi được TMDB.
    actorSearchCredentials: adminProcedure.mutation(() => ({
      tmdbKey: (process.env.TMDB_API_KEY || process.env.TMDB_ACCESS_TOKEN || "").trim(),
    })),
  }),

  // Nguồn và tập do admin thêm cho phim API (chỉ admin).
  movieSources: router({
    list: adminProcedure
      .input(z.object({ slug: z.string().trim().min(1).max(200) }))
      .query(({ input }) => listMovieSources(input.slug)),
    addSource: adminProcedure
      .input(z.object({ slug: z.string().trim().min(1).max(200), name: z.string().trim().min(1).max(120) }))
      .mutation(({ input }) => addMovieSource(input.slug, input.name)),
    renameSource: adminProcedure
      .input(z.object({ id: z.number().int().positive(), name: z.string().trim().min(1).max(120) }))
      .mutation(({ input }) => renameMovieSource(input.id, input.name)),
    removeSource: adminProcedure
      .input(z.object({ id: z.number().int().positive() }))
      .mutation(({ input }) => removeMovieSource(input.id)),
    addEpisode: adminProcedure
      .input(z.object({
        sourceId: z.number().int().positive(),
        name: z.string().trim().min(1).max(180),
        streamUrl: z.string().trim().url().max(2000),
        subtitleUrl: z.string().trim().max(2000).nullable().optional(),
        subtitleVtt: z.string().max(4_000_000).nullable().optional(),
        qualities: movieEpisodeQualities,
      }))
      .mutation(({ input }) => addMovieEpisode(input)),
    addEpisodes: adminProcedure
      .input(z.object({
        sourceId: z.number().int().positive(),
        episodes: z
          .array(
            z.object({
              name: z.string().trim().min(1).max(180),
              streamUrl: z.string().trim().url().max(2000),
              subtitleUrl: z.string().trim().max(2000).nullable().optional(),
              subtitleVtt: z.string().max(4_000_000).nullable().optional(),
            }),
          )
          .min(1)
          .max(2000),
      }))
      .mutation(({ input }) => addMovieEpisodes(input)),
    updateEpisode: adminProcedure
      .input(z.object({
        id: z.number().int().positive(),
        name: z.string().trim().min(1).max(180).optional(),
        streamUrl: z.string().trim().url().max(2000).optional(),
        subtitleUrl: z.string().trim().max(2000).nullable().optional(),
        subtitleVtt: z.string().max(4_000_000).nullable().optional(),
        qualities: movieEpisodeQualities,
      }))
      .mutation(({ input }) => {
        const { id, ...rest } = input;
        return updateMovieEpisode(id, rest);
      }),
    removeEpisode: adminProcedure
      .input(z.object({ id: z.number().int().positive() }))
      .mutation(({ input }) => removeMovieEpisode(input.id)),
    reorderEpisodes: adminProcedure
      .input(z.object({ sourceId: z.number().int().positive(), ids: z.array(z.number().int().positive()).max(5000) }))
      .mutation(({ input }) => reorderMovieEpisodes(input.sourceId, input.ids)),
    uploadSubtitle: adminProcedure
      .input(z.object({ base64: z.string().min(1).max(28_000_000), filename: z.string().max(180).optional() }))
      .mutation(({ input }) => saveMovieSubtitle(input)),
  }),

  adminAccounts: router({
    list: adminProcedure.query(() => listAllAccountSummaries()),
    // Nhãn tuỳ chỉnh hiện cạnh tên khi bình luận, ví dụ "VIP". Chuỗi rỗng là xoá nhãn.
    setBadge: adminProcedure
      .input(z.object({ userId: z.number().int().positive(), badge: z.string().trim().max(24).optional().default("") }))
      .mutation(async ({ input }) => {
        await setUserBadge(input.userId, input.badge.length > 0 ? input.badge : null);
        publishAllComments();
        return { success: true } as const;
      }),

    // Nhiều nhãn cho một tài khoản: chữ có màu/hiệu ứng hoặc ảnh, GIF nhỏ.
    setBadges: adminProcedure
      .input(z.object({ userId: z.number().int().positive(), badges: z.array(badgeInput).max(6).default([]) }))
      .mutation(async ({ input }) => {
        const badges = normalizeBadges(input.badges);
        // Giữ cột `badge` cũ đồng bộ để bản app chưa cập nhật vẫn hiện được nhãn đầu tiên.
        const legacy = badges.find((badge) => badge.type === "text" && badge.text.length > 0)?.text ?? null;
        await setUserBadges(input.userId, badges.length > 0 ? JSON.stringify(badges) : null, legacy);
        publishAllComments();
        return { success: true, badges } as const;
      }),

    // Màu và hiệu ứng làm nổi bật tên người dùng khi bình luận.
    setNameStyle: adminProcedure
      .input(z.object({ userId: z.number().int().positive(), nameStyle: nameStyleInput }))
      .mutation(async ({ input }) => {
        const style = {
          color: input.nameStyle.color.trim(),
          effect: input.nameStyle.effect,
        };
        const isEmpty = style.color.length === 0 && style.effect === "none";
        await setUserNameStyle(input.userId, isEmpty ? null : JSON.stringify(style));
        publishAllComments();
        return { success: true } as const;
      }),

    // Quản trị viên xem, đổi hoặc xoá ảnh đại diện của một tài khoản.
    setAvatar: adminProcedure
      .input(z.object({ userId: z.number().int().positive(), avatar: z.string().trim().min(16).max(2_800_000) }))
      .mutation(async ({ input }) => {
        if (!input.avatar.startsWith("data:image/") && !input.avatar.startsWith("/uploads/") && !/^https?:\/\//i.test(input.avatar)) {
          throw new TRPCError({ code: "BAD_REQUEST", message: "Ảnh đại diện không hợp lệ." });
        }
        await setUserAvatar(input.userId, input.avatar);
        publishAllComments();
        return { success: true } as const;
      }),

    clearAvatar: adminProcedure
      .input(z.object({ userId: z.number().int().positive() }))
      .mutation(async ({ input }) => {
        await setUserAvatar(input.userId, null);
        publishAllComments();
        return { success: true } as const;
      }),
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
