import { describe, expect, it } from "vitest";
import { hashPassword, verifyPassword } from "./localAuth";

describe("local email authentication", () => {
  it("hashes passwords and verifies only the original password", async () => {
    const hash = await hashPassword("Correct horse battery staple");
    expect(hash).toMatch(/^scrypt-v1\$/);
    expect(hash).not.toContain("Correct horse battery staple");
    expect(await verifyPassword("Correct horse battery staple", hash)).toBe(true);
    expect(await verifyPassword("wrong-password", hash)).toBe(false);
  });

  it("rejects malformed password hashes", async () => {
    expect(await verifyPassword("anything", "not-a-valid-hash")).toBe(false);
  });
});
