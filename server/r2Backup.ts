import { createHash, randomUUID } from "node:crypto";
import { gzip } from "node:zlib";
import { promisify } from "node:util";
import { spawn } from "node:child_process";
import { desc, eq } from "drizzle-orm";
import { getDb } from "./db";
import { r2BackupRuns, r2Settings } from "../drizzle/schema";
import { storageBackend, storagePut, testR2Connection } from "./r2Storage";

const gzipAsync = promisify(gzip);
const SETTINGS_ID = 1;
let runningBackup: Promise<BackupResult> | null = null;
let scheduler: NodeJS.Timeout | null = null;
let lastScheduledSlot = "";

type BackupResult = {
  success: boolean;
  runId?: number;
  backupKey?: string;
  manifestKey?: string;
  bytes?: number;
  startedAt: string;
  completedAt?: string;
  error?: string;
};

function databaseParts() {
  const raw = process.env.DATABASE_URL?.trim();
  if (!raw) throw new Error("DATABASE_URL chưa được cấu hình.");
  const url = new URL(raw);
  if (!url.hostname || !url.pathname.slice(1)) throw new Error("DATABASE_URL không hợp lệ.");
  return {
    host: url.hostname,
    port: url.port || "3306",
    user: decodeURIComponent(url.username),
    password: decodeURIComponent(url.password),
    database: decodeURIComponent(url.pathname.slice(1)),
  };
}

async function dumpDatabase(): Promise<Buffer> {
  const parts = databaseParts();
  const args = ["--single-transaction", "--quick", "--routines", "--triggers", "--host", parts.host, "--port", parts.port, "--user", parts.user, parts.database];
  try {
    return await new Promise<Buffer>((resolve, reject) => {
      const child = spawn("mysqldump", args, {
        env: { ...process.env, MYSQL_PWD: parts.password },
        stdio: ["ignore", "pipe", "pipe"],
      });
      const stdoutChunks: Buffer[] = [];
      const stderrChunks: Buffer[] = [];
      const maxDumpBytes = 256 * 1024 * 1024;
      const maxStderrBytes = 64 * 1024;
      let stdoutBytes = 0;
      let stderrBytes = 0;
      let settled = false;

      const fail = (error: Error) => {
        if (settled) return;
        settled = true;
        child.kill("SIGKILL");
        reject(error);
      };

      child.stdout.on("data", (chunk: Buffer | string) => {
        const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
        stdoutBytes += bytes.length;
        if (stdoutBytes > maxDumpBytes) {
          fail(new Error("Database dump vượt giới hạn 256 MiB cho mỗi lần backup."));
          return;
        }
        stdoutChunks.push(bytes);
      });
      child.stderr.on("data", (chunk: Buffer | string) => {
        if (stderrBytes >= maxStderrBytes) return;
        const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
        const remaining = maxStderrBytes - stderrBytes;
        const kept = bytes.subarray(0, remaining);
        stderrChunks.push(kept);
        stderrBytes += kept.length;
      });
      child.once("error", (error) => {
        if (!settled) {
          settled = true;
          reject(error);
        }
      });
      child.once("close", (code, signal) => {
        if (settled) return;
        const stderrText = Buffer.concat(stderrChunks).toString("utf8").trim();
        if (code !== 0) {
          settled = true;
          reject(new Error(`mysqldump thoát với mã ${code ?? signal ?? "không xác định"}${stderrText ? `: ${stderrText}` : ". Kiểm tra quyền database và thông tin kết nối."}`));
          return;
        }
        if (stdoutBytes === 0) {
          settled = true;
          reject(new Error(`mysqldump kết thúc nhưng không xuất dữ liệu SQL${stderrText ? `: ${stderrText}` : ". Kiểm tra database có bảng và quyền SELECT/TRIGGER/SHOW VIEW."}`));
          return;
        }
        settled = true;
        resolve(Buffer.concat(stdoutChunks, stdoutBytes));
      });
    });
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    const code = error && typeof error === "object" && "code" in error ? String((error as NodeJS.ErrnoException).code || "") : "";
    if (code === "ENOENT") throw new Error("Không tìm thấy executable mysqldump trên máy chủ. Hãy cài MySQL/MariaDB client hoặc cấu hình đường dẫn mysqldump.");
    throw new Error(`Không tạo được mysqldump: ${detail}. Kiểm tra quyền truy cập database, dung lượng và cấu hình client MySQL.`);
  }
}

