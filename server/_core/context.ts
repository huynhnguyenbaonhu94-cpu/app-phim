import type { CreateExpressContextOptions } from "@trpc/server/adapters/express";
import type { User } from "../../drizzle/schema";
import { authenticateLocalRequestWithSession } from "../localAuth";
import type { AccountSession } from "../../drizzle/schema";

export type TrpcContext = {
  req: CreateExpressContextOptions["req"];
  res: CreateExpressContextOptions["res"];
  user: User | null;
  session: AccountSession | null;
};

export async function createContext(
  opts: CreateExpressContextOptions
): Promise<TrpcContext> {
  let user: User | null = null;
  let session: AccountSession | null = null;

  try {
    const auth = await authenticateLocalRequestWithSession(opts.req);
    user = auth.user;
    session = auth.session ?? null;
  } catch (error) {
    // Authentication is optional for public procedures.
    user = null;
    session = null;
  }

  return {
    req: opts.req,
    res: opts.res,
    user,
    session,
  };
}
