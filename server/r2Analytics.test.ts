import { describe, expect, it } from "vitest";
import { getR2AnalyticsRange, summarizeR2Analytics } from "./r2Analytics";

describe("R2 analytics summary", () => {
  it("groups operation classes, request status, daily storage peaks, and bandwidth", () => {
    const result = summarizeR2Analytics({
      viewer: { accounts: [{
        r2OperationsAdaptiveGroups: [
          { sum: { requests: 12 }, dimensions: { actionType: "PutObject", actionStatus: "success", datetime: "2026-11-01T10:00:00Z" } },
          { sum: { requests: 30 }, dimensions: { actionType: "GetObject", actionStatus: "success", datetime: "2026-11-01T11:00:00Z" } },
          { sum: { requests: 4 }, dimensions: { actionType: "DeleteObject", actionStatus: "success", datetime: "2026-11-02T11:00:00Z" } },
          { sum: { requests: 2 }, dimensions: { actionType: "NewOperation", actionStatus: "userError", datetime: "2026-11-02T11:00:00Z" } },
          { sum: { requests: 3 }, dimensions: { actionType: "ListObjectsV2", actionStatus: "success", datetime: "2026-11-02T11:30:00Z" } },
        ],
        r2StorageAdaptiveGroups: [
          { max: { payloadSize: 1024, metadataSize: 24, objectCount: 2, uploadCount: 0 }, dimensions: { datetime: "2026-11-01T00:00:00Z" } },
          { max: { payloadSize: 900, metadataSize: 10, objectCount: 9, uploadCount: 0 }, dimensions: { datetime: "2026-11-01T12:00:00Z" } },
          { max: { payloadSize: 2048, metadataSize: 24, objectCount: 3, uploadCount: 1 }, dimensions: { datetime: "2026-11-02T00:00:00Z" } },
          { max: { payloadSize: null, metadataSize: 50, objectCount: 4, uploadCount: 0 }, dimensions: { datetime: "2026-11-03T00:00:00Z" } },
        ],
        r2BandwidthUsageAdaptiveGroups: [
          { sum: { bytesUpload: 100, bytesDownload: 500 }, dimensions: { datetimeHour: "2026-11-01T10:00:00Z" } },
          { sum: { bytesUpload: 50, bytesDownload: 250 }, dimensions: { datetimeHour: "2026-11-02T10:00:00Z" } },
        ],
      }] } }, 7, "2026-11-02T10:00:00.000Z");

    expect(result.totals).toEqual({
      classA: 15,
      classB: 30,
      freeOperations: 4,
      otherOperations: 2,
      requestStatuses: { success: 49, userError: 2, internalError: 0, unknown: 0 },
      uploadBytes: 150,
      downloadBytes: 750,
    });
    expect(result.current).toEqual({
      storageBytes: 2072,
      objectCount: 3,
      pendingMultipartUploads: 1,
      sampleAt: "2026-11-02T00:00:00.000Z",
    });
    expect(result.averages).toEqual({ storageBytes: 1560, sampledDays: 2 });
    expect(result.distribution.find((row) => row.actionType === "DeleteObject")?.operationClass).toBe("free");
    expect(result.distribution.find((row) => row.actionType === "ListObjectsV2")?.operationClass).toBe("A");
    expect(result.daily).toHaveLength(2);
    expect(result.daily[0]).toMatchObject({ date: "2026-11-01", classA: 12, classB: 30, bytesUpload: 100, bytesDownload: 500, storageBytes: 1048 });
    expect(result.daily[1]).toMatchObject({ date: "2026-11-02", classA: 3, other: 2, bytesUpload: 50, bytesDownload: 250, storageBytes: 2072 });
    expect(result.sourceTimestamps).toEqual({
      operations: "2026-11-02T11:30:00.000Z",
      storage: "2026-11-02T00:00:00.000Z",
      bandwidth: "2026-11-02T10:00:00.000Z",
    });
    expect(result.completeness).toEqual({ operationsLimitReached: false, storageLimitReached: false, bandwidthLimitReached: false });
  });

  it("classifies every operation in Cloudflare's published Class A/B/free lists", () => {
    const classA = ["ListBuckets", "PutBucket", "ListObjects", "ListObjectsV2", "PutObject", "CopyObject", "CompleteMultipartUpload", "CreateMultipartUpload", "LifecycleStorageTierTransition", "ListMultipartUploads", "UploadPart", "UploadPartCopy", "ListParts", "PutBucketEncryption", "PutBucketCors", "PutBucketLifecycleConfiguration"];
    const classB = ["HeadBucket", "HeadObject", "GetObject", "UsageSummary", "GetBucketEncryption", "GetBucketLocation", "GetBucketCors", "GetBucketLifecycleConfiguration"];
    const free = ["DeleteObject", "DeleteBucket", "AbortMultipartUpload"];
    const rows = [...classA, ...classB, ...free].map((actionType) => ({ sum: { requests: 1 }, dimensions: { actionType, actionStatus: "success", datetime: "2026-11-02T09:00:00Z" } }));
    const result = summarizeR2Analytics({ viewer: { accounts: [{ r2OperationsAdaptiveGroups: rows }] } }, 1);
    expect(result.totals.classA).toBe(classA.length);
    expect(result.totals.classB).toBe(classB.length);
    expect(result.totals.freeOperations).toBe(free.length);
  });

  it("sums daily aggregate rows into exact Class A/B period totals", () => {
    const result = summarizeR2Analytics({
      viewer: { accounts: [{
        latestOperationSample: [{ dimensions: { datetime: "2026-11-02T09:45:00.000Z" } }],
      }] },
    }, 2, "2026-11-02T10:00:00.000Z", { from: "2026-10-31T17:00:00.000Z", to: "2026-11-02T10:00:00.000Z" }, {
      operationDays: [
        { date: "2026-11-01", rows: [
          { sum: { requests: 40_000 }, dimensions: { actionType: "PutObject", actionStatus: "success" } },
          { sum: { requests: 25_000 }, dimensions: { actionType: "GetObject", actionStatus: "success" } },
        ] },
        { date: "2026-11-02", rows: [
          { sum: { requests: 30_850 }, dimensions: { actionType: "PutObject", actionStatus: "success" } },
          { sum: { requests: 15_650 }, dimensions: { actionType: "GetObject", actionStatus: "success" } },
        ] },
      ],
      calendarDates: ["2026-11-01", "2026-11-02"],
      operationsLimitReached: false,
      latestOperationsAt: "2026-11-02T09:45:00.000Z",
    });
    expect(result.totals.classA).toBe(70_850);
    expect(result.totals.classB).toBe(40_650);
    expect(result.daily.map(({ date, classA, classB }) => ({ date, classA, classB }))).toEqual([
      { date: "2026-11-01", classA: 40_000, classB: 25_000 },
      { date: "2026-11-02", classA: 30_850, classB: 15_650 },
    ]);
    expect(result.sourceTimestamps.operations).toBe("2026-11-02T09:45:00.000Z");
    expect(result.completeness.operationsLimitReached).toBe(false);
  });

  it("returns an actionable error when the account dataset is empty", () => {
    expect(() => summarizeR2Analytics({ viewer: { accounts: [] } }, 7)).toThrow(/không trả dữ liệu/i);
  });

  it("groups UTC samples using Vietnam's GMT+7 day boundary", () => {
    const result = summarizeR2Analytics({ viewer: { accounts: [{
      r2OperationsAdaptiveGroups: [{ sum: { requests: 1 }, dimensions: { actionType: "GetObject", datetime: "2026-11-01T20:00:00Z" } }],
    }] } }, 7);
    expect(result.daily[0]?.date).toBe("2026-11-02");
  });

  it("uses seven Vietnam calendar dates and a half-open current-time range", () => {
    const range = getR2AnalyticsRange("last7Days", new Date("2026-11-02T10:00:00.000Z"));
    expect(range.days).toBe(7);
    expect(range.startDate.toISOString()).toBe("2026-10-26T17:00:00.000Z");
    expect(range.endDate.toISOString()).toBe("2026-11-02T10:00:00.000Z");
    expect(range.dailyWindows[0]).toMatchObject({ date: "2026-10-27", startDate: new Date("2026-10-26T17:00:00.000Z") });
  });

  it("uses the first Vietnam calendar day of the month for month-to-date comparison", () => {
    const range = getR2AnalyticsRange("monthToDate", new Date("2026-11-02T10:00:00.000Z"));
    expect(range.days).toBe(2);
    expect(range.dailyWindows.map(({ date }) => date)).toEqual(["2026-11-01", "2026-11-02"]);
    expect(range.startDate.toISOString()).toBe("2026-10-31T17:00:00.000Z");
    expect(range.endDate.toISOString()).toBe("2026-11-02T10:00:00.000Z");
  });
});
