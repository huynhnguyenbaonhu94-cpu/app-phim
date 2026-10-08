import type { Request } from "express";
import { TRPCError } from "@trpc/server";

type Bucket = { count: number; resetAt: number };

// Lightweight process-local limiter. It protects a single API instance from
// bursts; production deployments with multiple instances should also add a
// shared gateway/WAF limiter (Redis, Cloudflare, etc.).
const buckets = new Map<string, Bucket>();
const MAX_BUCKETS = 10_000;

function requestIdentity(req: Request) {
  const forwarded = req.headers["x-forwarded-for"];
  const ip = typeof forwarded === "string" ? forwarded.split(",")[0]?.trim() : req.ip;
  return (ip || req.get("user-agent") || "unknown").slice(0, 180);
}

function compactBuckets(now: number) {
  if (buckets.size < MAX_BUCKETS) return;
  for (const [key, bucket] of Array.from(buckets.entries())) {
    if (bucket.resetAt <= now) buckets.delete(key);
    if (buckets.size < MAX_BUCKETS) break;
  }
}

export function enforceRateLimit(
  req: Request,
  scope: string,
  limit: number,
  windowMs: number,
  discriminator = "",
) {
  const now = Date.now();
  compactBuckets(now);
  const key = `${scope}:${requestIdentity(req)}:${discriminator}`;
  const current = buckets.get(key);
  if (!current || current.resetAt <= now) {
    buckets.set(key, { count: 1, resetAt: now + windowMs });
    return;
  }
  if (current.count >= limit) {
    const retryAfter = Math.max(1, Math.ceil((current.resetAt - now) / 1000));
    throw new TRPCError({
      code: "TOO_MANY_REQUESTS",
      message: `Bạn thao tác quá nhanh. Vui lòng thử lại sau ${retryAfter} giây.`,
    });
  }
  current.count += 1;
}

export function clearRateLimit(scope: string, req: Request, discriminator = "") {
  const key = `${scope}:${requestIdentity(req)}:${discriminator}`;
  buckets.delete(key);
}

export const SECURITY_LIMITS = {
  registerPerIp: { limit: 3, windowMs: 15 * 60_000 },
  loginPerIp: { limit: 8, windowMs: 10 * 60_000 },
  loginPerEmail: { limit: 5, windowMs: 10 * 60_000 },
  qrCreatePerIp: { limit: 6, windowMs: 10 * 60_000 },
  qrCompletePerIp: { limit: 6, windowMs: 10 * 60_000 },
  accountWritePerUser: { limit: 60, windowMs: 60_000 },
  commentPerUser: { limit: 20, windowMs: 60_000 },
} as const;
