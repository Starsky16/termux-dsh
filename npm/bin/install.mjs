#!/usr/bin/env node
// npm postinstall：下载并解压对应 Release 的运行时。
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { download, parseSha256File, releaseUrl, verifySha256 } from "../lib/download.mjs";
import { fixBinShebang, fixEntrypoint, globalBinDir, repatchL2, runProfileSetup } from "../lib/setup.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const pkgRoot = join(here, "..");
const pkg = JSON.parse(readFileSync(join(pkgRoot, "package.json"), "utf8"));
const runtimeDir = join(pkgRoot, "runtime");

const skipPlatform = process.env.TDSH_NPM_SKIP_PLATFORM_CHECK === "1";
if (!skipPlatform) {
  if (process.platform !== "android" || process.arch !== "arm64") {
    console.error(
      `termux-dsh 只支持 Termux/Android arm64（当前 ${process.platform}-${process.arch}）。\n` +
        `请改用 GitHub Release 的 .deb 或 bootstrap.sh。`
    );
    process.exit(1);
  }
}

const version = pkg.version;
const tgzName = "dsh-termux.tgz";
const shaName = "dsh-termux.tgz.sha256";

async function main() {
  const work = await mkdtemp(join(tmpdir(), "termux-dsh-npm-"));
  const tgz = join(work, tgzName);
  const shaFile = join(work, shaName);
  try {
    console.log(`termux-dsh: 下载 ${version} 运行时（约 133 MB）…`);
    await download(releaseUrl(version, tgzName), tgz);
    await download(releaseUrl(version, shaName), shaFile);
    const expected = parseSha256File(readFileSync(shaFile, "utf8"));
    if (!(await verifySha256(tgz, expected))) {
      throw new Error("sha256 校验失败，拒绝安装");
    }

    rmSync(runtimeDir, { recursive: true, force: true });
    mkdirSync(runtimeDir, { recursive: true });
    execFileSync("tar", ["-xzf", tgz, "-C", runtimeDir, "--strip-components=1"], { stdio: "inherit" });
    if (!existsSync(join(runtimeDir, "lib", "bin.js"))) {
      throw new Error("解压后缺少 lib/bin.js，运行时包不完整");
    }

    // npm 的 .bin 是 symlink，真正生效的是包内入口脚本，优先修它。
    fixEntrypoint(join(pkgRoot, "bin", "cli.mjs"));
    // 旧版 npm 会写 shim 文件（非 symlink），一并处理；两者都只动 env-node shim。
    fixBinShebang(join(pkgRoot, "..", ".bin"));
    const binDir = globalBinDir();
    if (binDir) fixBinShebang(binDir);
    runProfileSetup(join(pkgRoot, "share"));
    repatchL2(runtimeDir);
    console.log(`termux-dsh: 安装完成（${version}）。`);
  } finally {
    await rm(work, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(`termux-dsh: 安装失败：${error.message}`);
  rmSync(runtimeDir, { recursive: true, force: true });
  console.error("可改用 bootstrap.sh 或 GitHub Release 的 .deb 安装。");
  process.exit(1);
});
