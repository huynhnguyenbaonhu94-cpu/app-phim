import { getCloudflareAnalyticsCredentials } from "./r2Storage";

const GRAPHQL_ENDPOINT = "https://api.cloudflare.com/client/v4/graphql";
const OPERATIONS_LIMIT_PER_DAY = 10_000;
const STORAGE_LIMIT = 10_000;
const BANDWIDTH_LIMIT = 1_000;
const VIETNAM_OFFSET_MS = 7 * 60 * 60 * 1_000;

export type R2AnalyticsPeriod = "monthToDate" | "last7Days" | "last30Days";
type DailyWindow = { date: string; startDate: Date; endDate: Date };
type RequestedRange = { from: string; to: string };
type OperationRow = { sum?: { requests?: number | string | null } | null; dimensions?: { actionType?: string | null; actionStatus?: string | null; datetime?: string | null } | null };
type StorageRow = { max?: { objectCount?: number | string | null; uploadCount?: number | string | null; payloadSize?: number | string | null; metadataSize?: number | string | null } | null; dimensions?: { datetime?: string | null } | null };
type BandwidthRow = { sum?: { bytesUpload?: number | string | null; bytesDownload?: number | string | null } | null; dimensions?: { datetimeHour?: string | null } | null };
type AnalyticsAccount = {
  r2StorageAdaptiveGroups?: StorageRow[];
  r2BandwidthUsageAdaptiveGroups?: BandwidthRow[];
  latestOperationSample?: Array<{ dimensions?: { datetime?: string | null } | null }>;
  [key: string]: unknown;
};
type AnalyticsData = { viewer?: { accounts?: AnalyticsAccount[] } };
type DailyOperations = Array<{ date: string; rows: OperationRow[] }>;
type SummaryOptions = {
  operationDays?: DailyOperations;
  calendarDates?: string[];
  operationsLimitReached?: boolean;
  latestOperationsAt?: string | null;
};

const CLASS_A = new Set([
  "listbuckets", "putbucket", "listobjects", "listobjectsv2", "putobject", "copyobject",
  "completemultipartupload", "createmultipartupload", "lifecyclestoragetiertransition",
  "listmultipartuploads", "uploadpart", "uploadpartcopy", "listparts", "putbucketencryption",
  "putbucketcors", "putbucketlifecycleconfiguration",
]);
const CLASS_B = new Set([
  "headbucket", "headobject", "getobject", "usagesummary", "getbucketencryption",
  "getbucketlocation", "getbucketcors", "getbucketlifecycleconfiguration",
]);
const FREE_OPERATIONS = new Set(["deleteobject", "deletebucket", "abortmultipartupload"]);

function numeric(value: unknown): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function optionalNumeric(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : null;
}

function operationClass(actionType: string) {
  // Preserve numeric suffixes such as ListObjectsV2 when normalizing SDK action names.
  const normalized = actionType.replace(/[^a-z0-9]/gi, "").toLowerCase();
  if (CLASS_A.has(normalized)) return "A" as const;
  if (CLASS_B.has(normalized)) return "B" as const;
  if (FREE_OPERATIONS.has(normalized)) return "free" as const;
  return "other" as const;
}

function dayKey(value: string | null | undefined): string | null {
  if (!value) return null;
  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) return null;
  return new Date(timestamp + VIETNAM_OFFSET_MS).toISOString().slice(0, 10);
}

function latestTimestamp<T>(rows: T[], valueOf: (row: T) => string | null | undefined): string | null {
  let latest = Number.NEGATIVE_INFINITY;
  for (const row of rows) {
    const timestamp = Date.parse(valueOf(row) || "");
    if (Number.isFinite(timestamp) && timestamp > latest) latest = timestamp;
  }
  return Number.isFinite(latest) ? new Date(latest).toISOString() : null;
}

function addCalendarDays(dateKey: string, days: number) {
  const [year, month, day] = dateKey.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day + days)).toISOString().slice(0, 10);
}

function vietnamDayStart(dateKey: string) {
  const [year, month, day] = dateKey.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day) - VIETNAM_OFFSET_MS);
}

function vietnamTodayKey(now: Date) {
  return new Date(now.getTime() + VIETNAM_OFFSET_MS).toISOString().slice(0, 10);
}

