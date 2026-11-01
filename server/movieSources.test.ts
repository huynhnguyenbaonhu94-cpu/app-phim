import { describe, expect, it } from "vitest";
import { toWebVTT } from "./movieSources";

describe("toWebVTT", () => {
  it("converts common SRT timestamps with hours, minutes, and milliseconds", () => {
    const converted = toWebVTT("1\n00:00:01,250 --> 00:00:03,500\nHi\n");
    expect(converted).toContain("00:00:01.250 --> 00:00:03.500");
    expect(converted).toContain("WEBVTT");
  });

  it("normalizes minute-second SRT timestamps accepted by many sidecar sources", () => {
    const converted = toWebVTT("00:12,5 --> 01:04,75\nHello\n");
    expect(converted).toContain("00:12.500 --> 01:04.750");
  });

  it("normalizes second-only timestamps and already-headered WebVTT without duplicating its header", () => {
    const converted = toWebVTT("\uFEFFWEBVTT\n\n00:02,25 --> 00:04,5\nCaption\n");
    expect(converted).toContain("00:02.250 --> 00:04.500");
    expect(converted.match(/^WEBVTT/gm)).toHaveLength(1);
  });
});
