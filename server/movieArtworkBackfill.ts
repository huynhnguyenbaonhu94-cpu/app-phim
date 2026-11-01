import { createHash, randomUUID } from "node:crypto";
import { and, asc, count, desc, eq, inArray, sql } from "drizzle-orm";
import { getDb } from "./db";
import { checkR2Connection } from "./r2Backup";
import { mirrorMovieArtwork } from "./movieArtwork";
import {
  getMovieArtworkPage,
  MOVIE_ARTWORK_BACKFILL_KINDS,
  type MovieArtworkBackfillKind,
} from "./cinema";
import { r2PosterBackfillItems, r2PosterBackfillState } from "../drizzle/schema";

const STATE_ID = 1;
const LEASE_MS = 3 * 60_000;
const RECOVERY_INTERVAL_MS = 30_000;
const PAGE_DELAY_MS = 160;
const ITEM_BATCH_SIZE = 2;
const R2_FAILURE_CHECK_THRESHOLD = 6;

type RunState = typeof r2PosterBackfillState.$inferSelect;
type BackfillItem = typeof r2PosterBackfillItems.$inferSelect;

let ensureSchemaPromise: Promise<void> | null = null;
let workerPromise: Promise<void> | null = null;
let queuedWorkerToken: string | null = null;
let recoveryTimer: NodeJS.Timeout | null = null;

const activeStatuses = new Set(["running", "paused"]);
const validStatuses = new Set(["idle", "running", "paused", "completed", "completed_with_errors", "failed"]);

function leaseExpiry() {
  return new Date(Date.now() + LEASE_MS);
}

function hashSource(sourceUrl: string) {
  return createHash("sha256").update(new URL(sourceUrl).toString()).digest("hex");
}

function safeWorkerError(error: unknown) {
  const raw = error instanceof Error ? error.message : String(error || "unknown");
  const withoutUrls = raw.replace(/https?:\/\/[^\s)]+/gi, "[nguồn]").replace(/[\r\n\t]+/g, " ").trim();
  return (withoutUrls || "Lỗi xử lý backfill.").slice(0, 500);
}

function resultHeader(result: unknown): { affectedRows?: number } {
  if (Array.isArray(result)) return (result[0] || {}) as { affectedRows?: number };
  return (result || {}) as { affectedRows?: number };
}

async function ensurePosterBackfillSchema() {
  if (!ensureSchemaPromise) {
    ensureSchemaPromise = (async () => {
      const db = await getDb();
      if (!db) throw new Error("Database chưa kết nối; không thể lưu tiến trình backfill.");
      await db.execute(sql.raw(`CREATE TABLE IF NOT EXISTS r2_poster_backfill_state (
        id int NOT NULL PRIMARY KEY,
        status varchar(32) NOT NULL DEFAULT 'idle',
        phase varchar(32) NOT NULL DEFAULT 'discovering',
        catalogIndex int NOT NULL DEFAULT 0,
        currentPage int NOT NULL DEFAULT 1,
        currentKindTotalPages int NOT NULL DEFAULT 0,
        pagesTotal int NOT NULL DEFAULT 0,
        pagesCompleted int NOT NULL DEFAULT 0,
        itemsTotal int NOT NULL DEFAULT 0,
        currentKind varchar(40) NULL,
        currentItemName varchar(255) NULL,
        lastError text NULL,
        workerToken varchar(64) NULL,
        leaseExpiresAt timestamp NULL,
        startedAt timestamp NULL,
        completedAt timestamp NULL,
        heartbeatAt timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updatedAt timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
      ) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`));
      await db.execute(sql.raw(`CREATE TABLE IF NOT EXISTS r2_poster_backfill_items (
        id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
        sourceHash varchar(64) NOT NULL UNIQUE,
        sourceUrl text NOT NULL,
        sourceType varchar(20) NOT NULL,
        movieSlug varchar(200) NULL,
        movieName varchar(255) NULL,
        status varchar(20) NOT NULL DEFAULT 'pending',
        attempts int NOT NULL DEFAULT 0,
        workerToken varchar(64) NULL,
        lastError text NULL,
        createdAt timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updatedAt timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        completedAt timestamp NULL,
        INDEX r2_poster_backfill_status_id_idx (status, id)
      ) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`));
      await db.insert(r2PosterBackfillState).values({ id: STATE_ID }).onDuplicateKeyUpdate({ set: { id: STATE_ID } });
    })();
  }
  try {
    await ensureSchemaPromise;
  } catch (error) {
    ensureSchemaPromise = null;
    throw error;
  }
}