export function getR2AnalyticsRange(period: R2AnalyticsPeriod, now = new Date()) {
  const today = vietnamTodayKey(now);
  const todayParts = today.split("-").map(Number);
  const calendarDaysInMonth = todayParts[2];
  const targetDays = period === "monthToDate" ? calendarDaysInMonth : period === "last7Days" ? 7 : 30;
  const startKey = period === "monthToDate"
    ? `${today.slice(0, 7)}-01`
    : addCalendarDays(today, -(targetDays - 1));
  const dailyWindows: DailyWindow[] = [];
  for (let date = startKey; date <= today; date = addCalendarDays(date, 1)) {
    const startDate = vietnamDayStart(date);
    const nextMidnight = new Date(startDate.getTime() + 24 * 60 * 60 * 1_000);
    const endDate = new Date(Math.min(nextMidnight.getTime(), now.getTime()));
    dailyWindows.push({ date, startDate, endDate });
  }
  const startDate = dailyWindows[0]?.startDate ?? vietnamDayStart(today);
  return {
    period,
    days: dailyWindows.length,
    startDate,
    endDate: new Date(now.getTime()),
    dailyWindows,
  };
}

function buildAnalyticsQuery(dayCount: number) {
  const operationVariables = Array.from({ length: dayCount }, (_, index) => `$opStart${index}: Time!, $opEnd${index}: Time!`).join(",\n    ");
  const operationQueries = Array.from({ length: dayCount }, (_, index) => `
      operationsDay${index}: r2OperationsAdaptiveGroups(
        limit: ${OPERATIONS_LIMIT_PER_DAY}
        filter: { datetime_geq: $opStart${index}, datetime_lt: $opEnd${index}, bucketName: $bucketName }
      ) {
        sum { requests }
        dimensions { actionType actionStatus }
      }`).join("");
  return `query R2BucketAnalytics($accountTag: string!, $startDate: Time!, $endDate: Time!, $bucketName: string!, ${operationVariables}) {
  viewer {
    accounts(filter: { accountTag: $accountTag }) {
      latestOperationSample: r2OperationsAdaptiveGroups(
        limit: 1
        filter: { datetime_geq: $startDate, datetime_lt: $endDate, bucketName: $bucketName }
        orderBy: [datetime_DESC]
      ) { dimensions { datetime } }
      ${operationQueries}
      r2StorageAdaptiveGroups(
        limit: ${STORAGE_LIMIT}
        filter: { datetime_geq: $startDate, datetime_lt: $endDate, bucketName: $bucketName }
        orderBy: [datetime_DESC]
      ) {
        max { objectCount uploadCount payloadSize metadataSize }
        dimensions { datetime }
      }
      r2BandwidthUsageAdaptiveGroups(
        limit: ${BANDWIDTH_LIMIT}
        filter: { datetime_geq: $startDate, datetime_lt: $endDate, bucketName: $bucketName }
        orderBy: [datetimeHour_ASC]
      ) {
        sum { bytesUpload bytesDownload }
        dimensions { datetimeHour }
      }
    }
  }
}`;
}

function operationRows(value: unknown): OperationRow[] {
  return Array.isArray(value) ? value as OperationRow[] : [];
}

