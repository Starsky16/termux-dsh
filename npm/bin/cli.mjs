#!/usr/bin/env node
// termux-dsh 启动器：把参数透传给解压后的运行时 bin.js。
import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { existsSync } from "node:fs";

const here = dirname(fileURLToPath(import.meta.url));
const runtimeBin = join(here, "..", "runtime", "lib", "bin.js");

if (!existsSync(runtimeBin)) {
  console.error("termux-dsh: runtime 未安装，请重跑 `npm rebuild -g termux-dsh` 或重新安装。");
  process.exit(1);
}

const child = spawn(process.execPath, [runtimeBin, ...process.argv.slice(2)], {
  stdio: "inherit",
  env: process.env,
});
child.on("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }
  process.exit(code ?? 1);
});