async function database() {
  await ensurePosterBackfillSchema();
  const db = await getDb();
  if (!db) throw new Error("Database chưa kết nối; không thể đọc tiến trình backfill.");
  return db;
}

async function readState(db: Awaited<ReturnType<typeof getDb>>): Promise<RunState | null> {
  if (!db) return null;
  const rows = await db.select().from(r2PosterBackfillState).where(eq(r2PosterBackfillState.id, STATE_ID)).limit(1);
  return rows[0] ?? null;
}

function statusText(status: string) {
  return validStatuses.has(status) ? status : "failed";
}

export async function getPosterBackfillStatus() {
  const db = await database();
  const [state, groupedCounts, failures] = await Promise.all([
    readState(db),
    db.select({ status: r2PosterBackfillItems.status, total: count() }).from(r2PosterBackfillItems).groupBy(r2PosterBackfillItems.status),
    db.select({ id: r2PosterBackfillItems.id, sourceType: r2PosterBackfillItems.sourceType, movieSlug: r2PosterBackfillItems.movieSlug, movieName: r2PosterBackfillItems.movieName, attempts: r2PosterBackfillItems.attempts, lastError: r2PosterBackfillItems.lastError, updatedAt: r2PosterBackfillItems.updatedAt }).from(r2PosterBackfillItems).where(eq(r2PosterBackfillItems.status, "failed")).orderBy(desc(r2PosterBackfillItems.updatedAt)).limit(8),
  ]);
  const counts = { pending: 0, running: 0, succeeded: 0, failed: 0 };
  for (const row of groupedCounts) {
    const key = row.status as keyof typeof counts;
    if (key in counts) counts[key] = Number(row.total) || 0;
  }
  const run = state ? {
    status: statusText(state.status),
    phase: state.phase,
    catalogIndex: state.catalogIndex,
    currentPage: state.currentPage,
    currentKindTotalPages: state.currentKindTotalPages,
    pagesTotal: state.pagesTotal,
    pagesCompleted: state.pagesCompleted,
    itemsTotal: state.itemsTotal,
    currentKind: state.currentKind,
    currentKindLabel: MOVIE_ARTWORK_BACKFILL_KINDS.find((entry) => entry.kind === state.currentKind)?.label ?? null,
    currentItemName: state.currentItemName,
    lastError: state.lastError,
    startedAt: state.startedAt,
    completedAt: state.completedAt,
    heartbeatAt: state.heartbeatAt,
    updatedAt: state.updatedAt,
    pageProgress: state.pagesTotal > 0 ? Math.min(100, Math.floor((state.pagesCompleted / state.pagesTotal) * 100)) : null,
    imageProgress: state.itemsTotal > 0 ? Math.min(100, Math.floor(((counts.succeeded + counts.failed) / state.itemsTotal) * 100)) : 0,
  } : null;
  return {
    run,
    counts: { ...counts, total: state?.itemsTotal ?? 0, processed: counts.succeeded + counts.failed },
    failureSamples: failures,
  };
}

async function assertR2Ready() {
  const result = await checkR2Connection();
  if (!result.ok || result.backend !== "r2") throw new Error("Không xác nhận được kết nối R2; backfill chưa được khởi chạy.");
}

function launchWorker(token: string) {
  if (workerPromise) {
    queuedWorkerToken = token;
    return;
  }
  workerPromise = runWorker(token)
    .catch(async (error) => {
      console.error("[R2 poster backfill] Worker stopped:", safeWorkerError(error));
      await pauseWorkerAfterError(token, "Worker gặp lỗi hệ thống. Có thể tiếp tục để thử lại từ checkpoint đã lưu.");
    })
    .finally(() => {
      workerPromise = null;
      const nextToken = queuedWorkerToken;
      queuedWorkerToken = null;
      if (nextToken) launchWorker(nextToken);
    });
}

async function getCurrentRunningState(token: string) {
  const db = await database();
  const state = await readState(db);
  if (!state || state.status !== "running" || state.workerToken !== token) return null;
  return { db, state };
}