async function updateRun(runId: number, values: { status: string; completedAt?: Date; backupKey?: string; manifestKey?: string; byteSize?: number; errorMessage?: string | null }) {
  const db = await getDb();
  if (!db) return;
  await db.update(r2BackupRuns).set(values).where(eq(r2BackupRuns.id, runId));
}

function backupErrorText(error: unknown): string {
  if (!(error instanceof Error)) return String(error);
  const value = error as Error & { code?: unknown; Code?: unknown; $metadata?: { httpStatusCode?: unknown; requestId?: unknown } };
  const details = [
    value.name && value.name !== "Error" ? `type=${value.name}` : "",
    value.code ? `code=${String(value.code)}` : "",
    value.Code ? `serviceCode=${String(value.Code)}` : "",
    value.$metadata?.httpStatusCode ? `http=${String(value.$metadata.httpStatusCode)}` : "",
    value.$metadata?.requestId ? `requestId=${String(value.$metadata.requestId)}` : "",
  ].filter(Boolean);
  return `${value.message || value.name}${details.length ? ` [${details.join(", ")}]` : ""}`;
}

export async function runR2Backup(): Promise<BackupResult> {
  if (runningBackup) return runningBackup;
  const startedAt = new Date();
  runningBackup = (async () => {
    let runId: number | undefined;
    let currentStep = "Khởi tạo backup";
    try {
      currentStep = "Kiểm tra kết nối database";
      const db = await getDb();
      if (!db) throw new Error("Database is not available; không thể backup.");
      currentStep = "Kiểm tra cấu hình R2";
      if (await storageBackend() !== "r2") throw new Error("R2 chưa được cấu hình; backup database không được ghi vào local storage.");
      currentStep = "Tạo bản ghi trạng thái backup";
      const inserted = await db.insert(r2BackupRuns).values({ status: "running", startedAt }).$returningId();
      const newRunId = Number(inserted[0]?.id);
      if (!Number.isInteger(newRunId) || newRunId <= 0) throw new Error("Không tạo được trạng thái backup.");
      runId = newRunId;
      currentStep = "Tạo dump mysqldump";
      const sqlDump = await dumpDatabase();
      currentStep = "Nén SQL dump";
      const compressed = await gzipAsync(sqlDump, { level: 9 });
      const timestamp = startedAt.toISOString().replace(/[:.]/g, "-");
      currentStep = "Upload file backup lên R2";
      const backupObject = await storagePut(`backups/database-${timestamp}-${randomUUID()}.sql.gz`, compressed, "application/gzip");
      const digest = createHash("sha256").update(compressed).digest("hex");
      const manifest = {
        version: 1,
        type: "cinemora-database-backup",
        createdAt: startedAt.toISOString(),
        completedAt: new Date().toISOString(),
        backupKey: backupObject.key,
        contentEncoding: "gzip",
        contentType: "application/sql",
        bytes: compressed.length,
        sha256: digest,
      };
      currentStep = "Upload manifest lên R2";
      const manifestObject = await storagePut(`backups/${timestamp}-${randomUUID()}.manifest.json`, JSON.stringify(manifest, null, 2), "application/json");
      currentStep = "Cập nhật trạng thái hoàn tất";
      await updateRun(runId, { status: "completed", completedAt: new Date(), backupKey: backupObject.key, manifestKey: manifestObject.key, byteSize: compressed.length, errorMessage: null });
      return { success: true, runId, backupKey: backupObject.key, manifestKey: manifestObject.key, bytes: compressed.length, startedAt: startedAt.toISOString(), completedAt: new Date().toISOString() };
    } catch (error) {
      const message = `${currentStep}: ${backupErrorText(error)}`;
      console.error(`[R2 backup] ${message}`, error instanceof Error ? error.stack : error);
      if (runId) {
        try {
          await updateRun(runId, { status: "failed", completedAt: new Date(), errorMessage: message });
        } catch (updateError) {
          console.error("[R2 backup] Could not store failed status:", updateError);
        }
      }
      return { success: false, ...(runId ? { runId } : {}), startedAt: startedAt.toISOString(), completedAt: new Date().toISOString(), error: message };
    }
  })();
  try {
    return await runningBackup;
  } finally {
    runningBackup = null;
  }
}

