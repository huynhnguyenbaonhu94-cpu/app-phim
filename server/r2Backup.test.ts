import { describe, expect, it } from "vitest";
import { getVietnamBackupClock } from "./r2Backup";

describe("getVietnamBackupClock", () => {
  it("converts UTC to Vietnam local date and hour", () => {
    expect(getVietnamBackupClock(new Date("2026-10-30T19:00:00.000Z"))).toEqual({
      hour: 2,
      dateKey: "2026-10-31",
      weekKey: "2026-10-26",
    });
  });

  it("switches the weekly slot at Vietnam midnight on Monday", () => {
    expect(getVietnamBackupClock(new Date("2026-11-01T16:59:00.000Z"))).toEqual({
      hour: 23,
      dateKey: "2026-11-01",
      weekKey: "2026-10-26",
    });
    expect(getVietnamBackupClock(new Date("2026-11-01T17:00:00.000Z"))).toEqual({
      hour: 0,
      dateKey: "2026-11-02",
      weekKey: "2026-11-02",
    });
  });
});