async function extendLease(token: string, currentItemName?: string | null) {
  const db = await database();
  const values: Partial<RunState> = { heartbeatAt: new Date(), leaseExpiresAt: leaseExpiry() };
  if (currentItemName !== undefined) values.currentItemName = currentItemName;
  await db.update(r2PosterBackfillState).set(values).where(and(
    eq(r2PosterBackfillState.id, STATE_ID),
    eq(r2PosterBackfillState.status, "running"),
    eq(r2PosterBackfillState.workerToken, token),
  ));
}

async function pauseWorkerAfterError(token: string, message: string) {
  try {
    const db = await database();
    await db.transaction(async (tx) => {
      const rows = await tx.select().from(r2PosterBackfillState).where(eq(r2PosterBackfillState.id, STATE_ID)).for("update");
      const state = rows[0];
      if (!state || state.status !== "running" || state.workerToken !== token) return;
      await tx.update(r2PosterBackfillItems).set({ status: "pending", workerToken: null }).where(and(eq(r2PosterBackfillItems.status, "running"), eq(r2PosterBackfillItems.workerToken, token)));
      await tx.update(r2PosterBackfillState).set({ status: "paused", lastError: message.slice(0, 500), currentItemName: null, workerToken: null, leaseExpiresAt: null, heartbeatAt: new Date() }).where(eq(r2PosterBackfillState.id, STATE_ID));
    });
  } catch (updateError) {
    console.warn("[R2 poster backfill] Could not persist paused state:", updateError instanceof Error ? updateError.message : updateError);
  }
}

async function insertCandidatesAndAdvance(
  token: string,
  state: RunState,
  kind: MovieArtworkBackfillKind,
  pageResult: Awaited<ReturnType<typeof getMovieArtworkPage>>,
) {
  const db = await database();
  const unique = new Map<string, (typeof pageResult.candidates)[number]>();
  for (const candidate of pageResult.candidates) {
    try { unique.set(hashSource(candidate.sourceUrl), candidate); } catch { /* Invalid source URL is ignored. */ }
  }
  const candidateEntries = Array.from(unique.entries());
  const reportedTotalPages = pageResult.totalPages || state.currentKindTotalPages || 0;
  const pageLimit = reportedTotalPages > 0 ? reportedTotalPages : 0;
  const reachedEnd = pageLimit > 0
    ? state.currentPage >= pageLimit
    : pageResult.itemCount < 24 || state.currentPage >= 2_000;
  const nextCatalogIndex = reachedEnd ? state.catalogIndex + 1 : state.catalogIndex;
  const nextKind = MOVIE_ARTWORK_BACKFILL_KINDS[nextCatalogIndex];
  const nextPage = reachedEnd ? 1 : state.currentPage + 1;
  const insertedCount = await db.transaction(async (tx) => {
    const stateRows = await tx.select().from(r2PosterBackfillState).where(eq(r2PosterBackfillState.id, STATE_ID)).for("update");
    const current = stateRows[0];
    if (!current || current.status !== "running" || current.workerToken !== token) return null;

    let added = 0;
    if (candidateEntries.length) {
      const valueRows = candidateEntries.map(([sourceHash, candidate]) => sql`(
        ${sourceHash}, ${candidate.sourceUrl}, ${candidate.sourceType}, ${candidate.movieSlug || null}, ${candidate.movieName || null}, 'pending', 0
      )`);
      const insertResult = await tx.execute(sql`INSERT IGNORE INTO r2_poster_backfill_items
        (sourceHash, sourceUrl, sourceType, movieSlug, movieName, status, attempts)
        VALUES ${sql.join(valueRows, sql`,`)}`);
      added = Number(resultHeader(insertResult).affectedRows || 0);
    }

    const totalAddition = state.currentPage === 1 && state.currentKindTotalPages === 0 && pageResult.totalPages
      ? pageResult.totalPages
      : 0;
    await tx.update(r2PosterBackfillState).set({
      catalogIndex: nextCatalogIndex,
      currentPage: nextPage,
      currentKind: nextKind?.kind ?? null,
      currentKindTotalPages: reachedEnd ? 0 : reportedTotalPages,
      pagesTotal: sql`${r2PosterBackfillState.pagesTotal} + ${totalAddition}`,
      pagesCompleted: sql`${r2PosterBackfillState.pagesCompleted} + 1`,
      itemsTotal: sql`${r2PosterBackfillState.itemsTotal} + ${added}`,
      phase: nextCatalogIndex >= MOVIE_ARTWORK_BACKFILL_KINDS.length ? "processing" : "discovering",
      lastError: null,
      heartbeatAt: new Date(),
      leaseExpiresAt: leaseExpiry(),
    }).where(eq(r2PosterBackfillState.id, STATE_ID));
    return added;
  });
  return insertedCount !== null;
}