export function summarizeR2Analytics(
  data: AnalyticsData,
  rangeDays: number,
  collectedAt = new Date().toISOString(),
  requestedRange?: RequestedRange,
  options: SummaryOptions = {},
) {
  const account = data.viewer?.accounts?.[0];
  if (!account) throw new Error("Cloudflare không trả dữ liệu cho tài khoản đã cấu hình.");

  const operations: Array<OperationRow & { reportDate?: string }> = options.operationDays
    ? options.operationDays.flatMap(({ date, rows }) => rows.map((row) => ({ ...row, reportDate: date })))
    : operationRows(account.r2OperationsAdaptiveGroups);
  const bandwidth = account.r2BandwidthUsageAdaptiveGroups ?? [];
  const storage = (account.r2StorageAdaptiveGroups ?? []).map((row) => {
    const timestamp = Date.parse(row.dimensions?.datetime || "");
    const payloadSize = optionalNumeric(row.max?.payloadSize);
    const metadataSize = optionalNumeric(row.max?.metadataSize);
    if (!Number.isFinite(timestamp) || payloadSize === null || metadataSize === null) return null;
    return {
      row,
      timestamp,
      date: dayKey(row.dimensions?.datetime),
      storageBytes: payloadSize + metadataSize,
      objectCount: optionalNumeric(row.max?.objectCount),
      uploadCount: optionalNumeric(row.max?.uploadCount),
    };
  }).filter((sample): sample is NonNullable<typeof sample> => sample !== null)
    .sort((a, b) => a.timestamp - b.timestamp);

  const daily = new Map<string, { date: string; classA: number; classB: number; other: number; bytesUpload: number; bytesDownload: number; storageBytes: number | null; objectCount: number | null }>();
  const day = (key: string) => {
    const existing = daily.get(key);
    if (existing) return existing;
    const created = { date: key, classA: 0, classB: 0, other: 0, bytesUpload: 0, bytesDownload: 0, storageBytes: null as number | null, objectCount: null as number | null };
    daily.set(key, created);
    return created;
  };
  for (const date of options.calendarDates ?? []) day(date);

  const distributionMap = new Map<string, { actionType: string; operationClass: "A" | "B" | "free" | "other"; requests: number }>();
  const requestStatuses = { success: 0, userError: 0, internalError: 0, unknown: 0 };
  let classATotal = 0;
  let classBTotal = 0;
  let freeOperationsTotal = 0;
  let otherOperationsTotal = 0;
  for (const row of operations) {
    const actionType = String(row.dimensions?.actionType || "Unknown").slice(0, 100);
    const count = numeric(row.sum?.requests);
    const category = operationClass(actionType);
    const key = `${category}:${actionType}`;
    const item = distributionMap.get(key) ?? { actionType, operationClass: category, requests: 0 };
    item.requests += count;
    distributionMap.set(key, item);

    const status = String(row.dimensions?.actionStatus || "").toLowerCase();
    if (status === "success") requestStatuses.success += count;
    else if (status === "usererror") requestStatuses.userError += count;
    else if (status === "internalerror") requestStatuses.internalError += count;
    else requestStatuses.unknown += count;

    const date = row.reportDate ?? dayKey(row.dimensions?.datetime);
    const bucket = date ? day(date) : null;
    if (category === "A") { classATotal += count; if (bucket) bucket.classA += count; }
    else if (category === "B") { classBTotal += count; if (bucket) bucket.classB += count; }
    else if (category === "free") freeOperationsTotal += count;
    else { otherOperationsTotal += count; if (bucket) bucket.other += count; }
  }

  let uploadBytes = 0;
  let downloadBytes = 0;
  for (const row of bandwidth) {
    const up = numeric(row.sum?.bytesUpload);
    const down = numeric(row.sum?.bytesDownload);
    uploadBytes += up;
    downloadBytes += down;
    const date = dayKey(row.dimensions?.datetimeHour);
    if (date) {
      const bucket = day(date);
      bucket.bytesUpload += up;
      bucket.bytesDownload += down;
    }
  }

  const dailyStoragePeaks = new Map<string, number>();
  for (const sample of storage) {
    if (!sample.date) continue;
    const previousPeak = dailyStoragePeaks.get(sample.date) ?? Number.NEGATIVE_INFINITY;
    if (sample.storageBytes > previousPeak) dailyStoragePeaks.set(sample.date, sample.storageBytes);
    const bucket = day(sample.date);
    bucket.storageBytes = Math.max(bucket.storageBytes ?? 0, sample.storageBytes);
    if (sample.objectCount !== null) bucket.objectCount = Math.max(bucket.objectCount ?? 0, sample.objectCount);
  }

  const latestStorage = storage.at(-1);
  const averageStorageBytes = dailyStoragePeaks.size
    ? Array.from(dailyStoragePeaks.values()).reduce((total, value) => total + value, 0) / dailyStoragePeaks.size
    : null;
  const operationLimitReached = options.operationsLimitReached ?? operations.length >= OPERATIONS_LIMIT_PER_DAY;
  const latestOperationSample = Array.isArray(account.latestOperationSample) ? account.latestOperationSample : [];

  return {
    rangeDays,
    range: { from: requestedRange?.from ?? null, to: requestedRange?.to ?? null, timezone: "Asia/Ho_Chi_Minh" },
    collectedAt,
    sourceTimestamps: {
      operations: options.latestOperationsAt ?? latestTimestamp(latestOperationSample, (row) => row.dimensions?.datetime) ?? latestTimestamp(operations, (row) => row.dimensions?.datetime),
      storage: latestStorage ? new Date(latestStorage.timestamp).toISOString() : null,
      bandwidth: latestTimestamp(bandwidth, (row) => row.dimensions?.datetimeHour),
    },
    completeness: {
      operationsLimitReached: operationLimitReached,
      storageLimitReached: (account.r2StorageAdaptiveGroups ?? []).length >= STORAGE_LIMIT,
      bandwidthLimitReached: bandwidth.length >= BANDWIDTH_LIMIT,
    },
    current: {
      storageBytes: latestStorage?.storageBytes ?? null,
      objectCount: latestStorage?.objectCount ?? null,
      pendingMultipartUploads: latestStorage?.uploadCount ?? null,
      sampleAt: latestStorage ? new Date(latestStorage.timestamp).toISOString() : null,
    },
    averages: { storageBytes: averageStorageBytes, sampledDays: dailyStoragePeaks.size },
    totals: { classA: classATotal, classB: classBTotal, freeOperations: freeOperationsTotal, otherOperations: otherOperationsTotal, requestStatuses, uploadBytes, downloadBytes },
    distribution: Array.from(distributionMap.values()).sort((a, b) => b.requests - a.requests),
    daily: Array.from(daily.values()).sort((a, b) => a.date.localeCompare(b.date)),
    note: "Đây là dữ liệu tổng hợp Cloudflare Analytics, có thể trễ và không thay thế Billing. Class A/B là số request được phân loại theo danh mục Cloudflare, không phải số tiền hoặc số request chắc chắn bị tính phí. Storage dùng GB thập phân (1 GB = 1.000.000.000 byte) để khớp cách hiển thị Cloudflare. Average storage là trung bình đỉnh dung lượng của các ngày GMT+7 có mẫu trong khoảng đã chọn.",
  };
}