export async function getBackupStatus() {
  const db = await getDb();
  if (!db) return { configured: false, latest: null };
  const settings = await db.select({ enabled: r2Settings.backupEnabled, frequency: r2Settings.backupFrequency, scheduleHourVietnam: r2Settings.scheduleHourVietnam }).from(r2Settings).where(eq(r2Settings.id, SETTINGS_ID)).limit(1);
  const latest = await db.select().from(r2BackupRuns).orderBy(desc(r2BackupRuns.id)).limit(1);
  return { configured: (await storageBackend()) === "r2", schedule: settings[0] ? { enabled: Boolean(settings[0].enabled), frequency: settings[0].frequency === "weekly" ? "weekly" : "daily", scheduleHourVietnam: settings[0].scheduleHourVietnam } : { enabled: false, frequency: "daily" as const, scheduleHourVietnam: 9 }, latest: latest[0] ?? null, running: Boolean(runningBackup) };
}

export async function checkR2Connection() {
  return testR2Connection();
}

async function scheduleSettings() {
  const db = await getDb();
  if (!db) return null;
  const rows = await db.select({ enabled: r2Settings.backupEnabled, frequency: r2Settings.backupFrequency, scheduleHourVietnam: r2Settings.scheduleHourVietnam }).from(r2Settings).where(eq(r2Settings.id, SETTINGS_ID)).limit(1);
  return rows[0] ?? null;
}

/** Vietnam is fixed GMT+7 and does not observe daylight saving time. */
export function getVietnamBackupClock(now: Date) {
  const shifted = new Date(now.getTime() + 7 * 60 * 60 * 1000);
  const year = shifted.getUTCFullYear();
  const month = shifted.getUTCMonth() + 1;
  const day = shifted.getUTCDate();
  const weekday = shifted.getUTCDay();
  const pad = (value: number) => String(value).padStart(2, "0");
  const monday = new Date(Date.UTC(year, month - 1, day - ((weekday + 6) % 7)));
  return {
    hour: shifted.getUTCHours(),
    dateKey: `${year}-${pad(month)}-${pad(day)}`,
    weekKey: monday.toISOString().slice(0, 10),
  };
}

async function maybeRunScheduledBackup() {
  if (runningBackup) return;
  const settings = await scheduleSettings();
  if (!settings?.enabled || (await storageBackend()) !== "r2") return;
  const now = getVietnamBackupClock(new Date());
  if (now.hour < Number(settings.scheduleHourVietnam ?? 9)) return;
  const slot = settings.frequency === "weekly" ? `weekly:${now.weekKey}` : `daily:${now.dateKey}`;
  if (slot === lastScheduledSlot) return;
  const db = await getDb();
  const latest = db ? await db.select({ completedAt: r2BackupRuns.completedAt }).from(r2BackupRuns).where(eq(r2BackupRuns.status, "completed")).orderBy(desc(r2BackupRuns.id)).limit(1) : [];
  const latestDate = latest[0]?.completedAt;
  if (latestDate) {
    const completed = getVietnamBackupClock(new Date(latestDate));
    const completedSlot = settings.frequency === "weekly" ? `weekly:${completed.weekKey}` : `daily:${completed.dateKey}`;
    if (completedSlot === slot) {
      lastScheduledSlot = slot;
      return;
    }
  }
  lastScheduledSlot = slot;
  void runR2Backup().catch((error) => console.warn("[R2] Scheduled backup failed:", error));
}

export function startR2BackupScheduler() {
  if (scheduler) return;
  scheduler = setInterval(() => { void maybeRunScheduledBackup(); }, 60_000);
  scheduler.unref?.();
  void maybeRunScheduledBackup();
}

export function stopR2BackupScheduler() {
  if (!scheduler) return;
  clearInterval(scheduler);
  scheduler = null;
  lastScheduledSlot = "";
}
