import { describe, expect, it } from "vitest";
import { storageBackend, storageDelete, storagePut, storagePutPublic, storagePutPublicStable, storageRead, testR2Connection } from "./r2Storage";

describe("R2-compatible storage adapter", () => {
  it("uploads, downloads and cleans up a private local fallback object", async () => {
    const keyPrefix = `tests/storage-${Date.now()}`;
    const uploaded = await storagePut(`${keyPrefix}.txt`, Buffer.from("private test object"), "text/plain");
    expect(uploaded.backend).toBe("local");
    expect(await storageBackend()).toBe("local");
    expect((await storageRead(uploaded.key)).toString("utf8")).toBe("private test object");
    await storageDelete(uploaded.key);
    await expect(storageRead(uploaded.key)).rejects.toThrow();
  });

  it("does not pretend local fallback is an R2 connectivity success", async () => {
    await expect(testR2Connection()).rejects.toThrow(/R2 chưa được cấu hình/);
  });

  it("reads legacy special-chat objects saved with a hashed storage key", async () => {
    if (await storageBackend() !== "local") return;
    const legacyKey = `special-chat/legacy-${Date.now()}.jpg`;
    const payload = Buffer.from("legacy private chat media");
    const uploaded = await storagePut(legacyKey, payload, "image/jpeg");
    try {
      expect(uploaded.key).not.toBe(legacyKey);
      expect(await storageRead(legacyKey)).toEqual(payload);
    } finally {
      await storageDelete(uploaded.key);
    }
  });

  it("stores public assets in a distinct public-assets namespace", async () => {
    const uploaded = await storagePutPublic(`movie-images/test-${Date.now()}.png`, Buffer.from("public image"), "image/png");
    expect(uploaded.backend).toBe("local");
    expect(uploaded.key).toMatch(/^public-assets\/movie-images\//);
    expect(uploaded.url).toContain("/api/public-storage/public-assets/movie-images/");
    expect((await storageRead(uploaded.key)).toString("utf8")).toBe("public image");
    await storageDelete(uploaded.key);
  });

  it("stores content-addressed artwork at its exact stable public key", async () => {
    if (await storageBackend() !== "local") return;
    const key = `movie-artwork/tests/${Date.now()}-content-hash.jpg`;
    const payload = Buffer.from([0xff, 0xd8, 0xff, 0x01]);
    const uploaded = await storagePutPublicStable(key, payload, "image/jpeg");
    try {
      expect(uploaded.key).toBe(`public-assets/${key}`);
      expect(uploaded.url).toBe(`/api/public-storage/public-assets/${key}`);
      expect(await storageRead(uploaded.key)).toEqual(payload);
    } finally {
      await storageDelete(uploaded.key);
    }
  });
});
