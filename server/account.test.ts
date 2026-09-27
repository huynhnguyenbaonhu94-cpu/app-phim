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
});
