/** Convert MySQL UNIX_TIMESTAMP(...)*1000 output into a canonical instant. */
export function chatTimestampFromEpochMilliseconds(value: number | string | null | undefined): string | null {
  if (value === null || value === undefined || value === "") return null;
  const milliseconds = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(milliseconds) || milliseconds < 0) return null;
  const date = new Date(milliseconds);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}