async function processPendingBatch(token: string): Promise<{ processed: number; failed: number }> {
  const current = await getCurrentRunningState(token);
  if (!current) return { processed: 0, failed: 0 };
  const { db } = current;
  const rows = await db.select().from(r2PosterBackfillItems)
    .where(eq(r2PosterBackfillItems.status, "pending"))
    .orderBy(asc(r2PosterBackfillItems.id))
    .limit(ITEM_BATCH_SIZE);
  if (!rows.length) return { processed: 0, failed: 0 };

  const ids = rows.map((row) => row.id);
  await db.transaction(async (tx) => {
    const stateRows = await tx.select().from(r2PosterBackfillState).where(eq(r2PosterBackfillState.id, STATE_ID)).for("update");
    const state = stateRows[0];
    if (!state || state.status !== "running" || state.workerToken !== token) return;
    await tx.update(r2PosterBackfillItems).set({
      status: "running",
      attempts: sql`${r2PosterBackfillItems.attempts} + 1`,
      workerToken: token,
      lastError: null,
      completedAt: null,
    }).where(and(inArray(r2PosterBackfillItems.id, ids), eq(r2PosterBackfillItems.status, "pending")));
    await tx.update(r2PosterBackfillState).set({ currentItemName: rows[0]?.movieName || rows[0]?.movieSlug || "Ảnh catalog", heartbeatAt: new Date(), leaseExpiresAt: leaseExpiry() }).where(eq(r2PosterBackfillState.id, STATE_ID));
  });

  const claimed = await db.select().from(r2PosterBackfillItems)
    .where(and(inArray(r2PosterBackfillItems.id, ids), eq(r2PosterBackfillItems.status, "running"), eq(r2PosterBackfillItems.workerToken, token)));
  if (!claimed.length) return { processed: 0, failed: 0 };

  let failures = 0;
  await Promise.all(claimed.map(async (item: BackfillItem) => {
    let saved = false;
    try {
      const result = await mirrorMovieArtwork(item.sourceUrl);
      saved = Boolean(result?.url);
    } catch {
      saved = false;
    }
    if (!saved) failures += 1;
    const finishedAt = new Date();
    await db.update(r2PosterBackfillItems).set({
      status: saved ? "succeeded" : "failed",
      workerToken: null,
      lastError: saved ? null : "Không tải được ảnh hợp lệ từ nguồn hoặc không ghi được vào R2.",
      completedAt: finishedAt,
    }).where(and(
      eq(r2PosterBackfillItems.id, item.id),
      eq(r2PosterBackfillItems.status, "running"),
      eq(r2PosterBackfillItems.workerToken, token),
    ));
    await extendLease(token, item.movieName || item.movieSlug || "Ảnh catalog");
  }));
  return { processed: claimed.length, failed: failures };
}

async function advanceToProcessing(token: string) {
  const db = await database();
  const state = await readState(db);
  if (!state || state.status !== "running" || state.workerToken !== token) return false;
  if (state.phase !== "discovering" || state.catalogIndex < MOVIE_ARTWORK_BACKFILL_KINDS.length) return false;
  await db.update(r2PosterBackfillState).set({ phase: "processing", currentKind: null, currentPage: 1, currentKindTotalPages: 0, heartbeatAt: new Date(), leaseExpiresAt: leaseExpiry() }).where(and(
    eq(r2PosterBackfillState.id, STATE_ID), eq(r2PosterBackfillState.status, "running"), eq(r2PosterBackfillState.workerToken, token),
  ));
  return true;
}

