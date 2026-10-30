import { createHash, randomUUID } from "node:crypto";
import { gzip } from "node:zlib";
import { promisify } from "node:util";
import { execFile } from "node:child_process";
import { desc, eq } from "drizzle-orm";
import { getDb } from "./db";
import { r2BackupRuns, r2Settings } from "../drizzle/schema";
import { storageBackend, storagePut, testR2Connection } from "./r2Storage";

const gzipAsync = promisify(gzip);
const execFileAsync = promisify(execFile);
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
    const result = await execFileAsync("mysqldump", args, { env: { ...process.env, MYSQL_PWD: parts.password }, maxBuffer: 256 * 1024 * 1024 });
    return Buffer.from(result.stdout, "utf8");
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    throw new Error(`Không tạo được mysqldump: ${detail}. Cần cài mysqldump trên server để chạy backup an toàn.`);
  }
}

async function updateRun(runId: number, values: { status: string; completedAt?: Date; backupKey?: string; manifestKey?: string; byteSize?: number; errorMessage?: string | null }) {
  const db = await getDb();
  if (!db) return;
  await db.update(r2BackupRuns).set(values).where(eq(r2BackupRuns.id, runId));
}

export async function runR2Backup(): Promise<BackupResult> {
  if (runningBackup) return runningBackup;
  const startedAt = new Date();
  runningBackup = (async () => {
    const db = await getDb();
    if (!db) throw new Error("Database is not available; không thể backup.");
    if (await storageBackend() !== "r2") throw new Error("R2 chưa được cấu hình; backup database không được ghi vào local storage.");
    const inserted = await db.insert(r2BackupRuns).values({ status: "running", startedAt }).$returningId();
    const runId = Number(inserted[0]?.id);
    if (!Number.isInteger(runId) || runId <= 0) throw new Error("Không tạo được trạng thái backup.");
    try {
      const sqlDump = await dumpDatabase();
      const compressed = await gzipAsync(sqlDump, { level: 9 });
      const timestamp = startedAt.toISOString().replace(/[:.]/g, "-");
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
      const manifestObject = await storagePut(`backups/${timestamp}-${randomUUID()}.manifest.json`, JSON.stringify(manifest, null, 2), "application/json");
      await updateRun(runId, { status: "completed", completedAt: new Date(), backupKey: backupObject.key, manifestKey: manifestObject.key, byteSize: compressed.length, errorMessage: null });
      return { success: true, runId, backupKey: backupObject.key, manifestKey: manifestObject.key, bytes: compressed.length, startedAt: startedAt.toISOString(), completedAt: new Date().toISOString() };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await updateRun(runId, { status: "failed", completedAt: new Date(), errorMessage: message });
      return { success: false, runId, startedAt: startedAt.toISOString(), completedAt: new Date().toISOString(), error: message };
    }
  })().catch((error) => ({ success: false, startedAt: startedAt.toISOString(), completedAt: new Date().toISOString(), error: error instanceof Error ? error.message : String(error) }));
  try {
    return await runningBackup;
  } finally {
    runningBackup = null;
  }
}

export async function getBackupStatus() {
  const db = await getDb();
  if (!db) return { configured: false, latest: null };
  const settings = await db.select({ enabled: r2Settings.backupEnabled, frequency: r2Settings.backupFrequency, scheduleHourUtc: r2Settings.scheduleHourUtc }).from(r2Settings).where(eq(r2Settings.id, SETTINGS_ID)).limit(1);
  const latest = await db.select().from(r2BackupRuns).orderBy(desc(r2BackupRuns.id)).limit(1);
  return { configured: (await storageBackend()) === "r2", schedule: settings[0] ? { enabled: Boolean(settings[0].enabled), frequency: settings[0].frequency === "weekly" ? "weekly" : "daily", scheduleHourUtc: settings[0].scheduleHourUtc } : { enabled: false, frequency: "daily" as const, scheduleHourUtc: 2 }, latest: latest[0] ?? null, running: Boolean(runningBackup) };
}

export async function checkR2Connection() {
  return testR2Connection();
}

async function scheduleSettings() {
  const db = await getDb();
  if (!db) return null;
  const rows = await db.select({ enabled: r2Settings.backupEnabled, frequency: r2Settings.backupFrequency, scheduleHourUtc: r2Settings.scheduleHourUtc }).from(r2Settings).where(eq(r2Settings.id, SETTINGS_ID)).limit(1);
  return rows[0] ?? null;
}

async function maybeRunScheduledBackup() {
  if (runningBackup) return;
  const settings = await scheduleSettings();
  if (!settings?.enabled || (await storageBackend()) !== "r2") return;
  const now = new Date();
  if (now.getUTCHours() < Number(settings.scheduleHourUtc ?? 2)) return;
  const day = now.getUTCDay();
  const monday = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() - ((day + 6) % 7)));
  const slot = settings.frequency === "weekly" ? `weekly:${monday.toISOString().slice(0, 10)}` : `daily:${now.toISOString().slice(0, 10)}`;
  if (slot === lastScheduledSlot) return;
  const db = await getDb();
  const latest = db ? await db.select({ completedAt: r2BackupRuns.completedAt }).from(r2BackupRuns).where(eq(r2BackupRuns.status, "completed")).orderBy(desc(r2BackupRuns.id)).limit(1) : [];
  const latestDate = latest[0]?.completedAt;
  if (latestDate) {
    const completed = new Date(latestDate);
    const completedDay = completed.getUTCDay();
    const completedMonday = new Date(Date.UTC(completed.getUTCFullYear(), completed.getUTCMonth(), completed.getUTCDate() - ((completedDay + 6) % 7)));
    const completedSlot = settings.frequency === "weekly" ? `weekly:${completedMonday.toISOString().slice(0, 10)}` : `daily:${completed.toISOString().slice(0, 10)}`;
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
