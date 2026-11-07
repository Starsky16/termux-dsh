import { test } from "node:test";
import assert from "node:assert/strict";
import { releaseTag, releaseUrl, verifySha256 } from "../lib/download.mjs";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";

test("releaseTag 加 v 前缀", () => {
  assert.equal(releaseTag("0.2.2-rc.1-tdsh.1"), "v0.2.2-rc.1-tdsh.1");
});

test("releaseUrl 指向 GitHub Release 资产", () => {
  assert.equal(
    releaseUrl("0.2.2-rc.1-tdsh.1", "dsh-termux.tgz"),
    "https://github.com/Starsky16/termux-dsh/releases/download/v0.2.2-rc.1-tdsh.1/dsh-termux.tgz"
  );
});

test("TDSH_RELEASE_BASE 覆盖基址", () => {
  const old = process.env.TDSH_RELEASE_BASE;
  process.env.TDSH_RELEASE_BASE = "https://mirror.example/rel";
  try {
    assert.equal(releaseUrl("1.0.0", "x.tgz"), "https://mirror.example/rel/v1.0.0/x.tgz");
  } finally {
    if (old === undefined) delete process.env.TDSH_RELEASE_BASE;
    else process.env.TDSH_RELEASE_BASE = old;
  }
});

test("verifySha256 校验通过", async () => {
  const dir = await mkdtemp(join(tmpdir(), "tdsh-dl-"));
  const file = join(dir, "a.bin");
  await writeFile(file, "hello");
  const digest = createHash("sha256").update("hello").digest("hex");
  assert.equal(await verifySha256(file, digest), true);
});

test("verifySha256 不匹配返回 false", async () => {
  const dir = await mkdtemp(join(tmpdir(), "tdsh-dl-"));
  const file = join(dir, "a.bin");
  await writeFile(file, "hello");
  assert.equal(await verifySha256(file, "0".repeat(64)), false);
});