async function finishIfDrained(token: string) {
  const db = await database();
  const state = await readState(db);
  if (!state || state.status !== "running" || state.workerToken !== token || state.phase !== "processing") return false;
  const counts = await db.select({ status: r2PosterBackfillItems.status, total: count() }).from(r2PosterBackfillItems).groupBy(r2PosterBackfillItems.status);
  const values = new Map(counts.map((row) => [row.status, Number(row.total) || 0]));
  const unsettled = (values.get("pending") || 0) + (values.get("running") || 0);
  if (unsettled > 0) return false;
  const failed = values.get("failed") || 0;
  await db.update(r2PosterBackfillState).set({
    status: failed > 0 ? "completed_with_errors" : "completed",
    currentItemName: null,
    workerToken: null,
    leaseExpiresAt: null,
    completedAt: new Date(),
    heartbeatAt: new Date(),
    lastError: failed > 0 ? `${failed} ảnh cần thử lại hoặc kiểm tra nguồn.` : null,
  }).where(and(eq(r2PosterBackfillState.id, STATE_ID), eq(r2PosterBackfillState.status, "running"), eq(r2PosterBackfillState.workerToken, token)));
  return true;
}

async function runWorker(token: string) {
  let consecutiveFailures = 0;
  while (true) {
    const current = await getCurrentRunningState(token);
    if (!current) return;
    const pending = await processPendingBatch(token);
    if (pending.processed > 0) {
      consecutiveFailures = pending.failed > 0 ? consecutiveFailures + pending.failed : 0;
      if (consecutiveFailures >= R2_FAILURE_CHECK_THRESHOLD) {
        try {
          await checkR2Connection();
          consecutiveFailures = 0;
        } catch {
          await pauseWorkerAfterError(token, "Kết nối R2 bị gián đoạn; backfill đã tạm dừng và có thể tiếp tục sau khi kiểm tra kết nối.");
          return;
        }
      }
      continue;
    }

    const fresh = await getCurrentRunningState(token);
    if (!fresh) return;
    if (fresh.state.phase === "discovering") {
      if (fresh.state.catalogIndex >= MOVIE_ARTWORK_BACKFILL_KINDS.length) {
        await advanceToProcessing(token);
        continue;
      }
      const kind = MOVIE_ARTWORK_BACKFILL_KINDS[fresh.state.catalogIndex];
      if (!kind) {
        await advanceToProcessing(token);
        continue;
      }
      await extendLease(token, null);
      try {
        const pageResult = await getMovieArtworkPage(kind.kind as MovieArtworkBackfillKind, fresh.state.currentPage);
        const advanced = await insertCandidatesAndAdvance(token, fresh.state, kind.kind, pageResult);
        if (!advanced) return;
        await new Promise((resolve) => setTimeout(resolve, PAGE_DELAY_MS));
        continue;
      } catch (error) {
        console.warn(`[R2 poster backfill] Catalog page failed (${kind.kind}, page ${fresh.state.currentPage}):`, error instanceof Error ? error.message : error);
        await pauseWorkerAfterError(token, `Không đọc được trang ${fresh.state.currentPage} của danh mục “${kind.label}”. Có thể tiếp tục để thử lại đúng trang này.`);
        return;
      }
    }

    if (fresh.state.phase === "processing") {
      if (await finishIfDrained(token)) return;
      await new Promise((resolve) => setTimeout(resolve, 400));
      continue;
    }

    await pauseWorkerAfterError(token, "Trạng thái backfill không hợp lệ. Hãy tiếp tục để worker đọc lại checkpoint.");
    return;
  }
}

