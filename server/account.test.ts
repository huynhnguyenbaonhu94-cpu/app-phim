import { describe, expect, it } from "vitest";
import { appRouter } from "./routers";
import type { TrpcContext } from "./_core/context";

describe("account procedures", () => {
  it("requires an authenticated user for favorites", async () => {
    const caller = appRouter.createCaller({ user: undefined, req: {} as TrpcContext["req"], res: {} as TrpcContext["res"] });
    await expect(caller.account.favorites()).rejects.toMatchObject({ code: "UNAUTHORIZED" });
  });

  it("requires an authenticated user before recording watch history", async () => {
    const caller = appRouter.createCaller({ user: undefined, req: {} as TrpcContext["req"], res: {} as TrpcContext["res"] });
    await expect(caller.account.recordHistory({ movieSlug: "demo-movie", movieName: "Demo Movie" })).rejects.toMatchObject({ code: "UNAUTHORIZED" });
  });

  it("requires authentication for device management, password changes and sync", async () => {
    const caller = appRouter.createCaller({ user: undefined, sessionId: null, sessionInvalid: false, req: {} as TrpcContext["req"], res: {} as TrpcContext["res"] });
    await expect(caller.account.devices()).rejects.toMatchObject({ code: "UNAUTHORIZED" });
    await expect(caller.account.heartbeat()).rejects.toMatchObject({ code: "UNAUTHORIZED" });
    await expect(caller.account.logoutAll()).rejects.toMatchObject({ code: "UNAUTHORIZED" });
    await expect(caller.account.changePassword({ currentPassword: "old-password", newPassword: "new-password-123" })).rejects.toMatchObject({ code: "UNAUTHORIZED" });
    await expect(caller.account.sync({ favorites: [], history: [] })).rejects.toMatchObject({ code: "UNAUTHORIZED" });
  });

  it("requires a revocable DB-backed session for session management", async () => {
    const caller = appRouter.createCaller({
      user: { id: 4, openId: "local_4", name: "User", email: "user@example.com", passwordHash: "secret-hash", loginMethod: "email", role: "user", createdAt: new Date(), updatedAt: new Date(), lastSignedIn: new Date() },
      sessionId: null, sessionInvalid: false, req: {} as TrpcContext["req"], res: {} as TrpcContext["res"],
    });
    await expect(caller.account.devices()).rejects.toMatchObject({ code: "UNAUTHORIZED" });
    await expect(caller.account.sync({ favorites: [], history: [] })).rejects.toMatchObject({ code: "UNAUTHORIZED" });
  });

  it("does not expose password hashes or open IDs from auth.me", async () => {
    const caller = appRouter.createCaller({
      user: { id: 8, openId: "local_8", name: "Private User", email: "safe@example.com", passwordHash: "scrypt-v1$secret", loginMethod: "email", role: "user", createdAt: new Date(), updatedAt: new Date(), lastSignedIn: new Date() },
      sessionId: "db-session", sessionInvalid: false, req: {} as TrpcContext["req"], res: {} as TrpcContext["res"],
    });
    const user = await caller.auth.me();
    expect(user).toMatchObject({ id: 8, email: "safe@example.com" });
    expect(user).not.toHaveProperty("passwordHash");
    expect(user).not.toHaveProperty("openId");
  });
});
