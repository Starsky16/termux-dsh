#!/usr/bin/env node
// termux-dsh 启动器：把参数透传给解压后的运行时 bin.js。
import { spawn, execFileSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { existsSync } from "node:fs";

const here = dirname(fileURLToPath(import.meta.url));
const runtimeBin = join(here, "..", "runtime", "lib", "bin.js");

// npm 12 默认拦截未审批的 install script，此时 postinstall 不会跑；
// 首次启动时补一次下载，保证安装后仍然可用。
if (!existsSync(runtimeBin)) {
  console.log("termux-dsh: runtime 未就绪，正在下载（约 133 MB）…");
  try {
    execFileSync(process.execPath, [join(here, "install.mjs")], { stdio: "inherit", env: process.env });
  } catch {
    console.error("termux-dsh: 自动安装失败，请检查网络，或改用 bootstrap.sh / GitHub Release 的 .deb。");
    process.exit(1);
  }
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
