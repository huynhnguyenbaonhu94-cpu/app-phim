import type { CreateExpressContextOptions } from "@trpc/server/adapters/express";
import { createHash, randomUUID } from "node:crypto";
import { COOKIE_NAME, ONE_YEAR_MS } from "@shared/const";
import type { User } from "../../drizzle/schema";
import { createDeviceSession, DeviceLimitError } from "../db";
import { authenticateLocalRequest, createLocalSession } from "../localAuth";
import { getSessionCookieOptions } from "./cookies";

function legacyDeviceLabel(userAgent: string) {
  if (/iphone|ipad|ipod/i.test(userAgent)) return "Thiết bị iOS (phiên cũ)";
  if (/android/i.test(userAgent)) return "Thiết bị Android (phiên cũ)";
  if (/macintosh|mac os/i.test(userAgent)) return "Trình duyệt macOS (phiên cũ)";
  if (/windows/i.test(userAgent)) return "Trình duyệt Windows (phiên cũ)";
  if (/linux/i.test(userAgent)) return "Trình duyệt Linux (phiên cũ)";
  return "Trình duyệt web (phiên cũ)";
}

export type TrpcContext = {
  req: CreateExpressContextOptions["req"];
  res: CreateExpressContextOptions["res"];
  user: User | null;
  sessionId: string | null;
  sessionInvalid: boolean;
};

export async function createContext(
  opts: CreateExpressContextOptions
): Promise<TrpcContext> {
  let auth: Awaited<ReturnType<typeof authenticateLocalRequest>> = { user: null, sessionId: null, sessionInvalid: false };

  try {
    auth = await authenticateLocalRequest(opts.req);
    if (auth.user && !auth.sessionId && auth.legacyToken) {
      const sessionId = randomUUID();
      const deviceId = `legacy-${createHash("sha256").update(auth.legacyToken).digest("hex").slice(0, 48)}`;
      const expiresAt = new Date(Date.now() + ONE_YEAR_MS);
      const session = await createDeviceSession({
        userId: auth.user.id, sessionId, deviceId,
        deviceName: legacyDeviceLabel(opts.req.get("user-agent") || ""),
        ipAddress: String(opts.req.ip || "").slice(0, 45) || null,
        expiresAt, reuseExistingDeviceSession: true,
      });
      const token = await createLocalSession(auth.user, session.sessionId, session.expiresAt);
      opts.res.cookie(COOKIE_NAME, token, { ...getSessionCookieOptions(opts.req), maxAge: ONE_YEAR_MS });
      auth = { user: auth.user, sessionId: session.sessionId, sessionInvalid: false };
    }
  } catch (error) {
    // Public procedures remain available; a legacy account session at the
    // five-device limit must reauthenticate after another device is removed.
    if (error instanceof DeviceLimitError) {
      opts.res.clearCookie(COOKIE_NAME, getSessionCookieOptions(opts.req));
      auth = { user: null, sessionId: null, sessionInvalid: true };
    } else {
      auth = { user: null, sessionId: null, sessionInvalid: false };
    }
  }

  return {
    req: opts.req,
    res: opts.res,
    user: auth.user,
    sessionId: auth.sessionId,
    sessionInvalid: auth.sessionInvalid,
  };
}