export async function getR2Analytics(period: R2AnalyticsPeriod = "monthToDate") {
  const range = getR2AnalyticsRange(period);
  const credentials = await getCloudflareAnalyticsCredentials();
  if (!credentials) throw new Error("Chưa cấu hình Cloudflare Account Analytics API token hoặc chưa nhận diện được Account ID. Hãy thêm token chỉ có quyền Account Analytics:Read.");

  const startDate = range.startDate.toISOString();
  const endDate = range.endDate.toISOString();
  const variables: Record<string, string> = {
    accountTag: credentials.accountTag,
    bucketName: credentials.bucketName,
    startDate,
    endDate,
  };
  range.dailyWindows.forEach((window, index) => {
    variables[`opStart${index}`] = window.startDate.toISOString();
    variables[`opEnd${index}`] = window.endDate.toISOString();
  });

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 25_000);
  try {
    const response = await fetch(GRAPHQL_ENDPOINT, {
      method: "POST",
      cache: "no-store",
      headers: {
        authorization: `Bearer ${credentials.apiToken}`,
        "content-type": "application/json",
        accept: "application/json",
        "cache-control": "no-cache",
      },
      body: JSON.stringify({ query: buildAnalyticsQuery(range.dailyWindows.length), variables }),
      signal: controller.signal,
    });
    let payload: { data?: AnalyticsData; errors?: Array<{ message?: string }> };
    try { payload = await response.json() as typeof payload; }
    catch { throw new Error("Cloudflare Analytics trả về phản hồi không đọc được."); }
    if (!response.ok || payload.errors?.length) {
      const message = payload.errors?.map((error) => error.message).filter(Boolean).join("; ").slice(0, 500);
      throw new Error(message || `Không truy vấn được Cloudflare Analytics (HTTP ${response.status}). Kiểm tra token Account Analytics:Read và tên bucket.`);
    }
    const data = payload.data ?? {};
    const account = data.viewer?.accounts?.[0];
    if (!account) throw new Error("Cloudflare không trả dữ liệu cho tài khoản đã cấu hình.");
    const operationDays = range.dailyWindows.map((window, index) => ({
      date: window.date,
      rows: operationRows(account[`operationsDay${index}`]),
    }));
    const latestOperationSample = Array.isArray(account.latestOperationSample) ? account.latestOperationSample : [];
    const operationsLimitReached = operationDays.some((item) => item.rows.length >= OPERATIONS_LIMIT_PER_DAY);
    return summarizeR2Analytics(data, range.days, new Date().toISOString(), { from: startDate, to: endDate }, {
      operationDays,
      calendarDates: range.dailyWindows.map((window) => window.date),
      operationsLimitReached,
      latestOperationsAt: latestTimestamp(latestOperationSample, (row) => row.dimensions?.datetime),
    });
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") throw new Error("Cloudflare Analytics phản hồi quá chậm; hãy thử lại sau.");
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}