async function setRunningWithNewToken(reset: boolean, r2AlreadyValidated = false, retryFailed = false) {
  const db = await database();
  if (!r2AlreadyValidated) await assertR2Ready();
  const token = randomUUID();
  await db.transaction(async (tx) => {
    const rows = await tx.select().from(r2PosterBackfillState).where(eq(r2PosterBackfillState.id, STATE_ID)).for("update");
    const state = rows[0];
    if (!state) throw new Error("Không tìm thấy trạng thái backfill trong database.");
    if (reset && activeStatuses.has(state.status)) throw new Error("Đang có backfill hoạt động hoặc đã tạm dừng. Hãy tiếp tục hoặc hoàn tất lần hiện tại trước.");
    if (!reset && !retryFailed && state.status !== "paused") throw new Error("Chỉ có thể tiếp tục khi backfill đang tạm dừng.");
    if (!reset && retryFailed && (!["completed_with_errors", "failed"].includes(state.status) || state.phase !== "processing")) {
      throw new Error("Có thể thử lại ảnh lỗi sau khi lượt quét catalog hoàn tất.");
    }
    if (reset) await tx.delete(r2PosterBackfillItems);
    if (reset) {
      await tx.update(r2PosterBackfillState).set({
        status: "running",
        phase: "discovering",
        catalogIndex: 0,
        currentPage: 1,
        currentKindTotalPages: 0,
        pagesTotal: 0,
        pagesCompleted: 0,
        itemsTotal: 0,
        currentKind: MOVIE_ARTWORK_BACKFILL_KINDS[0].kind,
        currentItemName: null,
        lastError: null,
        workerToken: token,
        leaseExpiresAt: leaseExpiry(),
        startedAt: new Date(),
        completedAt: null,
        heartbeatAt: new Date(),
      }).where(eq(r2PosterBackfillState.id, STATE_ID));
    } else {
      if (retryFailed) await tx.update(r2PosterBackfillItems).set({ status: "pending", workerToken: null, lastError: null, completedAt: null }).where(eq(r2PosterBackfillItems.status, "failed"));
      await tx.update(r2PosterBackfillItems).set({ status: "pending", workerToken: null }).where(eq(r2PosterBackfillItems.status, "running"));
      await tx.update(r2PosterBackfillState).set({ status: "running", lastError: null, workerToken: token, leaseExpiresAt: leaseExpiry(), completedAt: null, heartbeatAt: new Date() }).where(eq(r2PosterBackfillState.id, STATE_ID));
    }
  });
  launchWorker(token);
  return getPosterBackfillStatus();
}

export async function startPosterBackfill() {
  return setRunningWithNewToken(true);
}

export async function resumePosterBackfill() {
  return setRunningWithNewToken(false);
}

export async function pausePosterBackfill() {
  const db = await database();
  await db.transaction(async (tx) => {
    const rows = await tx.select().from(r2PosterBackfillState).where(eq(r2PosterBackfillState.id, STATE_ID)).for("update");
    const state = rows[0];
    if (!state || state.status !== "running") throw new Error("Không có backfill đang chạy để tạm dừng.");
    await tx.update(r2PosterBackfillItems).set({ status: "pending", workerToken: null }).where(and(eq(r2PosterBackfillItems.status, "running"), eq(r2PosterBackfillItems.workerToken, state.workerToken || "")));
    await tx.update(r2PosterBackfillState).set({ status: "paused", workerToken: null, leaseExpiresAt: null, currentItemName: null, heartbeatAt: new Date() }).where(eq(r2PosterBackfillState.id, STATE_ID));
  });
  return getPosterBackfillStatus();
}

export async function retryFailedPosterBackfill() {
  await assertR2Ready();
  return setRunningWithNewToken(false, true, true);
}

async function recoverStaleWorker() {
  const db = await database();
  const token = randomUUID();
  const recovered = await db.transaction(async (tx) => {
    const rows = await tx.select().from(r2PosterBackfillState).where(eq(r2PosterBackfillState.id, STATE_ID)).for("update");
    const state = rows[0];
    if (!state || state.status !== "running") return false;
    const leaseUntil = state.leaseExpiresAt ? new Date(state.leaseExpiresAt).getTime() : 0;
    if (leaseUntil > Date.now()) return false;
    await tx.update(r2PosterBackfillItems).set({ status: "pending", workerToken: null }).where(eq(r2PosterBackfillItems.status, "running"));
    await tx.update(r2PosterBackfillState).set({ workerToken: token, leaseExpiresAt: leaseExpiry(), heartbeatAt: new Date(), lastError: "Đã khôi phục checkpoint sau khi tiến trình máy chủ khởi động lại." }).where(eq(r2PosterBackfillState.id, STATE_ID));
    return true;
  });
  if (recovered) launchWorker(token);
}

export function startPosterBackfillRecovery() {
  if (recoveryTimer || !process.env.DATABASE_URL) return;
  recoveryTimer = setInterval(() => {
    void recoverStaleWorker().catch((error) => console.warn("[R2 poster backfill] Recovery check failed:", error instanceof Error ? error.message : error));
  }, RECOVERY_INTERVAL_MS);
  recoveryTimer.unref?.();
  void recoverStaleWorker().catch((error) => console.warn("[R2 poster backfill] Initial recovery check failed:", error instanceof Error ? error.message : error));
}
