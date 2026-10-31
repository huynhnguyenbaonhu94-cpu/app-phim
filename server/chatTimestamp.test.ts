import { describe, expect, it } from "vitest";
import { chatTimestampFromEpochMilliseconds } from "./chatTimestamp";

describe("chatTimestampFromEpochMilliseconds", () => {
  it("converts a database instant to canonical UTC ISO without applying host timezone", () => {
    const instant = Date.UTC(2026, 9, 30, 7, 58, 52);
    expect(chatTimestampFromEpochMilliseconds(instant)).toBe("2026-10-30T07:58:52.000Z");
  });

  it("accepts numeric strings returned by MySQL drivers", () => {
    const instant = Date.UTC(2026, 9, 30, 7, 58, 52);
    expect(chatTimestampFromEpochMilliseconds(String(instant))).toBe("2026-10-30T07:58:52.000Z");
  });

  it("returns null instead of a misleading epoch for missing or invalid values", () => {
    expect(chatTimestampFromEpochMilliseconds(null)).toBeNull();
    expect(chatTimestampFromEpochMilliseconds("not-a-time")).toBeNull();
  });
});
